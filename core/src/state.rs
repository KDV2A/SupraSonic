use std::sync::{Arc, Mutex};
use crossbeam_channel::{unbounded, Sender};
use crate::{AudioEngine, audio::AudioPacket};
use crate::diarization::DiarizationService;

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
    diarization: Arc<DiarizationService>,
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
    pub fn new(storage_path: String) -> Self {
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
            while let Ok(packet) = rx.recv() {
                match packet {
                    AudioPacket::Format(sr) => {
                        tracing::info!("Background: Audio stream started at {} Hz", sr);
                    }
                    AudioPacket::Samples(data) => {
                        // Streaming Mode: Forward immediately to listener (Swift/Inference)
                        if let Ok(l) = listener_clone.lock() {
                            if let Some(listener) = l.as_ref() {
                                listener.on_audio_data(data);
                            }
                        }
                    }
                    AudioPacket::Level(lvl) => {
                        if let Ok(l) = listener_clone.lock() {
                            if let Some(listener) = l.as_ref() {
                                listener.on_level_changed(lvl);
                            }
                        }
                    }
                    AudioPacket::Flush => {
                         tracing::info!("Background: Flush processing (End of capture)");
                    }
                }
            }
        });

        Self {
            audio: Mutex::new(AudioEngine::new(tx.clone())),
            is_recording: Mutex::new(BoolState { value: false }),
            data_tx: tx,
            listener: listener,
            diarization: Arc::new(DiarizationService::new(storage_path)),
        }
    }
    
    pub fn register_speaker(&self, id: String, name: String) {
        self.diarization.register_speaker(id, name);
    }
    
    pub fn get_speaker_name(&self, id: String) -> String {
        self.diarization.get_speaker_name(id)
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

    pub fn flush(&self) -> Result<(), SupraSonicError> {
        let _ = self.data_tx.send(AudioPacket::Flush);
        Ok(())
    }
}

// --- Windows/C# Compatibility Layer ---

#[cfg(any(target_os = "windows", feature = "csharp"))]
mod c_api {
    use super::*;
    use std::sync::OnceLock;

    static APP_STATE: OnceLock<Arc<AppState>> = OnceLock::new();
    static mut AUDIO_CALLBACK: Option<extern "C" fn(*const f32, u32)> = None;
    static mut LEVEL_CALLBACK: Option<extern "C" fn(f32)> = None;

    struct CSharpListener;
    impl TranscriptionListener for CSharpListener {
        fn on_audio_data(&self, audio_data: Vec<f32>) {
            unsafe {
                if let Some(cb) = AUDIO_CALLBACK {
                    cb(audio_data.as_ptr(), audio_data.len() as u32);
                }
            }
        }
        fn on_level_changed(&self, level: f32) {
            unsafe {
                if let Some(cb) = LEVEL_CALLBACK {
                    cb(level);
                }
            }
        }
    }

    #[no_mangle]
    pub extern "C" fn suprasonic_init() {
        // Default path for C-API (Windows/Linux)
        let state = Arc::new(AppState::new("speakers.json".to_string()));
        state.set_listener(Box::new(CSharpListener));
        let _ = APP_STATE.set(state);
    }

    #[no_mangle]
    pub extern "C" fn suprasonic_set_audio_callback(cb: extern "C" fn(*const f32, u32)) {
        unsafe { AUDIO_CALLBACK = Some(cb); }
    }

    #[no_mangle]
    pub extern "C" fn suprasonic_set_level_callback(cb: extern "C" fn(f32)) {
        unsafe { LEVEL_CALLBACK = Some(cb); }
    }

    #[no_mangle]
    pub extern "C" fn suprasonic_start_recording() -> i32 {
        if let Some(state) = APP_STATE.get() {
            match state.start_recording() {
                Ok(_) => 0,
                Err(_) => -1,
            }
        } else { -2 }
    }

    #[no_mangle]
    pub extern "C" fn suprasonic_stop_recording() -> i32 {
        if let Some(state) = APP_STATE.get() {
            match state.stop_recording() {
                Ok(_) => 0,
                Err(_) => -1,
            }
        } else { -2 }
    }

    #[no_mangle]
    pub extern "C" fn suprasonic_flush() -> i32 {
        if let Some(state) = APP_STATE.get() {
            match state.flush() {
                Ok(_) => 0,
                Err(_) => -1,
            }
        } else { -2 }
    }
}
