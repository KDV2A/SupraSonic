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

        // Overlay
        public static string Recording => IsFrench ? "Enregistrement..." : "Recording...";

        // Settings / History
        public static string SettingsTitle => IsFrench ? "Paramètres de transcription" : "Transcription Settings";
        public static string MicSettings => IsFrench ? "Paramètres du microphone" : "Microphone Settings";
        public static string RecordingMode => IsFrench ? "Mode d'enregistrement" : "Recording Mode";
        public static string PTTOption => IsFrench ? "Appuyer pour parler (Maintenir Alt Gr)" : "Push to Talk (Hold Alt Gr)";
        public static string ToggleOption => IsFrench ? "Mode On/Off (Cliquer Alt Gr pour démarrer/arrêter)" : "Toggle Mode (Click Alt Gr to start/stop)";
    }
}
