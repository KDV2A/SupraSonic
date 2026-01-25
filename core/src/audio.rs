use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use crossbeam_channel::{unbounded, Sender};
use tracing;

pub enum AudioPacket {
    Format(u32),
    Samples(Vec<f32>),
    Level(f32),
    Flush,
}

pub struct AudioEngine {
    command_tx: Sender<AudioCommand>,
}

enum AudioCommand {
    Start,
    Stop,
}

impl AudioEngine {
    pub fn new(data_tx: Sender<AudioPacket>) -> Self {
        let (tx, rx) = unbounded();
        
        std::thread::spawn(move || {
            let mut stream: Option<cpal::Stream> = None;
            
            while let Ok(cmd) = rx.recv() {
                match cmd {
                    AudioCommand::Start => {
                        if stream.is_some() { continue; }
                        
                        // Attempt to build stream with data sender
                        match Self::build_stream(data_tx.clone()) {
                            Ok(s) => {
                                if let Err(e) = s.play() {
                                    tracing::error!("Failed to play stream: {}", e);
                                } else {
                                    stream = Some(s);
                                    tracing::info!("Audio stream started");
                                }
                            },
                            Err(e) => tracing::error!("Failed to build stream: {}", e),
                        }
                    }
                    AudioCommand::Stop => {
                        stream = None; // Drop stream to stop
                        // We do NOT send Flush here automatically, let the controller handle logic
                        tracing::info!("Audio stream stopped");
                    }
                }
            }
        });

        Self {
            command_tx: tx,
        }
    }

    fn build_stream(data_tx: Sender<AudioPacket>) -> anyhow::Result<cpal::Stream> {
        let host = cpal::default_host();
        let device = host.default_input_device()
            .ok_or_else(|| anyhow::anyhow!("No input device found"))?;
        let config = device.default_input_config()?;
        let sample_rate = config.sample_rate().0;
        
        tracing::info!("Input device: {:?}, Sample Rate: {}", device.name()?, sample_rate);
        
        // Notify of format
        let _ = data_tx.send(AudioPacket::Format(sample_rate));
        
        let stream = device.build_input_stream(
            &config.into(),
            move |data: &[f32], _: &_| {
                if !data.is_empty() {
                    // Send samples for processing
                    let _ = data_tx.send(AudioPacket::Samples(data.to_vec()));
                    
                    // Simple peak amplitude calculation for visualizer
                    let mut max = 0.0f32;
                    for &s in data {
                        let abs = s.abs();
                        if abs > max { max = abs };
                    }
                    let _ = data_tx.send(AudioPacket::Level(max));
                }
            },
            move |err| {
                tracing::error!("Audio stream error: {}", err);
            },
            None
        )?;
        
        Ok(stream)
    }

    pub fn start_capture(&self) -> anyhow::Result<()> {
        self.command_tx.send(AudioCommand::Start).map_err(|e| anyhow::anyhow!("Failed to send start command: {}", e))?;
        Ok(())
    }

    pub fn stop_capture(&self) {
        let _ = self.command_tx.send(AudioCommand::Stop);
    }
}
