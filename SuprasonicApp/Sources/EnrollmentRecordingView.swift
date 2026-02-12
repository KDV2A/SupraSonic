import Cocoa
import AVFoundation

class EnrollmentRecordingView: NSView {
    
    // UI Components
    private let container = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let timerLabel = NSTextField(labelWithString: "00:00")
    private let waveformView = EnrollmentWaveformView()
    private let stopButton = NSButton()
    private let cancelButton = NSButton()
    
    // State
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var recordingTimer: Timer?
    private var startTime: Date?
    private var updateTimer: Timer?
    
    // Callbacks
    var onFinish: (([Float]) -> Void)?
    var onCancel: (() -> Void)?
    
    // Localization
    private let isFrench = L10n.isFrench
    
    init() {
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Semi-transparent background
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        
        // Blur effect
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .withinWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffect)
        
        // Container
        container.orientation = .vertical
        container.spacing = 20
        container.alignment = .centerX
        container.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(container)
        
        // Status
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.stringValue = isFrench ? "Enregistrement en cours..." : "Recording..."
        
        // Waveform
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.heightAnchor.constraint(equalToConstant: 60).isActive = true
        waveformView.widthAnchor.constraint(equalToConstant: 300).isActive = true
        
        // Timer
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        timerLabel.textColor = .secondaryLabelColor
        
        // "Pastille" / Waveform Animation embedded in a circle?
        // User asked for "pastille enregistrement avec la wave".
        // Let's make the stop button a big red circle (pastille) or square inside circle.
        
        // Stop Button
        stopButton.bezelStyle = .regularSquare
        stopButton.isBordered = false
        stopButton.wantsLayer = true
        stopButton.layer?.backgroundColor = NSColor.systemRed.cgColor
        stopButton.layer?.cornerRadius = 30
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
        stopButton.contentTintColor = .white
        stopButton.target = self
        stopButton.action = #selector(stopRecording)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        stopButton.heightAnchor.constraint(equalToConstant: 60).isActive = true
        
        // Cancel Button
        cancelButton.title = isFrench ? "Annuler" : "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelRecording)
        
        // Assemble
        container.addArrangedSubview(statusLabel)
        container.addArrangedSubview(timerLabel)
        container.addArrangedSubview(waveformView)
        container.addArrangedSubview(stopButton)
        container.addArrangedSubview(cancelButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            visualEffect.centerXAnchor.constraint(equalTo: centerXAnchor),
            visualEffect.centerYAnchor.constraint(equalTo: centerYAnchor),
            visualEffect.widthAnchor.constraint(equalToConstant: 360),
            visualEffect.heightAnchor.constraint(equalToConstant: 300),
            
            container.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor)
        ])
    }
    
    // MARK: - Recording Logic
    
    func startRecording() {
        audioBuffer = []
        startTime = Date()
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            debugLog("❌ EnrollmentView: Failed to create audio converter")
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // 1. Convert for logic
            let ratio = 16000.0 / inputFormat.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return }
            
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if status == .haveData, let channelData = outputBuffer.floatChannelData {
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
                DispatchQueue.main.async {
                    self.audioBuffer.append(contentsOf: samples)
                }
            }
            
            // 2. Visualization (use raw input buffer for smoothness)
            if let floatData = buffer.floatChannelData {
                let frameLength = Int(buffer.frameLength)
                let samples = UnsafeBufferPointer(start: floatData[0], count: frameLength)
                // Downsample for UI
                var rms: Float = 0
                for i in stride(from: 0, to: frameLength, by: 10) {
                    rms += abs(samples[i])
                }
                rms /= Float(frameLength / 10)
                
                DispatchQueue.main.async {
                    self.waveformView.addSample(value: CGFloat(rms))
                }
            }
        }
        
        do {
            try audioEngine.start()
            startTimer()
        } catch {
            debugLog("❌ EnrollmentView: Failed to start engine: \(error)")
        }
    }
    
    @objc private func stopRecording() {
        stopEngine()
        onFinish?(audioBuffer)
    }
    
    @objc private func cancelRecording() {
        stopEngine()
        onCancel?()
    }
    
    private func stopEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        timer?.invalidate()
        updateTimer?.invalidate()
    }
    
    private var timer: Timer?
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTimerLabel()
        }
    }
    
    private func updateTimerLabel() {
        guard let startTime = startTime else { return }
        let duration = Date().timeIntervalSince(startTime)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        timerLabel.stringValue = String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform View

class EnrollmentWaveformView: NSView {
    private var samples: [CGFloat] = Array(repeating: 0.1, count: 30) // Bars
    
    override var isFlipped: Bool { true }
    
    func addSample(value: CGFloat) {
        // Shift left
        samples.removeFirst()
        // Boost value for visibility
        let boosted = min(value * 5.0, 1.0)
        samples.append(max(0.1, boosted))
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let context = NSGraphicsContext.current?.cgContext
        let width = bounds.width
        let height = bounds.height
        let barWidth = width / CGFloat(samples.count)
        let spacing: CGFloat = 2.0
        
        context?.setFillColor(NSColor.systemRed.cgColor) // Request: "Pastille enregistrement avec la wave" -> Red Wave?
        
        for (i, sample) in samples.enumerated() {
            let barHeight = height * sample
            let x = CGFloat(i) * barWidth
            let y = (height - barHeight) / 2
            
            let rect = CGRect(x: x + spacing/2, y: y, width: barWidth - spacing, height: barHeight)
            let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
            
            context?.addPath(path)
            context?.fillPath()
        }
    }
}
