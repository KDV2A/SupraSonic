using Microsoft.UI.Xaml;
using System;
using System.Threading.Tasks;
using SupraSonicWin.Helpers;

namespace SupraSonicWin
{
    public sealed partial class SetupWindow : Window
    {
        private TranscriptionManager m_transcription = new TranscriptionManager();

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
        }

        private async void OnStartClick(object sender, RoutedEventArgs e)
        {
            StartButton.IsEnabled = false;
            
            try
            {
                // 1. Microphone check
                StatusLabel.Text = L10n.CheckingMic;
                SetupProgressBar.Value = 10;
                
                var capability = Windows.Security.Authorization.AppCapability.Create("microphone");
                var accessStatus = await capability.RequestAccessAsync();

                if (accessStatus != Windows.Security.Authorization.AppCapabilityAccessStatus.Allowed)
                {
                    StatusLabel.Text = L10n.MicDenied;
                    StartButton.Content = IsFrench ? "Ouvrir et Réessayer" : "Open Settings & Retry";
                    StartButton.IsEnabled = true;
                    return;
                }
                SetupProgressBar.Value = 20;

                // 2. Typing/Keystroke check 
                StatusLabel.Text = IsFrench ? "Configuration de la frappe..." : "Configuring keystroke simulation...";
                await Task.Delay(500); 
                SetupProgressBar.Value = 30;

                // 3. Download Model
                StatusLabel.Text = L10n.DownloadingModel;
                for(int i = 30; i <= 80; i += 5)
                {
                    SetupProgressBar.Value = i;
                    await Task.Delay(200);
                }

                // 4. Initialize Engine
                StatusLabel.Text = L10n.OptimizingModel;
                await m_transcription.InitializeAsync();
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
    }
}
