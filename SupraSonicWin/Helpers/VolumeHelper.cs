using System;
using System.Runtime.InteropServices;

namespace SupraSonicWin.Helpers
{
    public static class VolumeHelper
    {
        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

        private const byte VK_VOLUME_MUTE = 0xAD;
        private const int KEYEVENTF_EXTENDEDKEY = 0x1;
        private const int KEYEVENTF_KEYUP = 0x2;

        // Note: VK_VOLUME_MUTE is a toggle. 
        // For a more robust implementation without a toggle, we'd need CoreAudio COM APIs.
        // For this app, we'll use a simple approach or PowerShell as a fallback.
        
        public static void SetMute(bool mute)
        {
            try {
                // Using PowerShell to ensure we set an absolute state (not a toggle)
                string command = mute 
                    ? "(New-Object -ComObject MMDeviceEnumerator).GetDefaultAudioEndpoint(0,0).AudioEndpointVolume.Mute = $true"
                    : "(New-Object -ComObject MMDeviceEnumerator).GetDefaultAudioEndpoint(0,0).AudioEndpointVolume.Mute = $false";
                
                var process = new System.Diagnostics.ProcessStartInfo {
                    FileName = "powershell.exe",
                    Arguments = $"-Command \"{command}\"",
                    WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden,
                    CreateNoWindow = true
                };
                System.Diagnostics.Process.Start(process);
            } catch (Exception ex) {
                System.Diagnostics.Debug.WriteLine($"❌ VolumeHelper Error: {ex.Message}");
            }
        }
    }
}
