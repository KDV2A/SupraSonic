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
        private TrayManager m_tray = new TrayManager();
        private OverlayWindow m_overlay = new OverlayWindow();
        private bool m_isRecording = false;

        public MainWindow()
        {
            this.InitializeComponent();
            
            // Hide window when started if desired (startup behavior)
            // this.AppWindow.Hide();

            this.Closed += (s, e) => {
                m_hotkey.Cleanup();
                m_tray.Dispose();
            };

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

                // Setup Hotkeys
                m_hotkey.Setup(this);
                m_hotkey.OnHotkeyPressed += OnHotkeyPressed;

                // Setup Tray
                m_tray.Setup(this);
                m_tray.OnShowSettingsRequested += () => {
                    this.Activate();
                    this.AppWindow.Show();
                };
                m_tray.OnExitRequested += () => Application.Current.Exit();

                Debug.WriteLine("✅ SupraSonic: System Integration Complete");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ Setup error: {ex.Message}");
            }
        }

        private void OnHotkeyPressed()
        {
            DispatcherQueue.TryEnqueue(() => {
                if (!m_isRecording)
                {
                    m_isRecording = true;
                    m_rust.StartRecording();
                    m_overlay.Activate();
                    Debug.WriteLine("🎙️ Recording started on Windows hotkey");
                }
                else
                {
                    m_isRecording = false;
                    m_rust.StopRecording();
                    m_overlay.Hide(); // Hide overlay window
                    Debug.WriteLine("⏹️ Recording stopped on Windows hotkey");
                }
            });
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
                    Debug.WriteLine($"📝 Transcribed: {result}");
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
