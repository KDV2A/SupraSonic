using Microsoft.UI.Xaml.Controls;
using System.Collections.Generic;
using SupraSonicWin.Models;

namespace SupraSonicWin.Pages
{
    public sealed partial class HistoryPage : Page
    {
        public IReadOnlyList<HistoryEntry> Entries => HistoryManager.Shared.Entries;

        public HistoryPage()
        {
            this.InitializeComponent();
        }
    }
}
