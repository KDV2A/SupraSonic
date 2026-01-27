using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using Windows.Storage;

namespace SupraSonicWin.Models
{
    public class HistoryEntry
    {
        public string Text { get; set; }
        public DateTime Timestamp { get; set; }
    }

    public class HistoryManager
    {
        public static HistoryManager Shared { get; } = new HistoryManager();

        private List<HistoryEntry> m_entries = new List<HistoryEntry>();
        private readonly string m_filePath;

        private HistoryManager()
        {
            m_filePath = Path.Combine(ApplicationData.Current.LocalFolder.Path, "history.json");
            _ = LoadAsync();
        }

        public IReadOnlyList<HistoryEntry> Entries => m_entries;

        public async Task AddEntryAsync(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return;

            m_entries.Insert(0, new HistoryEntry 
            { 
                Text = text, 
                Timestamp = DateTime.Now 
            });

            // Limit history to 100 entries
            if (m_entries.Count > 100) m_entries.RemoveAt(100);

            await SaveAsync();
        }

        private async Task LoadAsync()
        {
            try
            {
                if (File.Exists(m_filePath))
                {
                    string json = await File.ReadAllTextAsync(m_filePath);
                    m_entries = JsonSerializer.Deserialize<List<HistoryEntry>>(json) ?? new List<HistoryEntry>();
                }
            }
            catch { m_entries = new List<HistoryEntry>(); }
        }

        private async Task SaveAsync()
        {
            try
            {
                string json = JsonSerializer.Serialize(m_entries);
                await File.WriteAllTextAsync(m_filePath, json);
            }
            catch { }
        }
    }
}
