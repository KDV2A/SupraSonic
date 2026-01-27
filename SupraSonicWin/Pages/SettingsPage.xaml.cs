using Microsoft.UI.Xaml.Controls;
using SupraSonicWin.Models;
using System.Linq;

namespace SupraSonicWin.Pages
{
    public sealed partial class SettingsPage : Page
    {
        public SettingsPage()
        {
            this.InitializeComponent();
            LocalizeUI();
            LoadSettings();
        }

        private void LocalizeUI()
        {
            TitleText.Text = L10n.SettingsTitle;
            MicHeader.Text = L10n.MicSettings;
            RefreshButton.Content = IsFrench ? "Actualiser" : "Refresh Devices";
            RecordingHeader.Text = L10n.RecordingMode;
            PTTRadio.Content = L10n.PTTOption;
            ToggleRadio.Content = L10n.ToggleOption;
            HistoryToggle.Header = IsFrench ? "Activer l'historique" : "Enable History";
            HotkeyHeader.Text = IsFrench ? "Raccourci Global" : "Global Hotkey";
            RecordHotkeyButton.Content = IsFrench ? "Enregistrer un nouveau raccourci" : "Record New Hotkey";
        }

        private void LoadSettings()
        {
            HistoryToggle.IsOn = SettingsManager.Shared.HistoryEnabled;
            
            if (SettingsManager.Shared.HotkeyMode == SettingsManager.HotkeyModeType.PushToTalk)
                PTTRadio.IsChecked = true;
            else
                ToggleRadio.IsChecked = true;

            UpdateHotkeyLabel();
            RefreshAudioDevices();
        }

        private void UpdateHotkeyLabel()
        {
            int vk = SettingsManager.Shared.SelectedHotkeyVK;
            CurrentHotkeyLabel.Text = GetKeyName(vk);
        }

        private void OnRecordHotkeyClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            RecordHotkeyButton.Content = "Press any key...";
            this.KeyDown += OnSettingsPageKeyDown;
        }

        private void OnSettingsPageKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            this.KeyDown -= OnSettingsPageKeyDown;
            
            // Get virtual key (Windows.System.VirtualKey to int)
            int vk = (int)e.Key;
            
            SettingsManager.Shared.SelectedHotkeyVK = vk;
            RecordHotkeyButton.Content = "Record New Hotkey";
            UpdateHotkeyLabel();

            // Notify application to update hook
            NotificationCenter.Default.Post(new Notification("HotkeyChanged"));
        }

        private string GetKeyName(int vk)
        {
            return vk switch
            {
                0xA5 => "Alt Gr",
                0x12 => "Alt",
                0x11 => "Ctrl",
                0x10 => "Shift",
                0x5B => "Win",
                0x20 => "Space",
                _ => ((Windows.System.VirtualKey)vk).ToString()
            };
        }

        private async void RefreshAudioDevices()
        {
            MicrophoneComboBox.Items.Clear();
            MicrophoneComboBox.Items.Add(new ComboBoxItem { Content = "Default System Microphone", Tag = "Default" });

            try 
            {
                // In a real Windows environment, this uses WinRT to list devices
                var devices = await Windows.Devices.Enumeration.DeviceInformation.FindAllAsync(
                    Windows.Devices.Enumeration.DeviceClass.AudioCapture);
                
                foreach (var device in devices)
                {
                    MicrophoneComboBox.Items.Add(new ComboBoxItem { 
                        Content = device.Name, 
                        Tag = device.Id 
                    });
                }
            } catch { /* Fallback for local build */ }

            MicrophoneComboBox.SelectedIndex = 0;
        }

        private void OnHotkeyModeChanged(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            if (PTTRadio.IsChecked == true)
                SettingsManager.Shared.HotkeyMode = SettingsManager.HotkeyModeType.PushToTalk;
            else
                SettingsManager.Shared.HotkeyMode = SettingsManager.HotkeyModeType.Toggle;
        }

        private void OnMicrophoneChanged(object sender, SelectionChangedEventArgs e)
        {
            if (MicrophoneComboBox.SelectedItem is ComboBoxItem item)
                SettingsManager.Shared.SelectedMicrophone = item.Tag.ToString();
        }

        private void OnRefreshDevicesClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            RefreshAudioDevices();
        }

        private void OnHistoryToggled(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            SettingsManager.Shared.HistoryEnabled = HistoryToggle.IsOn;
        }
    }
}
