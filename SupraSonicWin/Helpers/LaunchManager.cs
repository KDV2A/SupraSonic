using Microsoft.Win32;
using System;
using System.Diagnostics;
using System.IO;

namespace SupraSonicWin.Helpers
{
    public static class LaunchManager
    {
        private const string RUN_KEY = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string APP_NAME = "SupraSonic";

        public static void SetLaunchAtStartup(bool enable)
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RUN_KEY, true))
                {
                    if (enable)
                    {
                        // Get path to the executable
                        string appPath = Process.GetCurrentProcess().MainModule.FileName;
                        key.SetValue(APP_NAME, $"\"{appPath}\"");
                        Debug.WriteLine($"✅ Startup enabled: {appPath}");
                    }
                    else
                    {
                        key.DeleteValue(APP_NAME, false);
                        Debug.WriteLine("✅ Startup disabled");
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ Failed to set launch at startup: {ex.Message}");
            }
        }

        public static bool IsLaunchAtStartupEnabled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RUN_KEY, false))
                {
                    return key.GetValue(APP_NAME) != null;
                }
            }
            catch
            {
                return false;
            }
        }
    }
}
