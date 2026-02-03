using System.Globalization;

namespace SupraSonicWin.Helpers
{
    public static class L10n
    {
        public static bool IsFrench => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("fr", System.StringComparison.OrdinalIgnoreCase);

        // Common strings
        public static string AppName => "SupraSonic";
        
        // Onboarding
        public static string WelcomeTitle => IsFrench ? "Bienvenue sur SupraSonic" : "Welcome to SupraSonic";
        public static string SetupDescription => IsFrench 
            ? "Nous devons télécharger le modèle d'intelligence artificielle et vérifier les autorisations." 
            : "We need to download the AI model and check permissions.";
        public static string StartSetup => IsFrench ? "Commencer la configuration" : "Start Setup";
        public static string CheckingMic => IsFrench ? "Vérification de l'accès au micro..." : "Checking microphone access...";
        public static string MicDenied => IsFrench 
            ? "Accès au micro refusé. Veuillez l'activer dans les paramètres de confidentialité Windows." 
            : "Microphone access denied. Please enable it in Windows Privacy Settings.";
        public static string DownloadingModel => IsFrench ? "Téléchargement du modèle d'intelligence artificielle..." : "Downloading AI model...";
        public static string OptimizingModel => IsFrench ? "Optimisation pour votre GPU (DirectML)..." : "Optimizing for your GPU (DirectML)...";
        public static string SetupComplete => IsFrench ? "Configuration terminée !" : "Setup Complete!";

        // LLM Onboarding
        public static string SetupAIEnableTitle => IsFrench ? "Activer l'amélioration par IA ?" : "Enable AI Refinement?";
        public static string SetupAIEnableDesc => IsFrench 
            ? "Utilisez l'IA pour corriger automatiquement la grammaire et l'orthographe. Nécessite une connexion internet." 
            : "Use AI to fix grammar and spelling automatically. Requires an internet connection.";
        public static string SetupAIEnableButton => IsFrench ? "Activer l'IA" : "Enable AI";
        public static string SetupAISkipButton => IsFrench ? "Passer" : "Skip";

        // Options
        public static string EnableHistory => IsFrench ? "Activer l'historique" : "Enable History";
        public static string MuteDuringRecording => IsFrench ? "Couper le son système pendant l'enregistrement" : "Mute system sound during recording";
        public static string LaunchAtStartup => IsFrench ? "Lancer au démarrage" : "Launch at startup";

        // Overlay

        // Settings / History
        public static string SettingsTitle => IsFrench ? "Paramètres de transcription" : "Transcription Settings";
        public static string MicSettings => IsFrench ? "Paramètres du microphone" : "Microphone Settings";
        public static string RecordingMode => IsFrench ? "Mode d'enregistrement" : "Recording Mode";
        public static string PTTOption => IsFrench ? "Appuyer pour parler (Maintenir Alt Gr)" : "Push to Talk (Hold Alt Gr)";
        public static string ToggleOption => IsFrench ? "Mode On/Off (Cliquer Alt Gr pour démarrer/arrêter)" : "Toggle Mode (Click Alt Gr to start/stop)";

        // LLM
        public static string LLMProviderLabel => IsFrench ? "Fournisseur de modèle IA" : "AI Model Provider";
        public static string ApiKeyLabel => IsFrench ? "Clé API" : "API Key";
        public static string LocalModelActive => IsFrench ? "Utilisation du modèle local Mistral (hors ligne)" : "Using local Mistral model (offline)";
        
        // Vocabulary
        public static string VocabularyTab => IsFrench ? "Vocabulaire" : "Vocabulary";
        public static string VocabularyDesc => IsFrench ? "Apprenez à SupraSonic comment écrire des mots spécifiques ou des noms propres." : "Teach SupraSonic how to spell specific words or proper names.";
        public static string SpokenWordLabel => IsFrench ? "Mot entendu" : "Spoken Word";
        public static string CorrectedWordLabel => IsFrench ? "Correction" : "Correction";
        public static string AddWordButton => IsFrench ? "Ajouter" : "Add";
        public static string DeleteButton => IsFrench ? "Supprimer" : "Delete";

        // AI Assistant
        public static string AIHotkeyLabel => IsFrench ? "Raccourci Assistant IA" : "AI Assistant Hotkey";
        public static string AIAssistantPromptLabel => IsFrench ? "Prompt de l'Assistant IA" : "AI Assistant Prompt";
        public static string AIAssistantPromptDesc => IsFrench ? "Définissez comment l'IA doit transformer votre texte." : "Define how the AI transforms your text.";
    }
}
