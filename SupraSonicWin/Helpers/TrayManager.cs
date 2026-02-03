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

            // Context Menu
            var menu = new Microsoft.UI.Xaml.Controls.MenuFlyout();
            
            // Version Item (Disabled)
            var versionItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { 
                Text = "SupraSonic v1.2.0", // Hardcoded for now as assembly versioning can be complex in WinUI 3
                IsEnabled = false 
            };
            menu.Items.Add(versionItem);
            menu.Items.Add(new Microsoft.UI.Xaml.Controls.MenuFlyoutSeparator());

            // Settings Item
            var settingsItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { Text = "Settings" };
            settingsItem.Click += (s, e) => OnShowSettingsRequested?.Invoke();
            menu.Items.Add(settingsItem);

            // Exit Item
            var exitItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { Text = "Exit" };
            exitItem.Click += (s, e) => OnExitRequested?.Invoke();
            menu.Items.Add(exitItem);

            m_taskbarIcon.ContextFlyout = menu;
        }

        public void Dispose()
        {
            m_taskbarIcon?.Dispose();
        }
    }
}
