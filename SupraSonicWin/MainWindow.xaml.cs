using Microsoft.UI.Xaml;
using System;
using System.Diagnostics;
using SupraSonicWin.Native;
using SupraSonicWin.Helpers;

namespace SupraSonicWin
{
    public sealed partial class MainWindow : Window
    {
        private RustCore m_rust = new RustCore();
        private TranscriptionManager m_transcription = new TranscriptionManager();
        private HotkeyManager m_hotkey = new HotkeyManager();
        private OverlayWindow m_overlay = new OverlayWindow();

        public MainWindow()
        {
            this.InitializeComponent();
            
            this.Closed += (s, e) => m_hotkey.Cleanup();

            InitializeApp();
        }

        private async void InitializeApp()
        {
            try
            {
                // Init Rust
                m_rust.Initialize();
                m_rust.OnAudioData += OnAudioCaptured;
                m_rust.OnLevelChanged += OnLevelChanged;

                // Init Transcription
                await m_transcription.InitializeAsync();

                // Setup Hotkey
                m_hotkey.Setup(this);
                // In a full implementation, we'd hook events here
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ Setup error: {ex.Message}");
            }
        }

        private void OnLevelChanged(float level)
        {
            DispatcherQueue.TryEnqueue(() => {
                m_overlay.UpdateLevel(level);
            });
        }

        private async void OnAudioCaptured(float[] samples)
        {
            try
            {
                Debug.WriteLine($"🧠 Transcribing {samples.Length} samples...");
                string result = await m_transcription.TranscribeAsync(samples);
                
                if (!string.IsNullOrEmpty(result))
                {
                    KeystrokeManager.Shared.InsertText(result);
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ Transcription error: {ex.Message}");
            }
        }

        private void OnExitClick(object sender, RoutedEventArgs e)
        {
            Application.Current.Exit();
        }
    }
}
