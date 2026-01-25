using System;
using Microsoft.UI.Xaml;
using H.NotifyIcon;
using H.NotifyIcon.Core;

namespace SupraSonicWin.Helpers
{
    /// <summary>
    /// Manages the system tray icon for the Windows application.
    /// </summary>
    public class TrayManager : IDisposable
    {
        private TaskbarIcon m_taskbarIcon;

        public event Action OnExitRequested;
        public event Action OnShowSettingsRequested;

        public void Setup(Window window)
        {
            string iconPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Assets", "app_icon.png");
            
            m_taskbarIcon = new TaskbarIcon
            {
                // In a production app, use a real .ico for better quality
                Icon = System.IO.File.Exists(iconPath) 
                    ? new System.Drawing.Bitmap(iconPath).GetHicon().ToIcon() 
                    : System.Drawing.SystemIcons.Application,
                ToolTipText = "SupraSonic"
            };

            // Double click to show settings
            m_taskbarIcon.TrayLeftMouseDown += (s, e) => OnShowSettingsRequested?.Invoke();

            // Context Menu (Simplified)
            // In a full WinUI 3 app, we'd define this in XAML or via a MenuFlyout
            // For now, we'll hook into the standard Tray events
        }

        public void Dispose()
        {
            m_taskbarIcon?.Dispose();
        }
    }
}
