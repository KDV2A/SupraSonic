using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System;
using System.Diagnostics;
using System.Linq;
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
        private bool m_isAIMode = false;

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
                m_hotkey.OnAIHotkeyPressed += OnAIHotkeyPressed;
                m_hotkey.OnAIHotkeyReleased += OnAIHotkeyReleased;

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

        private void OnAIHotkeyPressed()
        {
            StartRecording(true);
        }

        private void OnAIHotkeyReleased()
        {
            StopRecording();
        }

        private void OnHotkeyPressed()
        {
            StartRecording(false);
        }

        private void OnHotkeyReleased()
        {
            StopRecording();
        }

        private void StartRecording(bool isAI)
        {
            DispatcherQueue.TryEnqueue(() => {
                if (SettingsManager.Shared.HotkeyMode == SettingsManager.HotkeyModeType.PushToTalk)
                {
                    if (!m_isRecording)
                    {
                        m_isRecording = true;
                        m_isAIMode = isAI;
                        
                        if (SettingsManager.Shared.MuteSystemSoundDuringRecording)
                            VolumeHelper.SetMute(true);

                        m_rust.StartRecording();
                        m_overlay.SetAIMode(isAI);
                        m_overlay.Activate();
                    }
                }
                else // Toggle Mode
                {
                    if (!m_isRecording)
                    {
                        m_isRecording = true;
                        m_isAIMode = isAI;
                        
                        if (SettingsManager.Shared.MuteSystemSoundDuringRecording)
                            VolumeHelper.SetMute(true);

                        m_rust.StartRecording();
                        m_overlay.SetAIMode(isAI);
                        m_overlay.Activate();
                    }
                    else
                    {
                        StopRecording();
                    }
                }
            });
        }

        private void StopRecording()
        {
            DispatcherQueue.TryEnqueue(() => {
                if (m_isRecording)
                {
                    m_isRecording = false;
                    m_rust.StopRecording();
                    
                    if (SettingsManager.Shared.MuteSystemSoundDuringRecording)
                        VolumeHelper.SetMute(false);

                    m_overlay.Hide();
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
                    // Check for AI Skills Triggers (voice-activated)
                    var skills = SettingsManager.Shared.AISkills;
                    
                    // Robust trigger check: trim whitespace and common leading punctuation
                    string cleanText = result.Trim();
                    cleanText = cleanText.TrimStart('.', ',', '!', '?', '-', ' ');
                    string lowerText = cleanText.ToLowerInvariant();
                    
                    var triggeredSkill = skills.FirstOrDefault(s => 
                        !string.IsNullOrEmpty(s.Trigger) && 
                        lowerText.StartsWith(s.Trigger.ToLowerInvariant()));
                    
                    if (triggeredSkill != null)
                    {
                        Debug.WriteLine($"🤖 App: AI Skill Triggered: {triggeredSkill.Name}");
                        
                        // 1. Extract input text (strip trigger word)
                        string trigger = triggeredSkill.Trigger.ToLowerInvariant();
                        string inputText = result;
                        int triggerIdx = inputText.ToLowerInvariant().IndexOf(trigger);
                        if (triggerIdx >= 0)
                        {
                            inputText = inputText.Substring(triggerIdx + trigger.Length);
                        }
                        inputText = inputText.Trim();
                        
                        // 2. Call LLM with the skill's prompt
                        try
                        {
                            string aiResult = await LLMManager.Shared.ProcessSkill(triggeredSkill, inputText);
                            Debug.WriteLine($"🤖 App: AI Skill Result received");
                            result = aiResult;
                        }
                        catch (Exception llmEx)
                        {
                            Debug.WriteLine($"❌ App: AI Skill failed: {llmEx.Message}");
                            // On LLM failure, fall back to raw transcription
                        }
                    }
                    else if (m_isAIMode)
                    {
                        // AI hotkey mode: Transform via LLM with default prompt
                        result = await LLMManager.Shared.GenerateResponse(result);
                    }

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
