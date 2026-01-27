# SupraSonic - Installation & Compilation Windows

Ce dossier contient tout le nécessaire pour faire fonctionner SupraSonic sur Windows. SupraSonic utilise un cœur partagé en Rust pour les performances et une interface native en C# (WinUI 3).

## 📋 Prérequis sur le PC Windows
Avant de commencer, assurez-vous que les outils suivants sont installés :
1. **.NET 8 SDK** : [Télécharger ici](https://dotnet.microsoft.com/download/dotnet/8.0)
2. **Rust (rustup)** : [Télécharger ici](https://rustup.rs/)
3. **Build Tools pour Visual Studio 2022** (Léger, pas besoin de l'IDE complet) :
   - [Télécharger les Build Tools ici](https://visualstudio.microsoft.com/fr/downloads/#build-tools-for-visual-studio-2022) (cherchez "Build Tools pour Visual Studio 2022" en bas de page).
   - Lors de l'installation, cochez uniquement la case **"Développement de bureau en C++"**. Cela installera le compilateur et le SDK Windows nécessaires pour Rust et .NET.

## 🚀 Méthode Rapide (Sans ouvrir d'éditeur)
1. Extrayez le contenu de ce fichier ZIP.
2. Double-cliquez sur le fichier **`build-win.bat`**.
3. Le script va :
   - Compiler le code Rust.
   - Préparer l'application Windows.
   - Créer un dossier nommé `build-win/`.
4. Une fois terminé, ouvrez le dossier `build-win/` et lancez **`SupraSonicWin.exe`**.

## 🧠 À propos du modèle d'Intelligence Artificielle
Le modèle d'IA (Parakeet TDT v3) pèse environ 600 Mo. 
**Vous n'avez pas besoin de le chercher manuellement.** Lors du premier lancement de l'application sur Windows, une fenêtre de configuration ("Onboarding") s'ouvrira automatiquement pour :
- Vérifier l'accès à votre microphone.
- Télécharger automatiquement le modèle depuis nos serveurs.
- Optimiser le moteur pour votre carte graphique (GPU).

## 🛠️ Utilisation avec Visual Studio (Pour le développement)
1. Ouvrez le fichier **`SupraSonic.sln`**.
2. Compilez d'abord le cœur Rust (via terminal : `cd core && cargo build --release --features csharp`).
3. Copiez la DLL générée vers le projet C# comme indiqué dans le script de build.
4. Appuyez sur **F5** dans Visual Studio.

## 🆘 Dépannage (Troubleshooting)

### Erreur `linker link.exe not found`
Cette erreur signifie que Windows ne trouve pas le compilateur C++ dans votre session actuelle.
- **Solution Automatique** : J'ai mis à jour le script `build-win.bat` pour qu'il tente de trouver et d'activer lui-même les outils Visual Studio.
- **Solution Manuelle** (La plus fiable) : 
  1. Appuyez sur la touche `Windows` de votre clavier.
  2. Tapez **"Developer Command Prompt for VS 2022"**.
  3. Dans la fenêtre noire qui s'ouvre, allez dans votre dossier de projet et lancez `build-win.bat`.
