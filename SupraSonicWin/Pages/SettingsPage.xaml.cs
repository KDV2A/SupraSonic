using Microsoft.UI.Xaml.Controls;
using SupraSonicWin.Models;
using System.Linq;
using System.Collections.ObjectModel;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace SupraSonicWin.Pages
{
    public sealed partial class SettingsPage : Page
    {
        public ObservableCollection<VocabularyItem> Vocabulary { get; set; } = new ObservableCollection<VocabularyItem>();
        private bool IsFrench => L10n.IsFrench;
        private Microsoft.UI.Dispatching.DispatcherQueueTimer m_validationTimer;

        public SettingsPage()
        {
            this.InitializeComponent();
            LocalizeUI();
            LoadSettings();
            VocabularyListView.ItemsSource = Vocabulary;
        }

        private void LocalizeUI()
        {
            TitleText.Text = L10n.SettingsTitle;
            MicHeader.Text = L10n.MicSettings;
            RefreshButton.Content = IsFrench ? "Actualiser" : "Refresh Devices";
            RecordingHeader.Text = L10n.RecordingMode;
            PTTRadio.Content = L10n.PTTOption;
            ToggleRadio.Content = L10n.ToggleOption;
            HistoryToggle.Header = L10n.EnableHistory;
            MuteToggle.Header = L10n.MuteDuringRecording;
            LaunchStartupToggle.Header = L10n.LaunchAtStartup;
            HotkeyHeader.Text = IsFrench ? "Raccourci Global" : "Global Hotkey";
            RecordHotkeyButton.Content = IsFrench ? "Enregistrer un nouveau raccourci" : "Record New Hotkey";
            LLMHeader.Text = L10n.LLMProviderLabel;
            LocalInfoText.Text = L10n.LocalModelActive;
            VocabularyHeader.Text = L10n.VocabularyTab;
            VocabularyDesc.Text = L10n.VocabularyDesc;
            AddWordButton.Content = L10n.AddWordButton;
            AIHotkeyHeader.Text = L10n.AIHotkeyLabel;
            AIPromptHeader.Text = L10n.AIAssistantPromptLabel;
            AIPromptDesc.Text = L10n.AIAssistantPromptDesc;
            RecordAIHotkeyButton.Content = IsFrench ? "Enregistrer un nouveau raccourci" : "Record New Hotkey";
        }

        private void LoadSettings()
        {
            HistoryToggle.IsOn = SettingsManager.Shared.HistoryEnabled;
            MuteToggle.IsOn = SettingsManager.Shared.MuteSystemSoundDuringRecording;
            
            if (SettingsManager.Shared.HotkeyMode == SettingsManager.HotkeyModeType.PushToTalk)
                PTTRadio.IsChecked = true;
            else
                ToggleRadio.IsChecked = true;

            UpdateHotkeyLabel();
            UpdateAIHotkeyLabel();
            RefreshAudioDevices();
            LoadLLMSettings();
            LoadVocabulary();
            AIPromptBox.Text = SettingsManager.Shared.AISkills.FirstOrDefault()?.Prompt ?? "";
            LaunchStartupToggle.IsChecked = LaunchManager.IsLaunchAtStartupEnabled();
        }

        private void LoadLLMSettings()
        {
            var provider = SettingsManager.Shared.LLMProvider;
            string providerTag = provider.ToString().ToLower();
            
            foreach (ComboBoxItem item in LLMProviderComboBox.Items)
            {
                if (item.Tag?.ToString() == providerTag)
                {
                    LLMProviderComboBox.SelectedItem = item;
                    break;
                }
            }

            UpdateApiKeyUI(provider);
        }

        private void UpdateApiKeyUI(LLMProvider provider)
        {
            bool isLocal = provider == LLMProvider.Local;
            bool isNone = provider == LLMProvider.None;
            
            ApiKeyPanel.Visibility = (isLocal || isNone) ? Microsoft.UI.Xaml.Visibility.Collapsed : Microsoft.UI.Xaml.Visibility.Visible;
            LocalInfoText.Visibility = isLocal ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;

            if (!isLocal && !isNone)
            {
                ApiKeyBox.Text = provider switch
                {
                    LLMProvider.Google => SettingsManager.Shared.GeminiApiKey,
                    LLMProvider.OpenAI => SettingsManager.Shared.OpenAIApiKey,
                    LLMProvider.Anthropic => SettingsManager.Shared.AnthropicApiKey,
                    _ => ""
                };

                ModelInfoText.Text = provider switch
                {
                    LLMProvider.Google => $"Model: {LLMManager.GeminiModelName}",
                    LLMProvider.OpenAI => $"Model: {LLMManager.OpenAIModelName}",
                    LLMProvider.Anthropic => $"Model: {LLMManager.AnthropicModelName}",
                    _ => ""
                };

                ValidateCurrentKey();
            }
        }


        private void UpdateHotkeyLabel()
        {
            int vk = SettingsManager.Shared.SelectedHotkeyVK;
            CurrentHotkeyLabel.Text = GetKeyName(vk);
        }

        private void UpdateAIHotkeyLabel()
        {
            int vk = SettingsManager.Shared.SelectedAIHotkeyVK;
            CurrentAIHotkeyLabel.Text = GetKeyName(vk);
        }

        private void OnRecordHotkeyClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            RecordHotkeyButton.Content = "Press any key...";
            this.KeyDown += OnSettingsPageKeyDown;
        }

        private void OnSettingsPageKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            this.KeyDown -= OnSettingsPageKeyDown;
            int vk = (int)e.Key;
            SettingsManager.Shared.SelectedHotkeyVK = vk;
            RecordHotkeyButton.Content = "Record New Hotkey";
            UpdateHotkeyLabel();
            NotificationCenter.Default.Post(new Notification("HotkeyChanged"));
        }

        private void OnRecordAIHotkeyClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            RecordAIHotkeyButton.Content = "Press any key...";
            this.KeyDown += OnSettingsPageAIKeyDown;
        }

        private void OnSettingsPageAIKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            this.KeyDown -= OnSettingsPageAIKeyDown;
            int vk = (int)e.Key;
            SettingsManager.Shared.SelectedAIHotkeyVK = vk;
            RecordAIHotkeyButton.Content = "Record New Hotkey";
            UpdateAIHotkeyLabel();
            NotificationCenter.Default.Post(new Notification("HotkeyChanged"));
        }

        private void OnAIPromptChanged(object sender, TextChangedEventArgs e)
        {
            var skills = SettingsManager.Shared.AISkills;
            if (skills.Count > 0)
            {
                skills[0].Prompt = AIPromptBox.Text;
                SettingsManager.Shared.AISkills = skills;
            }
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

        private void OnMuteToggled(object sender, RoutedEventArgs e)
        {
            SettingsManager.Shared.MuteSystemSoundDuringRecording = MuteToggle.IsOn;
        }

        private void OnLaunchStartupToggled(object sender, RoutedEventArgs e)
        {
            LaunchManager.SetLaunchAtStartup(LaunchStartupToggle.IsOn);
        }

        private void OnLLMProviderChanged(object sender, SelectionChangedEventArgs e)
        {
            if (LLMProviderComboBox.SelectedItem is ComboBoxItem item)
            {
                string providerTag = item.Tag.ToString();
                if (Enum.TryParse<LLMProvider>(providerTag, true, out var provider))
                {
                    SettingsManager.Shared.LLMProvider = provider;
                    UpdateApiKeyUI(provider);
                }
            }
        }

        private void OnApiKeyChanged(object sender, Microsoft.UI.Xaml.Controls.TextChangedEventArgs e)
        {
            LLMProvider provider = SettingsManager.Shared.LLMProvider;
            string key = ApiKeyBox.Text;

            switch (provider)
            {
                case LLMProvider.Google: SettingsManager.Shared.GeminiApiKey = key; break;
                case LLMProvider.OpenAI: SettingsManager.Shared.OpenAIApiKey = key; break;
                case LLMProvider.Anthropic: SettingsManager.Shared.AnthropicApiKey = key; break;
            }

            // Debounce validation
            if (m_validationTimer == null)
            {
                m_validationTimer = this.DispatcherQueue.CreateTimer();
                m_validationTimer.Interval = TimeSpan.FromSeconds(1);
                m_validationTimer.Tick += (s, ev) => {
                    m_validationTimer.Stop();
                    ValidateCurrentKey();
                };
            }
            m_validationTimer.Stop();
            m_validationTimer.Start();
        }

        private async void ValidateCurrentKey()
        {
            LLMProvider provider = SettingsManager.Shared.LLMProvider;
            string key = ApiKeyBox.Text;

            if (provider == LLMProvider.Local || provider == LLMProvider.None)
            {
                StatusIcon.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
                return;
            }

            if (string.IsNullOrEmpty(key))
            {
                StatusIcon.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
                StatusIcon.Symbol = Symbol.OutlineStar;
                StatusIcon.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Gray);
                return;
            }

            // Progress state
            StatusIcon.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
            StatusIcon.Symbol = Symbol.Sync;
            StatusIcon.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Orange);

            bool isValid = await LLMManager.Shared.ValidateApiKey(provider, key);

            // Double check provider hasn't changed during await
            if (SettingsManager.Shared.LLMProvider == provider)
            {
                if (isValid)
                {
                    StatusIcon.Symbol = Symbol.Accept;
                    StatusIcon.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Green);
                }
                else
                {
                    StatusIcon.Symbol = Symbol.Cancel;
                    StatusIcon.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Red);
                }
            }
        }

        private void LoadVocabulary()
        {
            Vocabulary.Clear();
            var mapping = SettingsManager.Shared.VocabularyMapping;
            foreach (var pair in mapping)
            {
                var item = new VocabularyItem { Spoken = pair.Key, Corrected = pair.Value };
                item.PropertyChanged += (s, e) => SaveVocabulary();
                Vocabulary.Add(item);
            }
        }

        private void SaveVocabulary()
        {
            var mapping = new Dictionary<string, string>();
            foreach (var item in Vocabulary)
            {
                if (!string.IsNullOrEmpty(item.Spoken))
                {
                    mapping[item.Spoken] = item.Corrected;
                }
            }
            SettingsManager.Shared.VocabularyMapping = mapping;
        }

        private void OnAddWordClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            var item = new VocabularyItem { Spoken = "new word", Corrected = "NewWord" };
            item.PropertyChanged += (s, e) => SaveVocabulary();
            Vocabulary.Add(item);
            SaveVocabulary();
        }

        private void OnDeleteWordClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            if (sender is Button btn && btn.CommandParameter is VocabularyItem item)
            {
                Vocabulary.Remove(item);
                SaveVocabulary();
            }
        }
    }

    public class VocabularyItem : INotifyPropertyChanged
    {
        private string m_spoken;
        private string m_corrected;

        public string Spoken 
        { 
            get => m_spoken; 
            set { m_spoken = value; OnPropertyChanged(); } 
        }

        public string Corrected 
        { 
            get => m_corrected; 
            set { m_corrected = value; OnPropertyChanged(); } 
        }

        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged([CallerMemberName] string name = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }
}
