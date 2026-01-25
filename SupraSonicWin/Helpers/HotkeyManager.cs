using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Interop;

namespace SupraSonicWin.Helpers
{
    /// <summary>
    /// Manages global hotkeys for Windows using RegisterHotKey and a native message hook.
    /// </summary>
    public class HotkeyManager
    {
        [DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

        [DllImport("user32.dll")]
        private static extern IntPtr CallWindowProc(IntPtr lpPrevWndFunc, IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        private const int GWL_WNDPROC = -4;
        private const int WM_HOTKEY = 0x0312;
        private const int HOTKEY_ID = 9000;
        
        // Modifiers
        private const uint MOD_ALT = 0x0001;
        private const uint MOD_CONTROL = 0x0002;
        private const uint MOD_SHIFT = 0x0004;
        private const uint MOD_WIN = 0x0008;
        private const uint MOD_NOREPEAT = 0x4000;

        private IntPtr m_hWnd;
        private IntPtr m_oldWndProc;
        private WndProcDelegate m_newWndProc;

        private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        public event Action OnHotkeyPressed;

        public void Setup(Window window)
        {
            m_hWnd = WindowNative.GetWindowHandle(window);
            
            // Register hotkey: Alt Gr (Right Alt)
            // Alt Gr is logically Ctrl + Alt on Windows
            uint vk_alt_gr = 0x11; // VK_CONTROL (Wait, RegisterHotKey uses modifiers + VK)
            // Let's use Right Alt specifically
            const uint VK_RMENU = 0xA5; 
            RegisterHotKey(m_hWnd, HOTKEY_ID, MOD_NOREPEAT, VK_RMENU);

            // Hook into the window message loop
            m_newWndProc = new WndProcDelegate(WndProc);
            m_oldWndProc = SetWindowLongPtr(m_hWnd, GWL_WNDPROC, Marshal.GetFunctionPointerForDelegate(m_newWndProc));
        }

        public void Cleanup()
        {
            if (m_hWnd != IntPtr.Zero)
            {
                UnregisterHotKey(m_hWnd, HOTKEY_ID);
                SetWindowLongPtr(m_hWnd, GWL_WNDPROC, m_oldWndProc);
            }
        }

        private IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
        {
            if (msg == WM_HOTKEY && wParam.ToInt32() == HOTKEY_ID)
            {
                OnHotkeyPressed?.Invoke();
            }
            return CallWindowProc(m_oldWndProc, hWnd, msg, wParam, lParam);
        }
    }
}
