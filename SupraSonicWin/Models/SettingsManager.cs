using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Windows.Storage;

namespace SupraSonicWin.Models
{
    public enum LLMProvider
    {
        None,
        Local,
        Google,
        OpenAI,
        Anthropic
    }

    public class AISkill
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Name { get; set; }
        public string Trigger { get; set; }
        public string Prompt { get; set; }
        public string Color { get; set; } = "blue";
    }

    public class SettingsManager
    {
        public static SettingsManager Shared { get; } = new SettingsManager();

        private ApplicationDataContainer m_localSettings = ApplicationData.Current.LocalSettings;

        private const string KEY_HOTKEY_MODE = "HotkeyMode";
        private const string KEY_HISTORY_ENABLED = "HistoryEnabled";
        private const string KEY_MICROPHONE = "SelectedMicrophone";
        private const string KEY_MUTE_DURING_RECORDING = "MuteDuringRecording";
        private const string KEY_HOTKEY_VK = "SelectedHotkeyVK";
        private const string KEY_LLM_PROVIDER = "LLMProvider";
        private const string KEY_GEMINI_API_KEY = "GeminiApiKey";
        private const string KEY_OPENAI_API_KEY = "OpenAIApiKey";
        private const string KEY_ANTHROPIC_API_KEY = "AnthropicApiKey";
        private const string KEY_VOCABULARY_MAPPING = "VocabularyMapping";
        private const string KEY_AI_HOTKEY_VK = "SelectedAIHotkeyVK";
        private const string KEY_AI_SKILLS = "AISkills"; // New: Alignment with macOS
        private const string KEY_LLM_ENABLED = "LLMEnabled";
        private const string KEY_LOCAL_LLM_MODEL_PATH = "LocalLLMModelPath";
        private const string KEY_LOCAL_ASR_MODEL_PATH = "LocalASRModelPath";

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

        public bool MuteSystemSoundDuringRecording
        {
            get => (bool?)m_localSettings.Values[KEY_MUTE_DURING_RECORDING] ?? false;
            set => m_localSettings.Values[KEY_MUTE_DURING_RECORDING] = value;
        }

        public LLMProvider LLMProvider
        {
            get
            {
                string value = (string)m_localSettings.Values[KEY_LLM_PROVIDER] ?? "none";
                if (Enum.TryParse<LLMProvider>(value, true, out var provider)) return provider;
                return LLMProvider.None;
            }
            set => m_localSettings.Values[KEY_LLM_PROVIDER] = value.ToString().ToLower();
        }

        public string GeminiApiKey
        {
            get => (string)m_localSettings.Values[KEY_GEMINI_API_KEY] ?? "";
            set => m_localSettings.Values[KEY_GEMINI_API_KEY] = value;
        }

        public string OpenAIApiKey
        {
            get => (string)m_localSettings.Values[KEY_OPENAI_API_KEY] ?? "";
            set => m_localSettings.Values[KEY_OPENAI_API_KEY] = value;
        }

        public string AnthropicApiKey
        {
            get => (string)m_localSettings.Values[KEY_ANTHROPIC_API_KEY] ?? "";
            set => m_localSettings.Values[KEY_ANTHROPIC_API_KEY] = value;
        }

        public Dictionary<string, string> VocabularyMapping
        {
            get
            {
                string json = (string)m_localSettings.Values[KEY_VOCABULARY_MAPPING];
                if (string.IsNullOrEmpty(json)) return new Dictionary<string, string>();
                try { return JsonSerializer.Deserialize<Dictionary<string, string>>(json); }
                catch { return new Dictionary<string, string>(); }
            }
            set => m_localSettings.Values[KEY_VOCABULARY_MAPPING] = JsonSerializer.Serialize(value);
        }

        public List<AISkill> AISkills
        {
            get
            {
                string json = (string)m_localSettings.Values[KEY_AI_SKILLS];
                if (string.IsNullOrEmpty(json))
                {
                    return new List<AISkill> {
                        new AISkill {
                            Name = Helpers.L10n.IsFrench ? "Traduction" : "Translation",
                            Trigger = Helpers.L10n.IsFrench ? "traduction" : "translation",
                            Prompt = "Tu es un traducteur Français-Anglais professionnel, traduis l’input sans commentaires ni formatage. Input:",
                            Color = "blue"
                        }
                    };
                }
                try { return JsonSerializer.Deserialize<List<AISkill>>(json); }
                catch { return new List<AISkill>(); }
            }
            set => m_localSettings.Values[KEY_AI_SKILLS] = JsonSerializer.Serialize(value);
        }

        public int SelectedAIHotkeyVK
        {
            get => (int)(m_localSettings.Values[KEY_AI_HOTKEY_VK] ?? 0xA3); // Default: Right Ctrl
            set => m_localSettings.Values[KEY_AI_HOTKEY_VK] = value;
        }

        public bool LLMEnabled
        {
            get => (bool?)m_localSettings.Values[KEY_LLM_ENABLED] ?? false;
            set
            {
                m_localSettings.Values[KEY_LLM_ENABLED] = value;
                if (value && LLMProvider == LLMProvider.None)
                {
                    LLMProvider = LLMProvider.Local;
                }
            }
        }

        public string LocalLLMModelPath
        {
            get => (string)m_localSettings.Values[KEY_LOCAL_LLM_MODEL_PATH] ?? System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SupraSonic", "Models", "ministral-3b-instruct-q4.gguf");
            set => m_localSettings.Values[KEY_LOCAL_LLM_MODEL_PATH] = value;
        }

        public string LocalASRModelPath
        {
            get => (string)m_localSettings.Values[KEY_LOCAL_ASR_MODEL_PATH] ?? System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SupraSonic", "Models", "parakeet-tdt-0.6b-v3-onnx.onnx");
            set => m_localSettings.Values[KEY_LOCAL_ASR_MODEL_PATH] = value;
        }

        public void Reset()
        {
            m_localSettings.Values.Clear();
        }
    }
}

