using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Microsoft.UI;
using System.Collections.Generic;
using Windows.UI;

namespace SupraSonicWin
{
    public sealed partial class OverlayWindow : Window
    {
        private List<Rectangle> m_bars = new List<Rectangle>();
        private const int BAR_COUNT = 30;

        public OverlayWindow()
        {
            this.InitializeComponent();
            StatusLabel.Text = L10n.Recording;
            
            // Customize window appearance (Borderless, Topmost)
            var presenter = (Microsoft.UI.Windowing.OverlappedPresenter)this.AppWindow.Presenter;
            presenter.IsAlwaysOnTop = true;
            presenter.IsResizable = false;
            presenter.SetBorderAndTitleBar(false, false);
            
            // Center at the top of the monitor
            IntPtr hWnd = Microsoft.UI.Interop.WindowNative.GetWindowHandle(this);
            Microsoft.UI.WindowId windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hWnd);
            var appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(windowId);
            
            var displayArea = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(windowId, Microsoft.UI.Windowing.DisplayAreaFallback.Primary);
            int centerX = (displayArea.WorkArea.Width - (int)appWindow.Size.Width) / 2;
            appWindow.Move(new Windows.Graphics.PointInt32(centerX, 20));

            SetupWaveform();
        }

        private void SetupWaveform()
        {
            for (int i = 0; i < BAR_COUNT; i++)
            {
                var rect = new Rectangle
                {
                    Width = 4,
                    Height = 4,
                    Fill = new SolidColorBrush(Color.FromArgb(255, 0, 229, 255)),
                    RadiusX = 2,
                    RadiusY = 2,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(1, 0, 1, 0)
                };
                m_bars.Add(rect);
                WaveformControl.Items.Add(rect);
            }
        }

        private Random m_rand = new Random();

        public void SetAIMode(bool enabled)
        {
            StatusLabel.Text = enabled ? (L10n.IsFrench ? "Assistant IA" : "AI Assistant") : L10n.Recording;
        }

        public void UpdateLevel(float level)
        {
            // Dynamic organic animation matching macOS feel
            for (int i = 0; i < BAR_COUNT; i++)
            {
                // Smooth sine wave + noise based on audio level
                float noise = (float)(m_rand.NextDouble() * 10 * level);
                float sine = (float)Math.Sin(i * 0.3 + Environment.TickCount * 0.01) * 20 * level;
                float height = 4 + Math.Abs(sine) + noise;
                
                m_bars[i].Height = Math.Clamp(height, 4, 45);
            }
        }
    }
}
