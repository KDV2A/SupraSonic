import Foundation

struct L10n: Equatable {
    static var isFrench: Bool {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang == "fr"
    }
    
    static var current: L10n = {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang == "fr" ? L10n.fr : L10n.en
    }()
    
    // Settings Window
    let settingsTitle: String
    let generalTab: String
    let historyTab: String
    let aiAssistantTab: String
    let muteDuringRecording: String
    let muteDuringRecordingDesc: String
    let llmProviderLabel: String
    let apiKeyLabel: String
    let localModelActive: String
    
    // Sections
    let shortcutsSection: String
    let hotkeyModeLabel: String
    let hotkeyModePTT: String
    let hotkeyModeToggle: String
    let optionsSection: String
    let magicKey: String
    let magicKeyDesc: String
    
    // Configuration options
    let pushToTalk: String
    let pushToTalkDesc: String
    let pushToTalkDefault: String
    let recordToggle: String
    let recordToggleDesc: String
    let recordToggleDefault: String
    let clickToChangeShortcut: String
    let enableHistory: String
    let enableHistoryDesc: String
    let launchAtStartup: String
    let launchAtStartupDesc: String
    let microphone: String
    let microphoneDesc: String
    let micPermissionDenied: String
    let micRequested: String
    let micNotAvailable: String
    
    // History
    let dateColumn: String
    let transcriptionColumn: String
    let clearHistory: String
    let copy: String
    let clearHistoryConfirm: String
    let clearHistoryMessage: String
    
    // Vocabulary
    let vocabularyTab: String
    let vocabularyDesc: String
    let addWord: String
    let spokenWord: String
    let correctedWord: String
    let delete: String
    
    // AI Assistant
    let aiAssistantPromptLabel: String
    let aiAssistantPromptDesc: String
    
    // Buttons
    let reset: String
    let resetConfirm: String
    let resetMessage: String
    let cancel: String
    let clickToSet: String
    let pressKey: String
    
    // Menu
    let settings: String
    let quit: String
    let selectMicrophone: String
    
    // Overlay
    let recording: String
    
    // Model Section
    let modelSection: String
    let modelInstalled: String
    let modelActive: String
    let modelDownload: String
    let modelDownloading: String
    let modelRequired: String
    let modelRequiredMessage: String
    let modelSize: String
    let modelDelete: String
    let modelActivate: String
    
    // Setup Guide
    let setupTitle: String
    let setupMicrophoneStep: String
    let setupMicrophoneDone: String
    let setupAccessibilityStep: String
    let setupAccessibilityDone: String
    let setupGrantMicrophone: String
    let setupOpenMicrophoneSettings: String
    let setupOpenAccessibilitySettings: String
    let setupContinue: String
    let accessibilityRequiredTitle: String
    let accessibilityRequiredMessage: String
    let accessibilityTroubleshootTitle: String
    let accessibilityTroubleshootMessage: String
    let accessibilityRepairAndRelaunch: String
    
    // Detailed Setup
    let setupDiskCheck: String
    let setupInsufficientSpace: String
    let setupInstalling: String
    let setupDownloadParakeet: String
    let setupReady: String
    let setupGetStarted: String
    let setupDesc: String
    let setupMagicKeyTip: String
    let setupError: String
    let setupInstallationComplete: String
    let setupLLMTitle: String
    let setupLLMDesc: String
    let setupLLMEnable: String
    let setupLLMSkip: String
    let setupTrashInstallerPrompt: String
    let yes: String
    let no: String
    let setupDragToInstall: String
    
    // English
    static let en = L10n(
        settingsTitle: "SupraSonic Settings",
        generalTab: "General",
        historyTab: "History",
        aiAssistantTab: "AI Assistant",
        muteDuringRecording: "Mute During Recording",
        muteDuringRecordingDesc: "Mute system sounds while recording is in progress",
        llmProviderLabel: "AI Model Provider",
        apiKeyLabel: "API Key",
        localModelActive: "Using local Mistral model (offline)",
        shortcutsSection: "KEYBOARD SHORTCUT",
        hotkeyModeLabel: "Mode",
        hotkeyModePTT: "Push to Talk",
        hotkeyModeToggle: "Recording On/Off",
        optionsSection: "Options",
        magicKey: "Magic Key",
        magicKeyDesc: "The special key used to control SupraSonic.",
        pushToTalk: "Push to Talk",
        pushToTalkDesc: "Hold to record, release to transcribe",
        pushToTalkDefault: "⌘ Right",
        recordToggle: "Recording On/Off",
        recordToggleDesc: "One press starts recording, another ends it",
        recordToggleDefault: "⌥ Right",
        clickToChangeShortcut: "Click to set another shortcut",
        enableHistory: "Enable History",
        enableHistoryDesc: "Keep all recordings in memory",
        launchAtStartup: "Launch at Startup",
        launchAtStartupDesc: "Automatically launch the app when the computer starts",
        microphone: "Microphone",
        microphoneDesc: "Select the microphone to use for recording",
        micPermissionDenied: "Access Denied",
        micRequested: "Request Access",
        micNotAvailable: "Disconnected",
        dateColumn: "Date",
        transcriptionColumn: "Transcription",
        clearHistory: "Clear History",
        copy: "Copy",
        clearHistoryConfirm: "Clear History?",
        clearHistoryMessage: "All transcriptions will be deleted.",
        
        // Vocabulary
        vocabularyTab: "Vocabulary",
        vocabularyDesc: "Teach SupraSonic how to spell specific words or proper names.",
        addWord: "Add Word",
        spokenWord: "Spoken Word (e.g., supra sonic)",
        correctedWord: "Correction (e.g., SupraSonic)",
        delete: "Delete",
        aiAssistantPromptLabel: "Assistant Prompt",
        aiAssistantPromptDesc: "This prompt defines how the AI transforms the text you highlight. Triggered by Right Option.",
        reset: "Reset",
        resetConfirm: "Reset Settings?",
        resetMessage: "All settings will be restored to their default values.",
        cancel: "Cancel",
        clickToSet: "Click to set",
        pressKey: "Press a key...",
        settings: "Settings...",
        quit: "Quit",
        selectMicrophone: "Microphone",
        recording: "Recording",
        modelSection: "Transcription Model",
        modelInstalled: "Installed",
        modelActive: "Active",
        modelDownload: "Download",
        modelDownloading: "Downloading...",
        modelRequired: "Model Required",
        modelRequiredMessage: "Please download a transcription model to use SupraSonic. Go to Settings to download a model.",
        modelSize: "Size",
        modelDelete: "Delete",
        modelActivate: "Activate",
        setupTitle: "Welcome to SupraSonic",
        setupMicrophoneStep: "Microphone Access\nSupraSonic needs to access your microphone to record your voice.",
        setupMicrophoneDone: "Microphone access granted",
        setupAccessibilityStep: "Accessibility Access\nSupraSonic needs accessibility access to paste transcribed text and use global shortcuts.",
        setupAccessibilityDone: "Accessibility access granted",
        setupGrantMicrophone: "Grant Microphone Access",
        setupOpenMicrophoneSettings: "Open Microphone Settings",
        setupOpenAccessibilitySettings: "Open Accessibility Settings",
        setupContinue: "Continue",
        accessibilityRequiredTitle: "Accessibility Access Required",
        accessibilityRequiredMessage: "SupraSonic needs accessibility access to paste text. Please enable it in System Settings > Privacy & Security > Accessibility.",
        accessibilityTroubleshootTitle: "Having trouble?",
        accessibilityTroubleshootMessage: "If you've enabled it but it's still not working, we can reset the permissions for you. This will relaunch the app.",
        accessibilityRepairAndRelaunch: "Reset & Relaunch",
        setupDiskCheck: "Checking disk space...",
        setupInsufficientSpace: "Insufficient disk space (2 GB required).",
        setupInstalling: "Installation...",
        setupDownloadParakeet: "Downloading AI model...",
        setupReady: "Ready!",
        setupGetStarted: "Get Started",
        setupDesc: "Welcome to the SupraSonic installation. Get ready to dictate at the speed of sound!",
        setupMagicKeyTip: "The magic key Command Right triggers the recording.",
        setupError: "Error",
        setupInstallationComplete: "Installation Complete",
        setupLLMTitle: "Enable AI Reasoning?",
        setupLLMDesc: "Enhance your voice notes with an on-device AI (LiquidAI). This will download an additional 800MB model.",
        setupLLMEnable: "Enable AI Enhanced Mode",
        setupLLMSkip: "Standard Mode only",
        setupTrashInstallerPrompt: "Would you like to move the installer to the Trash?",
        yes: "Yes",
        no: "No",
        setupDragToInstall: "Drag SupraSonic to your Applications folder"
    )
    
    // French
    static let fr = L10n(
        settingsTitle: "Paramètres SupraSonic",
        generalTab: "Général",
        historyTab: "Historique",
        aiAssistantTab: "Assistant IA",
        muteDuringRecording: "Couper le son pendant l'enregistrement",
        muteDuringRecordingDesc: "Coupe le son du système pendant les phases d'enregistrement",
        llmProviderLabel: "Fournisseur de modèle IA",
        apiKeyLabel: "Clé API",
        localModelActive: "Utilisation du modèle Mistral local (hors-ligne)",
        shortcutsSection: "RACCOURCI CLAVIER",
        hotkeyModeLabel: "Mode",
        hotkeyModePTT: "Push to Talk",
        hotkeyModeToggle: "Enregistrement On/Off",
        optionsSection: "Options",
        magicKey: "Touche Magique",
        magicKeyDesc: "La touche spéciale utilisée pour contrôler SupraSonic.",
        pushToTalk: "Push to Talk",
        pushToTalkDesc: "Maintenir appuyé pour enregistrer, relâcher pour écrire",
        pushToTalkDefault: "⌘ Droite",
        recordToggle: "Enregistrement On/Off",
        recordToggleDesc: "Un appui lance l'enregistrement un autre le termine",
        recordToggleDefault: "⌥ Droite",
        clickToChangeShortcut: "Cliquer pour définir un autre raccourci",
        enableHistory: "Activer l'historique",
        enableHistoryDesc: "Garder en mémoire tous les enregistrements",
        launchAtStartup: "Lancement au démarrage",
        launchAtStartupDesc: "Lancer automatiquement l'application au démarrage de l'ordinateur",
        microphone: "Microphone",
        microphoneDesc: "Sélectionner le microphone à utiliser pour l'enregistrement",
        micPermissionDenied: "Accès refusé",
        micRequested: "Demander l'accès",
        micNotAvailable: "Déconnecté",
        dateColumn: "Date",
        transcriptionColumn: "Transcription",
        clearHistory: "Effacer l'historique",
        copy: "Copier",
        clearHistoryConfirm: "Effacer l'historique?",
        clearHistoryMessage: "Toutes les transcriptions seront supprimées.",
        
        // Vocabulary
        vocabularyTab: "Vocabulaire",
        vocabularyDesc: "Apprenez à SupraSonic comment écrire des mots spécifiques ou des noms propres.",
        addWord: "Ajouter un mot",
        spokenWord: "Mot entendu (ex: supra sonic)",
        correctedWord: "Correction (ex: SupraSonic)",
        delete: "Supprimer",
        aiAssistantPromptLabel: "Prompt de l'Assistant",
        aiAssistantPromptDesc: "Ce prompt définit comment l'IA transforme le texte que vous surlignez via Option Droite.",
        reset: "Réinitialiser",
        resetConfirm: "Réinitialiser les paramètres?",
        resetMessage: "Tous les paramètres seront remis à leurs valeurs par défaut.",
        cancel: "Annuler",
        clickToSet: "Cliquer pour définir",
        pressKey: "Appuyez sur une touche...",
        settings: "Paramètres...",
        quit: "Quitter",
        selectMicrophone: "Microphone",
        recording: "Enregistrement",
        modelSection: "Modèle de transcription",
        modelInstalled: "Installé",
        modelActive: "Actif",
        modelDownload: "Télécharger",
        modelDownloading: "Téléchargement...",
        modelRequired: "Modèle requis",
        modelRequiredMessage: "Veuillez télécharger un modèle de transcription pour utiliser SupraSonic. Allez dans les Paramètres pour télécharger un modèle.",
        modelSize: "Taille",
        modelDelete: "Supprimer",
        modelActivate: "Activer",
        setupTitle: "Bienvenue dans SupraSonic",
        setupMicrophoneStep: "Accès au Microphone\nSupraSonic a besoin d'accéder à votre microphone pour enregistrer votre voix.",
        setupMicrophoneDone: "Accès au microphone accordé",
        setupAccessibilityStep: "Accès à l'Accessibilité\nSupraSonic a besoin de l'accès accessibilité pour coller le texte transcrit et utiliser les raccourcis globaux.",
        setupAccessibilityDone: "Accès accessibilité accordé",
        setupGrantMicrophone: "Autoriser le Microphone",
        setupOpenMicrophoneSettings: "Ouvrir Réglages Microphone",
        setupOpenAccessibilitySettings: "Ouvrir Réglages Accessibilité",
        setupContinue: "Continuer",
        accessibilityRequiredTitle: "Accès Accessibilité Requis",
        accessibilityRequiredMessage: "SupraSonic a besoin de l'accès accessibilité pour coller le texte. Veuillez l'activer dans Réglages Système > Confidentialité et sécurité > Accessibilité.",
        accessibilityTroubleshootTitle: "Besoin d'aide ?",
        accessibilityTroubleshootMessage: "Si vous l'avez activé mais que cela ne marche pas, nous pouvons réinitialiser les permissions pour vous. Cela relancera l'application.",
        accessibilityRepairAndRelaunch: "Réinitialiser et Relancer",
        setupDiskCheck: "Vérification de l'espace disque...",
        setupInsufficientSpace: "Espace disque insuffisant (2 Go requis).",
        setupInstalling: "Installation...",
        setupDownloadParakeet: "Téléchargement du modèle d'intelligence artificielle en cours...",
        setupReady: "Prêt !",
        setupGetStarted: "Commencer",
        setupDesc: "Bienvenue dans l'installation de SupraSonic. Préparez-vous à dicter à la vitesse du son !",
        setupMagicKeyTip: "La touche magique Command Droite déclenche l'enregistrement.",
        setupError: "Erreur",
        setupInstallationComplete: "Installation terminée",
        setupLLMTitle: "Activer l'IA de Réflexion ?",
        setupLLMDesc: "Améliorez vos notes vocales avec une IA locale (LiquidAI). Cela téléchargera un modèle supplémentaire de 800 Mo.",
        setupLLMEnable: "Activer le mode enrichi par l'IA",
        setupLLMSkip: "Mode Standard uniquement",
        setupTrashInstallerPrompt: "Voulez-vous placer l'installeur dans la corbeille ?",
        yes: "Oui",
        no: "Non",
        setupDragToInstall: "Faites glisser SupraSonic vers votre dossier Applications"
    )
}
