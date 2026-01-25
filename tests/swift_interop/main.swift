import Foundation

// We need to suppress the need for a module map for this simple test
// by just including the swift file in compilation.
// However, suprasonic_core.swift relies on the C header.

print("Attempting to create AppState...")
do {
    let state = AppState()
    print("AppState created successfully!")
    
    print("Starting recording...")
    try state.startRecording()
    print("Recording started!")
    
    print("Sleeping for 1 second...")
    Thread.sleep(forTimeInterval: 1.0)
    
    print("Stopping recording...")
    try state.stopRecording()
    print("Recording stopped!")
    
    print("Test Passed: Rust interop is working.")
} catch {
    print("Error: \(error)")
    exit(1)
}
