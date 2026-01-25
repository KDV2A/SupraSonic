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
            
            // Customize window appearance (Borderless, Topmost)
            var presenter = (Microsoft.UI.Windowing.OverlappedPresenter)this.AppWindow.Presenter;
            presenter.IsAlwaysOnTop = true;
            presenter.IsResizable = false;
            presenter.SetBorderAndTitleBar(false, false);
            
            // Set transparent background logic for WinUI 3 (simplified)
            // Note: Full transparency in WinUI 3 usually requires mica/acrylic or Composition APIs

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
                    VerticalAlignment = VerticalAlignment.Center
                };
                m_bars.Add(rect);
                WaveformControl.Items.Add(rect);
            }
        }

        public void UpdateLevel(float level)
        {
            // Update bar heights based on level (simplified)
            for (int i = 0; i < BAR_COUNT; i++)
            {
                float factor = (float)System.Math.Sin(i * 0.2 + level) * level;
                m_bars[i].Height = 4 + (factor * 30);
            }
        }
    }
}
