using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Interop;

namespace SupraSonicWin.Helpers
{
    /// <summary>
    /// Manages global hotkeys for Windows using a Low-Level Keyboard Hook.
    /// Supports Push-to-Talk and Toggle modes.
    /// </summary>
    public class HotkeyManager
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;
        private const int VK_RMENU = 0xA5; // Right Alt / Alt Gr

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
        private LowLevelKeyboardProc m_proc;
        private IntPtr m_hookId = IntPtr.Zero;

        public event Action OnHotkeyPressed;
        public event Action OnHotkeyReleased;

        public void Setup(Window window)
        {
            m_proc = HookCallback;
            m_hookId = SetHook(m_proc);
        }

        public void Cleanup()
        {
            if (m_hookId != IntPtr.Zero)
            {
                UnhookWindowsHookEx(m_hookId);
            }
        }

        private IntPtr SetHook(LowLevelKeyboardProc proc)
        {
            using (var curProcess = System.Diagnostics.Process.GetCurrentProcess())
            using (var curModule = curProcess.MainModule)
            {
                return SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(curModule.ModuleName), 0);
            }
        }

        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                int vkCode = Marshal.ReadInt32(lParam);
                int targetVK = Models.SettingsManager.Shared.SelectedHotkeyVK;

                if (vkCode == targetVK)
                {
                    if (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN)
                        OnHotkeyPressed?.Invoke();
                    else if (wParam == (IntPtr)WM_KEYUP || wParam == (IntPtr)WM_SYSKEYUP)
                        OnHotkeyReleased?.Invoke();
                    
                    return (IntPtr)1; // Consume key
                }
            }
            return CallNextHookEx(m_hookId, nCode, wParam, lParam);
        }
    }
}
