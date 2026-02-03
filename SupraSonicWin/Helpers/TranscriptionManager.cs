using System;
using System.Threading.Tasks;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using System.Collections.Generic;
using System.Linq;
using System.Diagnostics;

namespace SupraSonicWin.Helpers
{
    public class TranscriptionManager
    {
        private InferenceSession m_session;
        private bool m_isReady = false;
        private double m_progress = 0;
        private string m_statusMessage = "";

        public bool IsReady => m_isReady;
        public double Progress => m_progress;
        public string StatusMessage => m_statusMessage;

        public async Task InitializeAsync()
        {
            if (m_isReady) return;

            try
            {
                m_statusMessage = L10n.IsFrench ? "Chargement du modèle..." : "Loading model...";
                m_progress = 0.1;

                // Path to our ONNX model (DirectML version)
                string modelPath = SettingsManager.Shared.LocalASRModelPath;
                
                // Configure DirectML for GPU acceleration
                var options = new SessionOptions();
                options.GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL;
                
                try {
                    m_statusMessage = L10n.IsFrench ? "Optimisation GPU (DirectML)..." : "Optimizing for GPU (DirectML)...";
                    m_progress = 0.3;
                    options.AppendExecutionProvider_DML(0); // Use GPU 0
                } catch {
                    Debug.WriteLine("⚠️ DirectML not available, falling back to CPU");
                }

                m_session = new InferenceSession(modelPath, options);
                m_isReady = true;
                m_progress = 1.0;
                m_statusMessage = L10n.IsFrench ? "Prêt" : "Ready";
                Debug.WriteLine("✅ Parakeet TDT v3 Initialized via ONNX/DirectML");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ Transcription Initialization Failed: {ex.Message}");
                throw;
            }
        }

        public async Task<string> TranscribeAsync(float[] audioSamples)
        {
            if (!m_isReady) throw new Exception("Transcription engine not starting");

            return await Task.Run(() =>
            {
                // Parakeet TDT inference logic
                // 1. Preprocess (Mel Spectrogram) - This normally happens in Rust core 
                //    but we might need to verify if Rust core sends raw audio or features.
                //    Plan says Rust sends processed audio buffer (16kHz).
                
                // 2. Wrap as Tensor
                var inputTensor = new DenseTensor<float>(audioSamples, new int[] { 1, audioSamples.Length });
                
                var inputs = new List<NamedOnnxValue>
                {
                    NamedOnnxValue.CreateFromTensor("audio_signal", inputTensor)
                };

                // 3. Run Inference
                using (var results = m_session.Run(inputs))
                {
                    // This is a simplified placeholder for the full TDT decoding loop
                    // In a production app, we'd iterate and decode the transducer output
                    var output = results.First().AsEnumerable<string>().FirstOrDefault();
                    return ApplyVocabularyMapping(output ?? "");
                }
            });
        }

        private string ApplyVocabularyMapping(string text)
        {
            try
            {
                var mapping = SettingsManager.Shared.VocabularyMapping;
                if (mapping == null || mapping.Count == 0) return text;

                string correctedText = text;
                // Sort by length descending to avoid partial replacements
                var sortedKeys = mapping.Keys.OrderByDescending(k => k.Length);

                foreach (var spoken in sortedKeys)
                {
                    string corrected = mapping[spoken];
                    // Case-insensitive whole word replacement
                    string pattern = @"\b" + System.Text.RegularExpressions.Regex.Escape(spoken) + @"\b";
                    correctedText = System.Text.RegularExpressions.Regex.Replace(
                        correctedText, pattern, corrected, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                }

                return correctedText;
            }
            catch
            {
                return text;
            }
        }

    }
}
