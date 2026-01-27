using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System;
using System.Diagnostics;
using SupraSonicWin.Native;
using SupraSonicWin.Helpers;
using SupraSonicWin.Models;
using SupraSonicWin.Pages;

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
            
            this.Closed += (s, e) => {
                m_hotkey.Cleanup();
                m_tray.Dispose();
            };

            NavView.SelectedItem = NavView.MenuItems[0];
            ContentFrame.Navigate(typeof(SettingsPage));

            InitializeApp();
        }

        private async void InitializeApp()
        {
            try
            {
                m_rust.Initialize();
                m_rust.OnAudioData += OnAudioCaptured;
                m_rust.OnLevelChanged += OnLevelChanged;

                await m_transcription.InitializeAsync();

                m_hotkey.Setup(this);
                m_hotkey.OnHotkeyPressed += OnHotkeyPressed;
                m_hotkey.OnHotkeyReleased += OnHotkeyReleased;

                m_tray.Setup(this);
                m_tray.OnShowSettingsRequested += () => {
                    this.Activate();
                    this.AppWindow.Show();
                };
                m_tray.OnExitRequested += () => Application.Current.Exit();
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ Setup error: {ex.Message}");
            }
        }

        private void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
        {
            if (args.SelectedItemContainer?.Tag?.ToString() == "history")
                ContentFrame.Navigate(typeof(HistoryPage));
            else
                ContentFrame.Navigate(typeof(SettingsPage));
        }

        private void OnHotkeyPressed()
        {
            DispatcherQueue.TryEnqueue(() => {
                if (SettingsManager.Shared.HotkeyMode == SettingsManager.HotkeyModeType.PushToTalk)
                {
                    if (!m_isRecording)
                    {
                        m_isRecording = true;
                        m_rust.StartRecording();
                        m_overlay.Activate();
                    }
                }
                else // Toggle Mode
                {
                    if (!m_isRecording)
                    {
                        m_isRecording = true;
                        m_rust.StartRecording();
                        m_overlay.Activate();
                    }
                    else
                    {
                        m_isRecording = false;
                        m_rust.StopRecording();
                        m_overlay.Hide();
                    }
                }
            });
        }

        private void OnHotkeyReleased()
        {
            DispatcherQueue.TryEnqueue(() => {
                if (SettingsManager.Shared.HotkeyMode == SettingsManager.HotkeyModeType.PushToTalk)
                {
                    if (m_isRecording)
                    {
                        m_isRecording = false;
                        m_rust.StopRecording();
                        m_overlay.Hide();
                    }
                }
            });
        }

        private void OnLevelChanged(float level)
        {
            DispatcherQueue.TryEnqueue(() => m_overlay.UpdateLevel(level));
        }

        private async void OnAudioCaptured(float[] samples)
        {
            try
            {
                string result = await m_transcription.TranscribeAsync(samples);
                
                if (!string.IsNullOrEmpty(result))
                {
                    KeystrokeManager.Shared.InsertText(result);
                    
                    if (SettingsManager.Shared.HistoryEnabled)
                    {
                        await HistoryManager.Shared.AddEntryAsync(result);
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ Transcription error: {ex.Message}");
            }
        }
    }
}
