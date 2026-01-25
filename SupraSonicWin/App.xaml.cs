using Microsoft.UI.Xaml;
using System;
using System.Diagnostics;
using SupraSonicWin.Native;

namespace SupraSonicWin
{
    public partial class App : Application
    {
        private MainWindow m_window;
        private RustCore m_rust;

        public App()
        {
            this.InitializeComponent();
        }

        protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
        {
            try 
            {
                m_rust = new RustCore();
                m_rust.Initialize();
                Debug.WriteLine("🦀 Rust Core Initialized on Windows");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ Rust Initialization Failed: {ex.Message}");
            }

            m_window = new MainWindow();
            m_window.Activate();
        }
    }
}
