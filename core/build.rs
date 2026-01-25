fn main() {
    uniffi::generate_scaffolding("./src/suprasonic_core.udl").unwrap_or_else(|e| {
        // If UDL doesn't exist, we might be using proc-macros, which is fine
        println!("cargo:warning=UniFFI UDL generation skipped: {}", e);
    });

    // Windows C# Bindings
    #[cfg(target_os = "macos")] // We can generate on Mac too for the Win project
    {
        csbindgen::Builder::default()
            .input_extern_file("src/state.rs")
            .input_extern_file("src/audio.rs")
            .csharp_namespace("SupraSonicWin.Native")
            .csharp_class_name("RustBindings")
            .csharp_dll_name("libsuprasonic_core")
            .generate_csharp_file("../SupraSonicWin/Native/RustBindings.cs")
            .expect("Failed to generate C# bindings");
    }
}
