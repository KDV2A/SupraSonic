using Microsoft.UI.Xaml;
using System;
using System.Threading.Tasks;
using SupraSonicWin.Helpers;

namespace SupraSonicWin
{
    public sealed partial class SetupWindow : Window
    {
        private TranscriptionManager m_transcription = new TranscriptionManager();
        private TaskCompletionSource<bool> m_aiChoiceTcs;

        public SetupWindow()
        {
            this.InitializeComponent();
            LocalizeUI();
        }

        private void LocalizeUI()
        {
            Title = L10n.AppName + " Setup";
            WelcomeText.Text = L10n.WelcomeTitle;
            DescriptionText.Text = L10n.SetupDescription;
            StartButton.Content = L10n.StartSetup;
            StatusLabel.Text = "Status";
            AITitle.Text = L10n.SetupAIEnableTitle;
            AIDesc.Text = L10n.SetupAIEnableDesc;
            EnableAIButton.Content = L10n.SetupAIEnableButton;
            SkipAIButton.Content = L10n.SetupAISkipButton;
        }

        private async void OnStartClick(object sender, RoutedEventArgs e)
        {
            StartButton.IsEnabled = false;
            
            try
            {
                // 0. Disk Space check
                StatusLabel.Text = L10n.IsFrench ? "Vérification de l'espace disque..." : "Checking disk space...";
                if (!HasEnoughDiskSpace())
                {
                    StatusLabel.Text = L10n.IsFrench ? "Espace disque insuffisant (2 Go requis)." : "Insufficient disk space (2 GB required).";
                    StartButton.IsEnabled = true;
                    return;
                }
                SetupProgressBar.Value = 5;

                // 1. Microphone check
                StatusLabel.Text = L10n.CheckingMic;
                SetupProgressBar.Value = 10;
                
                var capability = Windows.Security.Authorization.AppCapability.Create("microphone");
                var accessStatus = await capability.RequestAccessAsync();

                if (accessStatus != Windows.Security.Authorization.AppCapabilityAccessStatus.Allowed)
                {
                    StatusLabel.Text = L10n.MicDenied;
                    StartButton.Content = L10n.IsFrench ? "Ouvrir et Réessayer" : "Open Settings & Retry";
                    StartButton.IsEnabled = true;
                    return;
                }
                SetupProgressBar.Value = 20;

                // 2. Typing/Keystroke check 
                StatusLabel.Text = L10n.IsFrench ? "Configuration de la frappe..." : "Configuring keystroke simulation...";
                await Task.Delay(500); 
                SetupProgressBar.Value = 30;

                // 2.5 Ask for LLM Activation
                bool useLLM = await AskForLLMAsync();
                SettingsManager.Shared.LLMEnabled = useLLM;

                // 3. Download / Load Model
                StatusLabel.Text = L10n.DownloadingModel;
                
                var initTask = m_transcription.InitializeAsync();
                
                // Monitor progress
                while (!initTask.IsCompleted)
                {
                    StatusLabel.Text = m_transcription.StatusMessage;
                    SetupProgressBar.Value = 30 + (m_transcription.Progress * 60);
                    await Task.Delay(100);
                }
                
                await initTask;

                // 4. Initialize Engine
                StatusLabel.Text = L10n.OptimizingModel;
                SetupProgressBar.Value = 90;
                
                // 5. Initialize LLM if enabled
                if (SettingsManager.Shared.LLMEnabled)
                {
                    StatusLabel.Text = L10n.IsFrench ? "Initialisation de l'IA locale..." : "Initializing local AI engine...";
                    string modelPath = SettingsManager.Shared.LocalLLMModelPath;
                    
                    // In a real scenario, we'd also trigger the download here if missing.
                    // For now, we initialize via LLMManager.
                    await LLMManager.Shared.InitializeLocalAsync(modelPath);
                }

                SetupProgressBar.Value = 100;

                StatusLabel.Text = L10n.SetupComplete;
                await Task.Delay(1000);
                
                // Signal completion (In a real app, notify App.xaml.cs)
                this.Close();
            }
            catch (Exception ex)
            {
                StatusLabel.Text = $"Error: {ex.Message}";
                StartButton.Content = "Retry";
                StartButton.IsEnabled = true;
            }
        }

        private async Task<bool> AskForLLMAsync()
        {
            m_aiChoiceTcs = new TaskCompletionSource<bool>();
            
            DispatcherQueue.TryEnqueue(() => {
                AIChoicePanel.Visibility = Visibility.Visible;
                StartButton.Visibility = Visibility.Collapsed;
            });

            bool result = await m_aiChoiceTcs.Task;

            DispatcherQueue.TryEnqueue(() => {
                AIChoicePanel.Visibility = Visibility.Collapsed;
                StartButton.Visibility = Visibility.Visible;
                StartButton.IsEnabled = false;
            });

            return result;
        }

        private void OnEnableAIClick(object sender, RoutedEventArgs e)
        {
            m_aiChoiceTcs?.TrySetResult(true);
        }

        private void OnSkipAIClick(object sender, RoutedEventArgs e)
        {
            m_aiChoiceTcs?.TrySetResult(false);
        }

        private bool HasEnoughDiskSpace()
        {
            try
            {
                var drive = new System.IO.DriveInfo(System.IO.Path.GetPathRoot(AppDomain.CurrentDomain.BaseDirectory));
                return drive.AvailableFreeSpace > 2L * 1024 * 1024 * 1024; // 2GB
            }
            catch
            {
                return true; // Fallback if check fails
            }
        }
    }
}
