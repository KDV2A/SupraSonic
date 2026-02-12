use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use crossbeam_channel::{unbounded, Sender, Receiver};
use ringbuf::{HeapRb, traits::*};
use rubato::{Resampler, FastFixedIn, PolynomialDegree};
use std::sync::{Arc, Mutex};
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

// Internal config constants
const TARGET_SAMPLE_RATE: usize = 16000;
const ASR_CHUNK_MS: usize = 30; // ~30ms chunks
const ASR_CHUNK_SIZE: usize = (TARGET_SAMPLE_RATE * ASR_CHUNK_MS) / 1000; // 480 samples
const RING_BUFFER_SIZE: usize = 16000 * 5; // 5 seconds buffer

impl AudioEngine {
    pub fn new(data_tx: Sender<AudioPacket>) -> Self {
        let (cmd_tx, cmd_rx) = unbounded();
        
        std::thread::spawn(move || {
            let mut stream: Option<cpal::Stream> = None;
            let mut _stream_guard: Option<Arc<Mutex<bool>>> = None; // Keep alive check if needed

            while let Ok(cmd) = cmd_rx.recv() {
                match cmd {
                    AudioCommand::Start => {
                        if stream.is_some() { continue; }
                        
                        tracing::info!("Starting audio capture...");
                        match Self::build_stream(data_tx.clone()) {
                            Ok(s) => {
                                if let Err(e) = s.play() {
                                    tracing::error!("Failed to play stream: {}", e);
                                } else {
                                    stream = Some(s);
                                    tracing::info!("Audio stream started successfully");
                                }
                            },
                            Err(e) => tracing::error!("Failed to build stream: {}", e),
                        }
                    }
                    AudioCommand::Stop => {
                        if stream.is_some() {
                             tracing::info!("Stopping audio capture...");
                        }
                        stream = None; 
                        let _ = data_tx.send(AudioPacket::Flush);
                    }
                }
            }
        });

        Self {
            command_tx: cmd_tx,
        }
    }

    fn build_stream(data_tx: Sender<AudioPacket>) -> anyhow::Result<cpal::Stream> {
        let host = cpal::default_host();
        let device = host.default_input_device()
            .ok_or_else(|| anyhow::anyhow!("No input device found"))?;
        
        let config = device.default_input_config()?;
        let source_sample_rate = config.sample_rate().0 as usize;
        
        tracing::info!("Input device: {:?}, Source Rate: {}, Target Rate: {}", 
            device.name().unwrap_or_default(), source_sample_rate, TARGET_SAMPLE_RATE);

        // Notify of format (always 16kHz now)
        let _ = data_tx.send(AudioPacket::Format(TARGET_SAMPLE_RATE as u32));

        // Create Ring Buffer
        let rb = HeapRb::<f32>::new(RING_BUFFER_SIZE);
        let (mut producer, consumer) = rb.split();

        // Spawn separate processing thread to handle resampling/chunking
        std::thread::spawn(move || {
            Self::process_audio(consumer, source_sample_rate, data_tx);
        });

        // The audio callback only pushes to ring buffer (Real-time safe)
        let stream = device.build_input_stream(
            &config.into(),
            move |data: &[f32], _: &_| {
                let _ = producer.push_slice(data); 
            },
            move |err| {
                tracing::error!("Audio stream error: {}", err);
            },
            None
        )?;
        
        Ok(stream)
    }

    fn process_audio(
        mut consumer: impl Consumer<Item = f32>, 
        source_rate: usize, 
        data_tx: Sender<AudioPacket>
    ) {
        // ... (resampler setup same)
        // Setup Resampler if needed
        let mut resampler: Option<FastFixedIn<f32>> = if source_rate != TARGET_SAMPLE_RATE {
             let resample_ratio = TARGET_SAMPLE_RATE as f64 / source_rate as f64;
             let chunk_size = 1024; 
             match FastFixedIn::<f32>::new(
                resample_ratio,
                1.0,
                PolynomialDegree::Cubic,
                chunk_size, 
                1
            ) {
                Ok(r) => Some(r),
                Err(e) => {
                    tracing::error!("Failed to create resampler: {}", e);
                    return;
                }
            }
        } else {
            None
        };

        // Buffers
        let mut input_buffer = Vec::with_capacity(2048);
        let mut accumulated_samples = Vec::with_capacity(ASR_CHUNK_SIZE * 2);

        loop {
            // 1. Read from RingBuffer
            let available = consumer.occupied_len();
            if available == 0 {
                std::thread::sleep(std::time::Duration::from_millis(5));
                continue;
            }

            // If we have a resampler, we need specific chunk sizes
            if let Some(ref mut r) = resampler {
                let required_input = r.input_frames_next(); 
                
                if available >= required_input {
                    input_buffer.resize(required_input, 0.0);
                    let read_count = consumer.pop_slice(&mut input_buffer);
                    if read_count < required_input { continue; }

                    let waves_in = vec![input_buffer.clone()]; 
                    // 0.14.0 process returns Result<Vec<Vec<f32>>>
                    if let Ok(waves_out) = r.process(&waves_in, None) {
                         if let Some(out_channel) = waves_out.get(0) {
                             accumulated_samples.extend_from_slice(out_channel);
                         }
                    }
                }
            } else {
                // No resampling, just passthrough
                let chunk_to_read = available.min(1024);
                input_buffer.resize(chunk_to_read, 0.0);
                let _ = consumer.pop_slice(&mut input_buffer);
                accumulated_samples.extend_from_slice(&input_buffer);
            }

            // 2. Chunk for ASR (20-30ms)
            while accumulated_samples.len() >= ASR_CHUNK_SIZE {
                let chunk: Vec<f32> = accumulated_samples.drain(0..ASR_CHUNK_SIZE).collect();
                
                // Calculate level for UI
                let mut max = 0.0f32;
                for &s in &chunk {
                    let abs = s.abs();
                    if abs > max { max = abs };
                }
                
                // Send Level
                let _ = data_tx.send(AudioPacket::Level(max));
                // Send Samples
                let _ = data_tx.send(AudioPacket::Samples(chunk));
            }
        }
    }

    pub fn start_capture(&self) -> anyhow::Result<()> {
        self.command_tx.send(AudioCommand::Start).map_err(|e| anyhow::anyhow!("Failed to send start command: {}", e))?;
        Ok(())
    }

    pub fn stop_capture(&self) {
        let _ = self.command_tx.send(AudioCommand::Stop);
    }
}
