# SupraSonic Troubleshooting Guide

This guide documents known issues, specifically around application launch failures and crashes, and their solutions.

## 🚨 Symptom: App Crushes on Launch or After Onboarding

**Behavior:**
- The app runs fine from Xcode or Terminal but fails to launch via Finder/Dock.
- The app crashes immediately after clicking "Commencer" (Start) in the onboarding window.
- The system log shows `Code Signature Invalid` or `Library not loaded`.

### 1. Swift 6 Concurrency & `@main` Deadlock
**Cause:** Swift 6 introduces strict MainActor isolation. Using `@main` on the `AppDelegate` class can cause a deadlock during high-contention startup sequences, especially when many background tasks (like audio engine initialization) are triggered immediately.
**Solution:**
- **Remove `@main`** from `AppDelegate.swift`.
- Use a manual `main.swift` file:
  ```swift
  import Cocoa
  
  // Early environment setup if needed
  
  autoreleasepool {
      let app = NSApplication.shared
      let delegate = MainActor.assumeIsolated {
          return AppDelegate()
      }
      app.delegate = delegate
      app.run()
  }
  ```

### 2. Post-Onboarding Crash (Zombie Objects)
**Cause:** A race condition occurs when the onboarding window is closed while animations are still active, and the main app is trying to take focus simultaneously. This leads to a "Segmentation Fault: 11" (accessing deallocated memory).
**Solution:**
- **Disable Animations:** Before closing the window, set `animationBehavior = .none`.
- **Async Teardown:** Post the completion notification asynchronously to allow the current event loop iteration to finish.
  ```swift
  self.animationBehavior = .none
  self.orderOut(nil)
  DispatchQueue.main.async {
      NotificationCenter.default.post(name: .setupComplete, object: nil)
  }
  ```

### 3. MLX Metal Shader Library Not Found
**Cause:** The MLX (Machine Learning) library expects to find its Metal shaders (`default.metallib`) in specific locations relative to the binary or inside a specific bundle structure (`mlx-swift_Cmlx.bundle`). When distributed as a standalone app, these valid paths are often missing.
**Solution:**
- **Environment Variable:** Set `METAL_LIBRARY_PATH` and `MLX_METAL_LIBRARY` in `main.swift` **before** any MLX code is loaded.
- **Manual Bundle Creation:** In the build script, create the bundle structure manually:
  ```bash
  mkdir -p "$RESOURCES_DIR/mlx-swift_Cmlx.bundle"
  cp "$MLX_METALLIB" "$RESOURCES_DIR/mlx-swift_Cmlx.bundle/default.metallib"
  ```
- **Redundant Copying:** Copy the `.metallib` file to `Contents/MacOS/` and `Contents/Resources/` under multiple names (`mlx.metallib`, `default.metallib`) to ensure the C++ backend finds it.

### 4. Code Signing Issues
**Cause:** macOS refuses to load dynamic libraries (dylibs) that are not signed, even in ad-hoc builds on Apple Silicon.
**Solution:**
- Ensure **all** binaries in `Contents/MacOS/` (including helper dylibs and `.metallib` files) are signed *before* the main app bundle is signed.
  ```bash
  codesign --force --sign - "build/App.app/Contents/MacOS/libsuprasonic_core.dylib"
  codesign --force --sign - "build/App.app/Contents/MacOS/default.metallib"
  ```

## 🛠️ Verification Checklist

When debugging a new crash:
1.  **Check `stdout`/`stderr`:** If the app crashes instantly, standard Apple logs might miss it. Redirect `stdout` to a file in `main.swift` temporarily.
2.  **Verify Environment:** Check if `METAL_LIBRARY_PATH` is pointing to a directory that actually exists inside the bundle.
3.  **Trace Lifecycle:** Use print statements to verify `applicationDidFinishLaunching` is reached. If not, it's likely a static link initialization issue or a signing problem.
