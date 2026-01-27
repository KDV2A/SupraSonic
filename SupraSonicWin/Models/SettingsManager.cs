using System;
using Windows.Storage;

namespace SupraSonicWin.Models
{
    public class SettingsManager
    {
        public static SettingsManager Shared { get; } = new SettingsManager();

        private ApplicationDataContainer m_localSettings = ApplicationData.Current.LocalSettings;

        private const string KEY_HOTKEY_MODE = "HotkeyMode";
        private const string KEY_HISTORY_ENABLED = "HistoryEnabled";
        private const string KEY_MICROPHONE = "SelectedMicrophone";
        private const string KEY_HOTKEY_VK = "SelectedHotkeyVK";

        public enum HotkeyModeType { PushToTalk, Toggle }

        public HotkeyModeType HotkeyMode
        {
            get => (HotkeyModeType)(m_localSettings.Values[KEY_HOTKEY_MODE] ?? (int)HotkeyModeType.PushToTalk);
            set => m_localSettings.Values[KEY_HOTKEY_MODE] = (int)value;
        }

        public int SelectedHotkeyVK
        {
            get => (int)(m_localSettings.Values[KEY_HOTKEY_VK] ?? 0xA5); // Default: Right Alt (Alt Gr)
            set => m_localSettings.Values[KEY_HOTKEY_VK] = value;
        }

        public string SelectedMicrophone
        {
            get => (string)m_localSettings.Values[KEY_MICROPHONE] ?? "Default";
            set => m_localSettings.Values[KEY_MICROPHONE] = value;
        }

        public bool HistoryEnabled
        {
            get => (bool?)m_localSettings.Values[KEY_HISTORY_ENABLED] ?? true;
            set => m_localSettings.Values[KEY_HISTORY_ENABLED] = value;
        }

        public void Reset()
        {
            m_localSettings.Values.Clear();
        }
    }
}
