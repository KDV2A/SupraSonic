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
            if (!Models.ModelManager.Shared.HasTargetModel())
            {
                Debug.WriteLine("🚀 Windows: Model missing. Launching Setup...");
                m_setupWindow = new SetupWindow();
                m_setupWindow.Activate();
                
                // When setup closes, we should probably relaunch or show MainWindow
                m_setupWindow.Closed += (s, e) => {
                    if (Models.ModelManager.Shared.HasTargetModel())
                    {
                        m_window = new MainWindow();
                        m_window.Activate();
                    }
                    else
                    {
                        Application.Current.Exit();
                    }
                };
            }
            else
            {
                Debug.WriteLine("✅ Windows: Model found. Launching Main App...");
                m_window = new MainWindow();
                m_window.Activate();
            }
        }

        private MainWindow m_window;
        private SetupWindow m_setupWindow;
    }
}
