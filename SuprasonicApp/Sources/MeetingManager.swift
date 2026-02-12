import Foundation
import AVFoundation
import SupraSonicCore
import FluidAudio
import CoreML

@MainActor
class MeetingManager: ObservableObject {
    static let shared = MeetingManager()
    
    @Published var isMeetingActive = false
    @Published var currentMeeting: Meeting?
    @Published var lastSegment: String = ""
    @Published var isProcessing = false
    
    // Cooldown to prevent final audio chunk from leaking to dictation
    private(set) var meetingStopTime: Date?
    var recentlyStopped: Bool {
        guard let stopTime = meetingStopTime else { return false }
        return Date().timeIntervalSince(stopTime) < 3.0
    }
    
    private var flushTimer: Timer?
    private let flushInterval: TimeInterval = 15.0
    private var startTime: Date?
    private var rustState: AppState?
    
    // Diarization & segment tracking
    private var audioBuffer: [Float] = []
    private let sampleRate = 16000
    private var lastSpeakerId: String?
    private var lastSpeakerName: String = "Participant"
    
    private init() {}
    
    func setRustState(_ state: AppState) {
        self.rustState = state
    }
    
    // MARK: - Meeting Lifecycle
    
    func startMeeting(title: String) {
        guard !isMeetingActive, let state = rustState else { return }
        
        let meeting = Meeting(title: title)
        self.currentMeeting = meeting
        self.isMeetingActive = true
        self.startTime = Date()
        self.audioBuffer = []
        self.lastFlushIndex = 0
        self.lastSpeakerId = nil
        self.lastSpeakerName = "Participant"
        
        do {
            try state.startRecording()
            debugLog("🎙️ Meeting: Started recording — '\(title)'")
            
            flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.flushAudio()
                }
            }
        } catch {
            debugLog("❌ Meeting: Failed to start recording: \(error)")
            isMeetingActive = false
        }
    }
    
    func stopMeeting() {
        guard isMeetingActive, let state = rustState else { return }
        
        flushTimer?.invalidate()
        flushTimer = nil
        
        // Final flush to get last audio
        try? state.flush()
        
        do {
            try state.stopRecording()
            debugLog("⏹️ Meeting: Stopped recording")
        } catch {
            debugLog("❌ Meeting: Failed to stop recording: \(error)")
        }
        
        // Transcribe last accumulated audio before stopping
        // Use a delay to let the final flush audio arrive
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            
            // Transcribe any remaining audio
            let currentCount = self.audioBuffer.count
            if currentCount > self.lastFlushIndex + 16000 {
                let newAudio = Array(self.audioBuffer[self.lastFlushIndex..<currentCount])
                self.lastFlushIndex = currentCount
                
                let diarAudio = Array(self.audioBuffer.suffix(16000 * 5))
                debugLog("🌊 Meeting: Final transcription of \(newAudio.count) samples...")
                Task {
                    do {
                        let text = try await TranscriptionManager.shared.transcribe(audioSamples: newAudio)
                        if !text.isEmpty {
                            debugLog("📝 Meeting Final Transcription: \(text)")
                            let cachedId = await MainActor.run { self.lastSpeakerId }
                            let cachedName = await MainActor.run { self.lastSpeakerName }
                            let speakerInfo = await self.identifySpeaker(audio: diarAudio, lastId: cachedId, lastName: cachedName)
                            await MainActor.run {
                                self.lastSpeakerId = speakerInfo.id
                                self.lastSpeakerName = speakerInfo.name
                                self.addFinalSegment(text: text, speakerId: speakerInfo.id, speakerName: speakerInfo.name)
                            }
                        }
                    } catch {
                        debugLog("❌ Meeting: Final transcription failed: \(error)")
                    }
                    
                    // Now do post-processing
                    await self.postMeetingProcessing()
                }
            } else {
                // No remaining audio, just do post-processing
                Task {
                    await self.postMeetingProcessing()
                }
            }
        }
        
        // Mark as processing
        if var meeting = currentMeeting {
            meeting.status = .processing
            meeting.duration = Date().timeIntervalSince(startTime ?? Date())
            self.currentMeeting = meeting
            MeetingHistoryManager.shared.saveMeeting(meeting)
        }
        
        isMeetingActive = false
        meetingStopTime = Date()
        isProcessing = true
    }
    
    // MARK: - Audio Recording (disabled - only keep transcription + AI summary)
    
    // Audio file storage removed to save disk space
    // Only text transcription and AI summary are kept
    
    // MARK: - Audio Handling
    
    func handleAudioBuffer(_ audio: [Float]) {
        guard isMeetingActive else { return }
        
        // Append to in-memory buffer for Diarization context only
        // No disk storage - only transcription text is kept
        audioBuffer.append(contentsOf: audio)
    }
    
    private var lastFlushIndex = 0
    
    private func flushAudio() {
        guard isMeetingActive, let state = rustState else { return }
        
        debugLog("🌊 Meeting: Triggering Rust flush (buffer: \(audioBuffer.count) samples, lastFlush: \(lastFlushIndex))...")
        
        // Trigger Rust to send buffered audio via onAudioData callback
        try? state.flush()
        
        // Schedule transcription after a short delay to allow audio to arrive via onAudioData
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.transcribeAccumulatedAudio()
        }
    }
    
    private func transcribeAccumulatedAudio() {
        guard isMeetingActive else { return }
        
        let currentCount = audioBuffer.count
        guard currentCount > lastFlushIndex + 16000 else {
            debugLog("🌊 Meeting: Not enough new audio to transcribe (\(currentCount - lastFlushIndex) samples)")
            return
        }
        
        // Include 1s overlap from previous chunk to avoid losing words at boundaries
        let overlapSamples = 16000
        let startIdx = max(0, lastFlushIndex - overlapSamples)
        let newAudio = Array(audioBuffer[startIdx..<currentCount])
        lastFlushIndex = currentCount
        
        // Take 5s context for diarization
        let contextSamples = 16000 * 5
        let diarAudio = Array(audioBuffer.suffix(contextSamples))
        
        debugLog("🌊 Meeting: Transcribing \(newAudio.count) samples (\(Double(newAudio.count) / 16000.0)s) with 1s overlap...")
        
        Task {
            do {
                // 1. Transcribe
                let text = try await TranscriptionManager.shared.transcribe(audioSamples: newAudio)
                guard !text.isEmpty else {
                    debugLog("📝 Meeting: Empty transcription result")
                    return
                }
                debugLog("📝 Meeting Transcription: \(text)")
                
                // 2. Identify speaker via OfflineDiarizerManager (provides embeddings)
                let cachedId = await MainActor.run { self.lastSpeakerId }
                let cachedName = await MainActor.run { self.lastSpeakerName }
                let speakerInfo = await self.identifySpeaker(audio: diarAudio, lastId: cachedId, lastName: cachedName)
                
                // 3. Add segment on main actor
                await MainActor.run {
                    self.lastSpeakerId = speakerInfo.id
                    self.lastSpeakerName = speakerInfo.name
                    self.addFinalSegment(text: text, speakerId: speakerInfo.id, speakerName: speakerInfo.name)
                }
            } catch {
                debugLog("❌ Meeting: Transcription failed: \(error)")
            }
        }
    }
    
    // MARK: - Speaker Identification (async - uses OfflineDiarizerManager)
    
    private func identifySpeaker(audio: [Float], lastId: String?, lastName: String) async -> (id: String?, name: String) {
        let profiles = await MainActor.run { SpeakerEnrollmentManager.shared.profiles }
        guard !profiles.isEmpty, !audio.isEmpty else {
            return (lastId, lastName)
        }
        
        // Normalize audio same way as enrollment (scale to 0.9 max amplitude)
        let maxAmp = audio.reduce(0) { max($0, abs($1)) }
        let scale = maxAmp > 0 ? min(0.9 / maxAmp, 100.0) : 1.0
        let normalizedAudio = audio.map { $0 * Float(scale) }
        
        do {
            let offlineDiarizer = OfflineDiarizerManager()
            try await offlineDiarizer.prepareModels(directory: TranscriptionManager.diarizerModelsDirectory())
            let result = try await offlineDiarizer.process(audio: normalizedAudio)
            
            guard let speakerDB = result.speakerDatabase, !speakerDB.isEmpty else {
                debugLog("🔍 Meeting: No speakers detected — keeping '\(lastName)'")
                return (lastId, lastName)
            }
            
            // Find the dominant speaker
            var durationPerSpeaker: [String: Float] = [:]
            for seg in result.segments {
                let dur = seg.endTimeSeconds - seg.startTimeSeconds
                durationPerSpeaker[seg.speakerId, default: 0] += dur
            }
            
            guard let (bestId, _) = durationPerSpeaker.max(by: { $0.value < $1.value }),
                  let detectedEmbedding = speakerDB[bestId] else {
                return (lastId, lastName)
            }
            
            // Match embedding against enrolled profiles via cosine similarity
            var bestMatch: (profile: SpeakerProfile, score: Float)?
            for profile in profiles {
                let score = Self.cosineSimilarity(detectedEmbedding, profile.embedding)
                debugLog("🔍 Meeting: Cosine('\(profile.name)') = \(String(format: "%.4f", score))")
                if score > (bestMatch?.score ?? 0.05) {
                    bestMatch = (profile, score)
                }
            }
            
            if let match = bestMatch {
                debugLog("🎯 Meeting: Speaker → '\(match.profile.name)' (score: \(String(format: "%.3f", match.score)))")
                return (match.profile.id, match.profile.name)
            } else {
                // Recognition failed — reuse last known speaker instead of showing "S1"
                if lastId != nil {
                    debugLog("🔍 Meeting: Low confidence — keeping '\(lastName)'")
                    return (lastId, lastName)
                }
                return (bestId, formatSpeakerName(bestId))
            }
        } catch {
            debugLog("⚠️ Meeting: Diarization failed — keeping '\(lastName)'")
            return (lastId, lastName)
        }
    }
    
    // MARK: - Segment Processing
    
    private func addFinalSegment(text: String, speakerId: String?, speakerName: String) {
        guard var meeting = currentMeeting else { return }
        
        let timestamp = Date().timeIntervalSince(startTime ?? Date())
        
        // Merge with previous segment if same speaker
        if let lastIdx = meeting.segments.indices.last,
           meeting.segments[lastIdx].speakerName == speakerName {
            meeting.segments[lastIdx].text += " " + text
            debugLog("📝 Meeting: Merged with previous segment for '\(speakerName)'")
        } else {
            let segment = MeetingSegment(timestamp: timestamp, text: text, speakerId: speakerId, speakerName: speakerName, isFinal: true)
            meeting.segments.append(segment)
        }
        
        meeting.duration = timestamp
        self.currentMeeting = meeting
        self.lastSegment = ""
        
        // Track participant
        if let pid = speakerId, !meeting.participantIds.contains(pid) {
            meeting.participantIds.append(pid)
            self.currentMeeting = meeting
        }
        
        MeetingHistoryManager.shared.saveMeeting(meeting)
        debugLog("📝 Meeting Segment: [\(Int(timestamp))s] [\(speakerName)] \(text)")
        
        // Keep buffer reasonable (last 60s)
        if audioBuffer.count > 16000 * 60 {
            audioBuffer.removeFirst(audioBuffer.count - 16000 * 60)
            lastFlushIndex = max(0, lastFlushIndex - (audioBuffer.count - 16000 * 60))
        }
        
        // Broadcast for UI
        NotificationCenter.default.post(
            name: Constants.NotificationNames.meetingTranscriptUpdated,
            object: nil,
            userInfo: ["text": text, "speaker": speakerName, "isFinal": true]
        )
    }
    
    func handleSegmentProduced(_ text: String, isFinal: Bool) {
        guard isMeetingActive, currentMeeting != nil, !text.isEmpty else { return }
        
        if !isFinal {
            self.lastSegment = text
            NotificationCenter.default.post(
                name: Constants.NotificationNames.meetingTranscriptUpdated,
                object: nil,
                userInfo: ["text": text, "speaker": "...", "isFinal": false]
            )
        }
    }
    
    // MARK: - Post-Meeting Processing
    
    private func postMeetingProcessing() async {
        guard var meeting = currentMeeting else {
            isProcessing = false
            return
        }
        
        debugLog("🤖 Meeting: Starting post-meeting processing...")
        
        // AI Summarization
        do {
            let result = try await LLMManager.shared.processMeeting(meeting: meeting)
            meeting.summary = result.summary
            meeting.actionItems = result.actionItems
            debugLog("✅ Meeting: AI summarization complete")
        } catch {
            debugLog("⚠️ Meeting: AI summarization failed: \(error)")
        }
        
        // Mark as completed
        meeting.status = .completed
        self.currentMeeting = meeting
        MeetingHistoryManager.shared.saveMeeting(meeting)
        
        isProcessing = false
        debugLog("✅ Meeting: Post-processing finished")
        
        // Notify UI to refresh (meeting detail window may already be open)
        NotificationCenter.default.post(
            name: Constants.NotificationNames.meetingTranscriptUpdated,
            object: nil,
            userInfo: ["meetingCompleted": true, "meetingId": meeting.id.uuidString]
        )
    }
    
    // MARK: - AI Summarization (Manual)
    
    func summarizeMeeting(meetingId: UUID? = nil) async {
        guard let id = meetingId ?? currentMeeting?.id else { return }
        
        var targetMeeting: Meeting?
        if let current = currentMeeting, current.id == id {
            targetMeeting = current
        } else {
            targetMeeting = MeetingHistoryManager.shared.loadAllMeetings().first(where: { $0.id == id })
        }
        
        guard var meeting = targetMeeting else { return }
        
        self.isProcessing = true
        debugLog("🤖 Meeting: Starting AI summarization for \(meeting.title)")
        
        do {
            let result = try await LLMManager.shared.processMeeting(meeting: meeting)
            meeting.summary = result.summary
            meeting.actionItems = result.actionItems
            
            MeetingHistoryManager.shared.saveMeeting(meeting)
            
            if self.currentMeeting?.id == meeting.id {
                self.currentMeeting = meeting
            }
            
            debugLog("✅ Meeting: AI summarization complete.")
        } catch {
            debugLog("❌ Meeting: AI summarization failed: \(error)")
        }
        
        self.isProcessing = false
    }
    
    // MARK: - Speaker Helpers
    
    func renameSpeaker(id: String, newName: String) {
        if var meeting = currentMeeting {
            for i in 0..<meeting.segments.count {
                if meeting.segments[i].speakerId == id {
                    meeting.segments[i].speakerName = newName
                }
            }
            self.currentMeeting = meeting
            MeetingHistoryManager.shared.saveMeeting(meeting)
        }
    }
    
    private nonisolated func formatSpeakerName(_ rawId: String) -> String {
        // If it looks like a UUID, show generic name
        if rawId.count > 20 && rawId.contains("-") {
            return L10n.isFrench ? "Participant inconnu" : "Unknown Participant"
        }
        return rawId.replacingOccurrences(of: "SPEAKER_", with: "Speaker ")
    }
    
    static nonisolated func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
    
    // MARK: - Import Mode
    
    func importMeeting(from url: URL) async {
        guard !isMeetingActive, !isProcessing else {
            debugLog("⚠️ Meeting: Cannot import while active or processing")
            return
        }
        
        self.isProcessing = true
        defer { self.isProcessing = false }
        
        let filename = url.deletingPathExtension().lastPathComponent
        debugLog("📥 Meeting: Importing \(filename)...")
        
        do {
            let (samples, convertedURL) = try await AudioConverter.convertToStandardFormat(inputURL: url)
            
            var meeting = Meeting(title: "Import: \(filename)")
            
            // Audio file storage removed - only transcription text is kept
            // Clean up converted audio file
            try? FileManager.default.removeItem(at: convertedURL)
            
            var segments: [MeetingSegment] = []
            let chunkSamples = 16000 * 30
            let totalSamples = samples.count
            var offset = 0
            
            let importDiarizer = DiarizerManager()
            if let models = TranscriptionManager.shared.diarizerModels {
                importDiarizer.initialize(models: models)
                SpeakerEnrollmentManager.shared.loadKnownSpeakers(into: importDiarizer)
            }
            
            self.currentMeeting = meeting
            
            while offset < totalSamples {
                let end = min(offset + chunkSamples, totalSamples)
                let chunk = Array(samples[offset..<end])
                let timestamp = Double(offset) / 16000.0
                
                if chunk.count > 16000 {
                    let text = try await TranscriptionManager.shared.transcribe(audioSamples: chunk)
                    
                    if !text.isEmpty {
                        var speakerName = "Participant"
                        var speakerId: String? = nil
                        
                        if TranscriptionManager.shared.diarizerModels != nil {
                            do {
                                let results = try importDiarizer.performCompleteDiarization(chunk)
                                var durationPerSpeaker: [String: Float] = [:]
                                for s in results.segments {
                                    durationPerSpeaker[s.speakerId, default: 0] += (s.endTimeSeconds - s.startTimeSeconds)
                                }
                                if let (bestId, _) = durationPerSpeaker.max(by: { $0.value < $1.value }) {
                                    speakerId = bestId
                                    if let profile = SpeakerEnrollmentManager.shared.findProfile(for: bestId) {
                                        speakerName = profile.name
                                    } else {
                                        speakerName = formatSpeakerName(bestId)
                                    }
                                }
                            } catch {
                                debugLog("⚠️ Import: Diarization failed: \(error)")
                            }
                        }
                        
                        let segment = MeetingSegment(timestamp: timestamp, text: text, speakerId: speakerId, speakerName: speakerName, isFinal: true)
                        segments.append(segment)
                        
                        meeting.segments = segments
                        meeting.duration = timestamp
                        self.currentMeeting = meeting
                    }
                }
                
                offset += chunkSamples
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            
            meeting.segments = segments
            meeting.duration = Double(totalSamples) / 16000.0
            meeting.status = .completed
            
            MeetingHistoryManager.shared.saveMeeting(meeting)
            self.currentMeeting = meeting
            
            debugLog("✅ Import: Complete")
            
        } catch {
            debugLog("❌ Import: Failed: \(error)")
        }
    }
}
