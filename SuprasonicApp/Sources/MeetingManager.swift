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
    
    private var flushTimer: Timer?
    private let flushInterval: TimeInterval = 15.0
    private var startTime: Date?
    private var rustState: AppState?
    
    // FluidAudio Diarization Pipeline
    private var diarizerManager: DiarizerManager?
    private var audioBuffer: [Float] = []
    private let sampleRate = 16000
    
    private init() {}
    
    func setRustState(_ state: AppState) {
        self.rustState = state
    }
    
    // MARK: - Meeting Lifecycle
    
    func startMeeting(title: String) {
        guard !isMeetingActive, let state = rustState else { return }
        
        // Initialize Diarizer with known speakers
        if let models = TranscriptionManager.shared.diarizerModels {
            print("👯‍♀️ Meeting: Initializing FluidAudio Diarizer...")
            let manager = DiarizerManager()
            manager.initialize(models: models)
            
            // Load enrolled speakers for known-speaker recognition
            SpeakerEnrollmentManager.shared.loadKnownSpeakers(into: manager)
            
            self.diarizerManager = manager
        } else {
            print("⚠️ Meeting: Diarizer models not loaded. Diarization disabled.")
        }
        
        let meeting = Meeting(title: title)
        self.currentMeeting = meeting
        self.isMeetingActive = true
        self.startTime = Date()
        self.audioBuffer = []
        
        setupAudioRecording(meetingId: meeting.id)
        
        do {
            try state.startRecording()
            print("🎙️ Meeting: Started recording — '\(title)'")
            
            flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.flushAudio()
                }
            }
        } catch {
            print("❌ Meeting: Failed to start recording: \(error)")
            isMeetingActive = false
        }
    }
    
    func stopMeeting() {
        guard isMeetingActive, let state = rustState else { return }
        
        flushTimer?.invalidate()
        flushTimer = nil
        
        do {
            try state.stopRecording()
            print("⏹️ Meeting: Stopped recording")
        } catch {
            print("❌ Meeting: Failed to stop recording: \(error)")
        }
        
        // Close Audio File
        audioFile = nil
        
        // Mark as processing
        if var meeting = currentMeeting {
            meeting.status = .processing
            meeting.duration = Date().timeIntervalSince(startTime ?? Date())
            self.currentMeeting = meeting
            MeetingHistoryManager.shared.saveMeeting(meeting)
        }
        
        isMeetingActive = false
        isProcessing = true
        
        // Post-meeting processing: AI summary
        Task {
            await postMeetingProcessing()
        }
    }
    
    // MARK: - Audio Recording
    
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    
    private func setupAudioRecording(meetingId: UUID) {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let meetingsDir = documents.appendingPathComponent("SupraSonic/Meetings/\(meetingId.uuidString)")
        
        do {
            try fileManager.createDirectory(at: meetingsDir, withIntermediateDirectories: true)
            let audioURL = meetingsDir.appendingPathComponent("recording.wav")
            self.recordingURL = audioURL
            
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
            self.audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            print("💾 Meeting: Recording audio to \(audioURL.path)")
        } catch {
            print("❌ Meeting: Failed to setup audio recording: \(error)")
        }
    }
    
    // MARK: - Audio Handling
    
    func handleAudioBuffer(_ audio: [Float]) {
        guard isMeetingActive else { return }
        
        // 1. Append to in-memory buffer for Diarization context
        audioBuffer.append(contentsOf: audio)
        
        // 2. Write to disk
        if let file = audioFile, let format = file.processingFormat as AVAudioFormat? {
            let frameCount = AVAudioFrameCount(audio.count)
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
                buffer.frameLength = frameCount
                if let channelData = buffer.floatChannelData {
                    let ptr = channelData[0]
                    audio.withUnsafeBufferPointer { srcPtr in
                        if let srcBase = srcPtr.baseAddress {
                            ptr.update(from: srcBase, count: audio.count)
                        }
                    }
                    try? file.write(from: buffer)
                }
            }
        }
    }
    
    private func flushAudio() {
        guard isMeetingActive, let state = rustState else { return }
        print("🌊 Meeting: Flushing audio for segment...")
        try? state.flush()
    }
    
    // MARK: - Segment Processing
    
    func handleSegmentProduced(_ text: String, isFinal: Bool) {
        guard isMeetingActive, var meeting = currentMeeting, !text.isEmpty else { return }
        
        let timestamp = Date().timeIntervalSince(startTime ?? Date())
        var speakerName: String = "Participant"
        
        if isFinal {
            var speakerId: String? = nil
            
            // Diarization: identify speaker using FluidAudio
            if let diarizer = diarizerManager, !audioBuffer.isEmpty {
                let contextSamples = 16000 * 2
                let suffix = audioBuffer.suffix(contextSamples)
                let audioSlice = Array(suffix)
                
                do {
                    let results = try diarizer.performCompleteDiarization(audioSlice)
                    
                    var durationPerSpeaker: [String: Float] = [:]
                    for segment in results.segments {
                        let dur = segment.endTimeSeconds - segment.startTimeSeconds
                        durationPerSpeaker[segment.speakerId, default: 0] += dur
                    }
                    
                    if let (bestId, _) = durationPerSpeaker.max(by: { $0.value < $1.value }) {
                        speakerId = bestId
                        
                        // Look up enrolled speaker profile
                        if let profile = SpeakerEnrollmentManager.shared.findProfile(for: bestId) {
                            speakerName = profile.name
                            
                            // Track participant
                            if !meeting.participantIds.contains(profile.id) {
                                meeting.participantIds.append(profile.id)
                            }
                        } else {
                            speakerName = formatSpeakerName(bestId)
                        }
                        
                        print("🎯 Meeting: Identified '\(bestId)' → '\(speakerName)'")
                    }
                } catch {
                    print("⚠️ Meeting: Diarization failed for segment: \(error)")
                }
            }
            
            let segment = MeetingSegment(timestamp: timestamp, text: text, speakerId: speakerId, speakerName: speakerName, isFinal: true)
            meeting.segments.append(segment)
            meeting.duration = timestamp
            self.currentMeeting = meeting
            self.lastSegment = ""
            
            MeetingHistoryManager.shared.saveMeeting(meeting)
            print("📝 Meeting Segment: [\(Int(timestamp))s] [\(speakerName)] \(text)")
            
            // Keep buffer reasonable (last 60s)
            if audioBuffer.count > 16000 * 60 {
                audioBuffer.removeFirst(audioBuffer.count - 16000 * 60)
            }
            
        } else {
            self.lastSegment = text
            print("📝 Meeting Partial: \(text)")
        }
        
        // Broadcast for UI (Overlay)
        let userInfo: [String: Any] = [
            "text": text,
            "speaker": speakerName,
            "isFinal": isFinal
        ]
        NotificationCenter.default.post(name: Constants.NotificationNames.meetingTranscriptUpdated, object: nil, userInfo: userInfo)
    }
    
    // MARK: - Post-Meeting Processing
    
    private func postMeetingProcessing() async {
        guard var meeting = currentMeeting else {
            isProcessing = false
            return
        }
        
        print("🤖 Meeting: Starting post-meeting processing...")
        
        // AI Summarization
        do {
            let result = try await LLMManager.shared.processMeeting(meeting: meeting)
            meeting.summary = result.summary
            meeting.actionItems = result.actionItems
            print("✅ Meeting: AI summarization complete")
        } catch {
            print("⚠️ Meeting: AI summarization failed: \(error)")
        }
        
        // Mark as completed
        meeting.status = .completed
        self.currentMeeting = meeting
        MeetingHistoryManager.shared.saveMeeting(meeting)
        
        isProcessing = false
        print("✅ Meeting: Post-processing finished")
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
        print("🤖 Meeting: Starting AI summarization for \(meeting.title)")
        
        do {
            let result = try await LLMManager.shared.processMeeting(meeting: meeting)
            meeting.summary = result.summary
            meeting.actionItems = result.actionItems
            
            MeetingHistoryManager.shared.saveMeeting(meeting)
            
            if self.currentMeeting?.id == meeting.id {
                self.currentMeeting = meeting
            }
            
            print("✅ Meeting: AI summarization complete.")
        } catch {
            print("❌ Meeting: AI summarization failed: \(error)")
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
    
    private func formatSpeakerName(_ rawId: String) -> String {
        return rawId.replacingOccurrences(of: "SPEAKER_", with: "Speaker ")
    }
    
    // MARK: - Import Mode
    
    func importMeeting(from url: URL) async {
        guard !isMeetingActive, !isProcessing else {
            print("⚠️ Meeting: Cannot import while active or processing")
            return
        }
        
        self.isProcessing = true
        defer { self.isProcessing = false }
        
        let filename = url.deletingPathExtension().lastPathComponent
        print("📥 Meeting: Importing \(filename)...")
        
        do {
            let (samples, convertedURL) = try await AudioConverter.convertToStandardFormat(inputURL: url)
            
            var meeting = Meeting(title: "Import: \(filename)")
            let meetingId = meeting.id
            
            setupAudioRecording(meetingId: meetingId)
            if let destURL = self.recordingURL {
                self.audioFile = nil
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: convertedURL, to: destURL)
                print("💾 Meeting: Imported audio saved to \(destURL.path)")
            }
            
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
                                print("⚠️ Import: Diarization failed: \(error)")
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
            
            print("✅ Import: Complete")
            
        } catch {
            print("❌ Import: Failed: \(error)")
        }
    }
}
