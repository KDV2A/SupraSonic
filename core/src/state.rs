use std::sync::{Arc, Mutex};
use crossbeam_channel::{unbounded, Sender};
use crate::{AudioEngine, audio::AudioPacket};

#[uniffi::export(callback_interface)]
pub trait TranscriptionListener: Send + Sync {
    fn on_audio_data(&self, audio_data: Vec<f32>);
    fn on_level_changed(&self, level: f32);
}

#[derive(uniffi::Object)]
pub struct AppState {
    audio: Mutex<AudioEngine>,
    is_recording: Mutex<BoolState>,
    data_tx: Sender<AudioPacket>,
    listener: Arc<Mutex<Option<Arc<dyn TranscriptionListener>>>>,
}

struct BoolState {
    value: bool,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum SupraSonicError {
    #[error("Audio error: {0}")]
    Audio(String),
    #[error("Inference error: {0}")]
    Inference(String),
    #[error("Lock error: {0}")]
    Lock(String),
    #[error("General error: {0}")]
    General(String),
}

#[uniffi::export]
impl AppState {
    #[uniffi::constructor]
    pub fn new() -> Self {
        use std::sync::Once;
        static INIT: Once = Once::new();
        INIT.call_once(|| {
            tracing_subscriber::fmt::init();
        });

        let (tx, rx) = unbounded();
        let listener: Arc<Mutex<Option<Arc<dyn TranscriptionListener>>>> = Arc::new(Mutex::new(None));
        
        // Spawn Background Processing Loop
        let listener_clone = listener.clone();
        std::thread::spawn(move || {
            let mut audio_buffer: Vec<f32> = Vec::new();
            let mut sample_rate = 48000;
            
            while let Ok(packet) = rx.recv() {
                match packet {
                    AudioPacket::Format(sr) => {
                        tracing::info!("Background: Sample Rate set to {}", sr);
                        sample_rate = sr;
                    }
                    AudioPacket::Samples(data) => {
                        audio_buffer.extend(data);
                    }
                    AudioPacket::Level(lvl) => {
                        if let Ok(l) = listener_clone.lock() {
                            if let Some(listener) = l.as_ref() {
                                listener.on_level_changed(lvl);
                            }
                        }
                    }
                    AudioPacket::Flush => {
                        if !audio_buffer.is_empty() {
                            tracing::info!("Background: Processing {} samples ({} Hz)...", audio_buffer.len(), sample_rate);
                            
                            // Resample to 16kHz for Parakeet
                            let processed_audio = if sample_rate != 16000 {
                                match resample_audio(&audio_buffer, sample_rate, 16000) {
                                    Ok(resampled) => {
                                        tracing::info!("Resampled: {} -> {} samples", audio_buffer.len(), resampled.len());
                                        resampled
                                    },
                                    Err(e) => {
                                        tracing::error!("Resampling failed: {}", e);
                                        audio_buffer.clone() 
                                    }
                                }
                            } else {
                                audio_buffer.clone()
                            };

                            // Send directly to Swift listener
                            if let Ok(l) = listener_clone.lock() {
                                if let Some(listener) = l.as_ref() {
                                    tracing::info!("Background: Dispatching audio to Swift...");
                                    listener.on_audio_data(processed_audio);
                                } else {
                                    tracing::warn!("Background: No listener registered, dropping audio");
                                }
                            }
                            
                            audio_buffer.clear();
                        }
                    }
                }
            }
        });

        Self {
            audio: Mutex::new(AudioEngine::new(tx.clone())),
            is_recording: Mutex::new(BoolState { value: false }),
            data_tx: tx,
            listener: listener, 
        }
    }

    pub fn set_listener(&self, listener: Box<dyn TranscriptionListener>) {
        if let Ok(mut l) = self.listener.lock() {
            *l = Some(Arc::from(listener));
        }
    }

    pub fn start_recording(&self) -> Result<(), SupraSonicError> {
        let audio = self.audio.lock().map_err(|e: std::sync::PoisonError<_>| SupraSonicError::Lock(e.to_string()))?;
        audio.start_capture().map_err(|e| SupraSonicError::Audio(e.to_string()))?;
        
        let mut rec = self.is_recording.lock().map_err(|e: std::sync::PoisonError<_>| SupraSonicError::Lock(e.to_string()))?;
        rec.value = true;
        
        tracing::info!("State: Recording started");
        Ok(())
    }

    pub fn stop_recording(&self) -> Result<(), SupraSonicError> {
        let audio = self.audio.lock().map_err(|e: std::sync::PoisonError<_>| SupraSonicError::Lock(e.to_string()))?;
        audio.stop_capture();
        
        let mut rec = self.is_recording.lock().map_err(|e: std::sync::PoisonError<_>| SupraSonicError::Lock(e.to_string()))?;
        rec.value = false;
        
        // Signal flush to processing loop
        let _ = self.data_tx.send(AudioPacket::Flush);
        
        tracing::info!("State: Recording stopped");
        Ok(())
    }
}

fn resample_audio(input: &[f32], from_rate: u32, to_rate: u32) -> anyhow::Result<Vec<f32>> {
    use rubato::{Resampler, Fft, FixedSync};
    use audioadapter_buffers::direct::SequentialSliceOfVecs;

    if input.is_empty() { return Ok(Vec::new()); }

    let chunk_size = 1024;
    let sub_chunks = 1;
    let channels = 1;
    
    let mut resampler = Fft::<f32>::new(
        from_rate as usize, 
        to_rate as usize, 
        chunk_size, 
        sub_chunks, 
        channels,
        FixedSync::Input
    )?;

    // Calculate approximate output size
    let ratio = to_rate as f64 / from_rate as f64;
    let mut output_buffer = Vec::with_capacity((input.len() as f64 * ratio) as usize + 1024);
    
    // FftFixedIn needs exact chunk size input
    let chunks = input.chunks(chunk_size);
    
    // Scratch buffers for rubato
    let mut input_frames = vec![vec![0.0; chunk_size]; channels]; 
    let max_output_frames = resampler.output_frames_max();
    let mut output_frames = vec![vec![0.0; max_output_frames]; channels];

    for chunk in chunks {
        // Copy chunk into input buffer with zero-padding if needed
        let len = chunk.len();
        input_frames[0][..len].copy_from_slice(chunk);
        if len < chunk_size {
             for i in len..chunk_size { input_frames[0][i] = 0.0; }
        }

        // Wrap in audioadapter
        let input_wrapper = SequentialSliceOfVecs::new(&input_frames, channels, chunk_size)
             .map_err(|e| anyhow::anyhow!("Adapter error: {:?}", e))?;
        let mut output_wrapper = SequentialSliceOfVecs::new_mut(&mut output_frames, channels, max_output_frames)
             .map_err(|e| anyhow::anyhow!("Adapter ref error: {:?}", e))?;

        let (in_len, out_len) = resampler.process_into_buffer(&input_wrapper, &mut output_wrapper, None)?;
        
        // Append to final buffer
        if out_len > 0 {
             output_buffer.extend_from_slice(&output_frames[0][..out_len]);
        }
    }

    Ok(output_buffer)
}
