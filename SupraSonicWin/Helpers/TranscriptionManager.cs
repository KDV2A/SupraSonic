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

        public bool IsReady => m_isReady;

        public async Task InitializeAsync()
        {
            if (m_isReady) return;

            try
            {
                // Path to our ONNX model (DirectML version)
                string modelPath = "Assets/Models/parakeet-tdt-0.6b-v3-onnx.onnx";
                
                // Configure DirectML for GPU acceleration
                var options = new SessionOptions();
                options.GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL;
                
                try {
                    options.AppendExecutionProvider_DML(0); // Use GPU 0
                } catch {
                    Debug.WriteLine("⚠️ DirectML not available, falling back to CPU");
                }

                m_session = new InferenceSession(modelPath, options);
                m_isReady = true;
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
                    return output ?? "";
                }
            });
        }
    }
}
