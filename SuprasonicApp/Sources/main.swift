import Cocoa

// 1. SETUP ENVIRONMENT
// (No special setup required for APIs)

// 2. START APPLICATION
autoreleasepool {
    let app = NSApplication.shared
    
    // Create AppDelegate on the MainActor synchronously
    let delegate = MainActor.assumeIsolated {
        return AppDelegate()
    }
    
    app.delegate = delegate
    app.run()
}
