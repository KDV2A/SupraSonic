use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Speaker {
    pub id: String,
    pub name: String,
    pub embedding: Option<Vec<f32>>, // 192 (ECAPA) or 512 (x-vector)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Segment {
    pub start: f64,
    pub end: f64,
    pub text: String,
    pub speaker_id: String,
    pub is_final: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpeakerRegistry {
    pub speakers: HashMap<String, Speaker>,
}

impl SpeakerRegistry {
    pub fn new() -> Self {
        Self {
            speakers: HashMap::new(),
        }
    }
    
    pub fn add_speaker(&mut self, id: String, name: String) {
        // If ID exists, update name. If not, create new.
        if let Some(speaker) = self.speakers.get_mut(&id) {
            speaker.name = name;
        } else {
            self.speakers.insert(id.clone(), Speaker {
                id: id.clone(),
                name,
                embedding: None,
            });
        }
    }
    
    pub fn get_speaker_name(&self, id: &str) -> Option<String> {
        self.speakers.get(id).map(|s| s.name.clone())
    }

    // Placeholder for Embedding Matching
    pub fn assign_speaker(&self, _embedding: &[f32]) -> String {
        // TODO: Cosine Similarity
        // For now, return a generic ID that the UI can then "renaming"
        "Guest".to_string() 
    }
    
    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(&self).unwrap_or_default()
    }
    
    pub fn from_json(json: &str) -> Self {
        serde_json::from_str(json).unwrap_or_else(|_| Self::new())
    }
}

// Helper to manage storage path
pub struct DiarizationService {
    registry: Arc<Mutex<SpeakerRegistry>>,
    storage_path: PathBuf,
}

impl DiarizationService {
    pub fn new(storage_path: String) -> Self {
         let path = PathBuf::from(storage_path);
         let registry = if path.exists() {
             let content = fs::read_to_string(&path).unwrap_or_default();
             SpeakerRegistry::from_json(&content)
         } else {
             SpeakerRegistry::new()
         };
         
         Self {
             registry: Arc::new(Mutex::new(registry)),
             storage_path: path,
         }
    }
    
    pub fn save(&self) {
        if let Ok(reg) = self.registry.lock() {
            let json = reg.to_json();
            let _ = fs::write(&self.storage_path, json);
        }
    }
    
    pub fn register_speaker(&self, id: String, name: String) {
        if let Ok(mut reg) = self.registry.lock() {
            reg.add_speaker(id, name);
        }
        self.save();
    }
    
    pub fn get_speaker_name(&self, id: String) -> String {
        if let Ok(reg) = self.registry.lock() {
             return reg.get_speaker_name(&id).unwrap_or(id);
        }
        id
    }
}
