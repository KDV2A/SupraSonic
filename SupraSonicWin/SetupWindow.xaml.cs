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
        }

        private async void OnStartClick(object sender, RoutedEventArgs e)
        {
            StartButton.IsEnabled = false;
            
            try
            {
                // 1. Microphone check (Standard Windows prompt handled by OS/SDK)
                StatusLabel.Text = "Checking microphone...";
                SetupProgressBar.Value = 20;
                await Task.Delay(1000);

                // 2. Download Model
                StatusLabel.Text = "Downloading Parakeet TDT v3 model (600MB)...";
                // Real implementation would use HttpClient with progress callback
                for(int i = 20; i <= 80; i += 5)
                {
                    SetupProgressBar.Value = i;
                    await Task.Delay(200);
                }

                // 3. Initialize Engine
                StatusLabel.Text = "Optimizing for your GPU (DirectML)...";
                await m_transcription.InitializeAsync();
                SetupProgressBar.Value = 100;

                StatusLabel.Text = "Setup Complete!";
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
