import Cocoa

class OverlayWindow: NSWindow {
    private let l = L10n.current
    private var contentBox: NSBox!
    private var waveformView: WaveformView!
    private var label: NSTextField!
    
    init() {
        // Dynamic Island style: pill at top center of screen
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 280
        let windowHeight: CGFloat = 50
        let windowX = (screenFrame.width - windowWidth) / 2
        let windowY = screenFrame.height - windowHeight - 50 // 50px from top
        
        let windowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        
        super.init(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Window properties
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.ignoresMouseEvents = true
        self.hasShadow = true
        
        setupUI()
    }
    
    private func setupUI() {
        // Main container (pill shape)
        contentBox = NSBox(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        contentBox.boxType = .custom
        contentBox.fillColor = NSColor.black.withAlphaComponent(0.9)
        contentBox.borderColor = .clear
        contentBox.borderWidth = 0
        contentBox.cornerRadius = frame.height / 2
        contentBox.contentViewMargins = .zero
        
        // Label
        label = NSTextField(labelWithString: l.recording)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.frame = NSRect(x: 20, y: (frame.height - 20) / 2, width: 100, height: 20)
        
        // Waveform view
        waveformView = WaveformView(frame: NSRect(x: 120, y: 10, width: frame.width - 140, height: frame.height - 20))
        
        contentBox.addSubview(label)
        contentBox.addSubview(waveformView)
        contentView?.addSubview(contentBox)
    }
    
    func updateLevel(_ level: Float) {
        waveformView.addLevel(level)
    }
    
    func show() {
        waveformView.reset()
        orderFront(nil)
        
        // Animate in
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 1
        }
    }
    
    func hide() {
        waveformView.stop()
        // Animate out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

class WaveformView: NSView {
    private var levels: [Float] = Array(repeating: 0.1, count: 30)
    private var targetLevels: [Float] = Array(repeating: 0.1, count: 30)
    private var animationTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.decayLevels()
            self?.needsDisplay = true
        }
    }
    
    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addLevel(_ level: Float) {
        // Boost level sensitivity - snappy and responsive
        // Clamp top level to prevent overflow (1.0 is full height)
        let amplified = min(level * 22, 1.2)
        
        for i in 0..<targetLevels.count {
            // Central bars are more sensitive
            let centerIdx = Float(targetLevels.count) / 2.0
            let distFromCenter = abs(Float(i) - centerIdx) / centerIdx
            
            // Per-bar organic variance
            let multiplier = 1.0 - (distFromCenter * 0.6)
            let variance = 0.85 + (Float.random(in: 0.0...0.3))
            
            // Final target value clamped to 1.2 max
            let newTarget = min(amplified * multiplier * variance, 1.2)
            targetLevels[i] = max(targetLevels[i], newTarget)
        }
    }
    
    func reset() {
        levels = Array(repeating: 0.1, count: 30)
        targetLevels = Array(repeating: 0.1, count: 30)
        startAnimating()
        needsDisplay = true
    }
    
    func stop() {
        stopAnimating()
    }
    
    private func decayLevels() {
        for i in 0..<levels.count {
            let diff = targetLevels[i] - levels[i]
            
            // Organic rise/fall speeds
            let riseSpeed = 0.35 + (Float(i % 3) * 0.05)
            let fallSpeed = 0.15 + (Float(i % 5) * 0.02)
            
            if diff > 0 {
                levels[i] += diff * riseSpeed
            } else {
                levels[i] += diff * fallSpeed
            }
            
            // Decaying target towards idle
            let idle: Float = 0.05
            let decayRate = 0.85 + (Float(i % 4) * 0.02)
            
            targetLevels[i] = targetLevels[i] * decayRate
            if targetLevels[i] < idle {
                targetLevels[i] = idle
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let totalWidth = bounds.width
        let barSpacing: CGFloat = 2
        let barCount = levels.count
        let barWidth: CGFloat = (totalWidth - (CGFloat(barCount - 1) * barSpacing)) / CGFloat(barCount)
        
        let maxHeight = bounds.height - 4
        let midY = bounds.height / 2
        
        context.setLineCap(.round)
        context.setLineWidth(barWidth)
        
        for (i, level) in levels.enumerated() {
            let x = CGFloat(i) * (barWidth + barSpacing) + barWidth / 2
            let height = max(4, CGFloat(level) * maxHeight)
            
            // Gradient effect: brighter in the middle, dimmer at the ends
            let centerFactor = 1.0 - abs(CGFloat(i) - CGFloat(barCount)/2.0) / (CGFloat(barCount)/2.0)
            let alpha = 0.4 + (0.6 * centerFactor)
            
            // Vibrant cyan/green color
            context.setStrokeColor(NSColor(red: 0, green: 0.9, blue: 1.0, alpha: alpha).cgColor)
            
            context.move(to: CGPoint(x: x, y: midY - height / 2))
            context.addLine(to: CGPoint(x: x, y: midY + height / 2))
            context.strokePath()
        }
    }
}
