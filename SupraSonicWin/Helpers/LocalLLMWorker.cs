using LLama;
using LLama.Common;
using LLama.Sampling;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SupraSonicWin.Helpers
{
    public class LocalLLMWorker : IDisposable
    {
        private LLamaWeights m_weights;
        private LLamaContext m_context;
        private InteractiveExecutor m_executor;
        private bool m_isReady = false;

        public bool IsReady => m_isReady;

        public async Task<bool> InitializeAsync(string modelPath)
        {
            if (m_isReady) return true;
            if (!File.Exists(modelPath))
            {
                Debug.WriteLine($"❌ LocalLLM: Model file not found at {modelPath}");
                return false;
            }

            try
            {
                await Task.Run(() =>
                {
                    var parameters = new ModelParams(modelPath)
                    {
                        ContextSize = 1024,
                        GpuLayerCount = 32, // Most 3B models fit in VRAM with 32 layers
                        MainGpu = 0
                    };

                    m_weights = LLamaWeights.LoadFromFile(parameters);
                    m_context = m_weights.CreateContext(parameters);
                    m_executor = new InteractiveExecutor(m_context);
                    m_isReady = true;
                    Debug.WriteLine("✅ LocalLLM: Model loaded with DirectML acceleration");
                });
                return true;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ LocalLLM Initialization Error: {ex.Message}");
                return false;
            }
        }

        public async Task<string> GenerateResponseAsync(string systemPrompt, string instruction, string text)
        {
            if (!m_isReady) return "Local LLM Error: Engine not ready";

            try
            {
                // Ministral / Mistral Instruct format
                string fullPrompt = $"[INST] {systemPrompt}\n\n<INSTRUCTION>{instruction}</INSTRUCTION>\n<TEXT>{text}</TEXT> [/INST] RESULT:";

                StringBuilder sb = new StringBuilder();
                var inferenceParams = new InferenceParams()
                {
                    MaxTokens = 512,
                    AntiPrompts = new List<string> { "</s>", "[/INST]" },
                    SamplingPipeline = new DefaultSamplingPipeline()
                    {
                        Temperature = 0.7f,
                    }
                };

                await foreach (var token in m_executor.InferAsync(fullPrompt, inferenceParams))
                {
                    sb.Append(token);
                    // Optimization: stop if we see common stop tokens not caught by anti-prompts
                    if (sb.ToString().Contains("</s>")) break;
                }

                return sb.ToString().Replace("</s>", "").Trim();
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"❌ LocalLLM Inference Error: {ex.Message}");
                return $"Error: {ex.Message}";
            }
        }

        public void Dispose()
        {
            m_context?.Dispose();
            m_weights?.Dispose();
            m_isReady = false;
        }
    }
}
