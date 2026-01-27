@echo off
setlocal

echo 🏗️ SupraSonic Windows Builder
echo ----------------------------

:: 1. Check for .NET SDK
dotnet --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ .NET SDK is not installed. Please download it from: https://dotnet.microsoft.com/download
    pause
    exit /b %errorlevel%
)

:: 1b. Initialize Visual Studio Environment (Fixes 'link.exe not found')
echo 🔍 Searching for Visual Studio Build Tools...
set "VSDVCMD="
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" set "VSDVCMD=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" set "VSDVCMD=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" set "VSDVCMD=C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"

if defined VSDVCMD (
    echo 🛠️ Initializing Developer Environment...
    call "%VSDVCMD%" >nul
) else (
    echo ⚠️ Visual Studio Build Tools not found in default paths.
    echo ⚠️ If build fails, please run this script from the 'Developer Command Prompt for VS 2022'.
)

:: 2. Build Rust Core (Requires Rust/Cargo installed on Windows)
echo 🦀 Building Rust Core...
cd core

:: Ensure we are using the MSVC toolchain (Standard for Windows/WinUI)
:: The GNU toolchain often fails with 'dlltool.exe not found'
rustup toolchain install stable-x86_64-pc-windows-msvc
cargo +stable-x86_64-pc-windows-msvc build --release --features csharp
if %errorlevel% neq 0 (
    echo ❌ Rust build failed.
    pause
    exit /b %errorlevel%
)

:: Copy DLL to Native folder
echo 📄 Copying Rust DLL...
copy /Y target\release\suprasonic_core.dll ..\SupraSonicWin\Native\libsuprasonic_core.dll
cd ..

:: 3. Publish the WinUI 3 App
echo 📦 Packaging SupraSonic for Windows...
dotnet publish SupraSonicWin\SupraSonicWin.csproj -c Release -r win-x64 --self-contained true -p:PublishReadyToRun=true -o build-win

if %errorlevel% eq 0 (
    echo.
    echo ✅ Build Complete!
    echo 📂 Find your app in the 'build-win' folder.
    echo 🚀 Run 'SupraSonicWin.exe' to test.
) else (
    echo ❌ Windows build failed.
)

pause
