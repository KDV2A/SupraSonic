uniffi::setup_scaffolding!();

pub mod state;
pub mod audio;
pub mod diarization;

pub use audio::AudioEngine;
