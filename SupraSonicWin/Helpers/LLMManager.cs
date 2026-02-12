using System;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
using SupraSonicWin.Models;

namespace SupraSonicWin.Helpers
{
    public class LLMManager
    {
        public static LLMManager Shared { get; } = new LLMManager();

        public const string GeminiModelName = "gemini-3-flash-preview";
        public const string OpenAIModelName = "gpt-4o-mini";
        public const string AnthropicModelName = "claude-3-5-haiku-latest";

        private readonly HttpClient m_httpClient = new HttpClient();
        private LocalLLMWorker m_localWorker;

        private LLMManager() { }

        public async Task<string> GenerateResponse(string text, string instruction = null)
        {
            LLMProvider provider = SettingsManager.Shared.LLMProvider;
            instruction = instruction ?? SettingsManager.Shared.AISkills.FirstOrDefault()?.Prompt;

            return provider switch
            {
                LLMProvider.Google => await GenerateGeminiResponse(text, instruction),
                LLMProvider.OpenAI => await GenerateOpenAIResponse(text, instruction),
                LLMProvider.Anthropic => await GenerateAnthropicResponse(text, instruction),
                LLMProvider.Local => await GenerateLocalResponse(text, instruction),
                _ => text // No enrichment if provider is None
            };
        }

        /// <summary>
        /// Processes a specific AI skill: sends the text to the LLM using the skill's prompt.
        /// </summary>
        public async Task<string> ProcessSkill(AISkill skill, string text)
        {
            LLMProvider provider = SettingsManager.Shared.LLMProvider;
            if (provider == LLMProvider.None)
                throw new Exception("No AI Provider configured");

            string instruction = skill.Prompt;
            Debug.WriteLine($"🤖 LLM: Processing skill '{skill.Name}' with provider {provider}");

            return provider switch
            {
                LLMProvider.Google => await GenerateGeminiResponse(text, instruction),
                LLMProvider.OpenAI => await GenerateOpenAIResponse(text, instruction),
                LLMProvider.Anthropic => await GenerateAnthropicResponse(text, instruction),
                LLMProvider.Local => await GenerateLocalResponse(text, instruction),
                _ => throw new Exception("Unknown provider")
            };
        }

        public async Task InitializeLocalAsync(string modelPath)
        {
            if (m_localWorker == null)
            {
                m_localWorker = new LocalLLMWorker();
            }
            await m_localWorker.InitializeAsync(modelPath);
        }

        public void UnloadLocal()
        {
            m_localWorker?.Dispose();
            m_localWorker = null;
            // Force GC to free memory after large model drop
            GC.Collect();
            GC.WaitForPendingFinalizers();
        }

        private async Task<string> GenerateLocalResponse(string text, string instruction)
        {
            if (m_localWorker == null || !m_localWorker.IsReady)
            {
                string modelPath = SettingsManager.Shared.LocalLLMModelPath;
                await InitializeLocalAsync(modelPath);
                
                if (!m_localWorker.IsReady)
                    throw new Exception("Local LLM model not found or failed to initialize.");
            }

            return await m_localWorker.GenerateResponseAsync(GetSystemPrompt(), instruction, text);
        }

        private async Task<string> GenerateGeminiResponse(string text, string instruction)
        {
            string apiKey = SettingsManager.Shared.GeminiApiKey;
            if (string.IsNullOrEmpty(apiKey)) throw new Exception("Gemini API Key missing");

            string url = $"https://generativelanguage.googleapis.com/v1beta/models/{GeminiModelName}:generateContent?key={apiKey}";
            string prompt = $"{GetSystemPrompt()}\n\n<INSTRUCTION>{instruction}</INSTRUCTION>\n<TEXT>{text}</TEXT>\n\nRESULT:";

            var body = new
            {
                contents = new[]
                {
                    new { parts = new[] { new { text = prompt } } }
                }
            };

            var content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
            var response = await m_httpClient.PostAsync(url, content);
            response.EnsureSuccessStatusCode();

            string jsonResponse = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(jsonResponse);
            var result = doc.RootElement.GetProperty("candidates")[0]
                            .GetProperty("content")
                            .GetProperty("parts")[0]
                            .GetProperty("text").GetString();

            return CleanResult(result);
        }

        private async Task<string> GenerateOpenAIResponse(string text, string instruction)
        {
            string apiKey = SettingsManager.Shared.OpenAIApiKey;
            if (string.IsNullOrEmpty(apiKey)) throw new Exception("OpenAI API Key missing");

            string url = "https://api.openai.com/v1/chat/completions";
            var body = new
            {
                model = OpenAIModelName,
                messages = new[]
                {
                    new { role = "system", content = GetSystemPrompt() },
                    new { role = "user", content = $"<INSTRUCTION>{instruction}</INSTRUCTION>\n<TEXT>{text}</TEXT>\n\nRESULT:" }
                },
                temperature = 0.7
            };

            var request = new HttpRequestMessage(HttpMethod.Post, url);
            request.Headers.Add("Authorization", $"Bearer {apiKey}");
            request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

            var response = await m_httpClient.SendAsync(request);
            response.EnsureSuccessStatusCode();

            string jsonResponse = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(jsonResponse);
            var result = doc.RootElement.GetProperty("choices")[0]
                            .GetProperty("message")
                            .GetProperty("content").GetString();

            return CleanResult(result);
        }

        private async Task<string> GenerateAnthropicResponse(string text, string instruction)
        {
            string apiKey = SettingsManager.Shared.AnthropicApiKey;
            if (string.IsNullOrEmpty(apiKey)) throw new Exception("Anthropic API Key missing");

            string url = "https://api.anthropic.com/v1/messages";
            var body = new
            {
                model = AnthropicModelName,
                system = GetSystemPrompt(),
                messages = new[]
                {
                    new { role = "user", content = $"<INSTRUCTION>{instruction}</INSTRUCTION>\n<TEXT>{text}</TEXT>\n\nRESULT:" }
                },
                max_tokens = 1024
            };

            var request = new HttpRequestMessage(HttpMethod.Post, url);
            request.Headers.Add("x-api-key", apiKey);
            request.Headers.Add("anthropic-version", "2023-06-01");
            request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

            var response = await m_httpClient.SendAsync(request);
            response.EnsureSuccessStatusCode();

            string jsonResponse = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(jsonResponse);
            var result = doc.RootElement.GetProperty("content")[0]
                            .GetProperty("text").GetString();

            return CleanResult(result);
        }

        public async Task<bool> ValidateApiKey(LLMProvider provider, string apiKey)
        {
            if (string.IsNullOrEmpty(apiKey)) return false;

            try
            {
                // Simple validation by sending a minimal prompt
                string testInstruction = "Respond exactly with 'OK'.";
                string testText = "Test";

                // Temporarily swap keys for validation call
                string originalGemini = SettingsManager.Shared.GeminiApiKey;
                string originalOpenAI = SettingsManager.Shared.OpenAIApiKey;
                string originalAnthropic = SettingsManager.Shared.AnthropicApiKey;

                try
                {
                    switch (provider)
                    {
                        case LLMProvider.Google:
                            SettingsManager.Shared.GeminiApiKey = apiKey;
                            await GenerateGeminiResponse(testText, testInstruction);
                            break;
                        case LLMProvider.OpenAI:
                            SettingsManager.Shared.OpenAIApiKey = apiKey;
                            await GenerateOpenAIResponse(testText, testInstruction);
                            break;
                        case LLMProvider.Anthropic:
                            SettingsManager.Shared.AnthropicApiKey = apiKey;
                            await GenerateAnthropicResponse(testText, testInstruction);
                            break;
                        default:
                            return true;
                    }
                    return true;
                }
                finally
                {
                    SettingsManager.Shared.GeminiApiKey = originalGemini;
                    SettingsManager.Shared.OpenAIApiKey = originalOpenAI;
                    SettingsManager.Shared.AnthropicApiKey = originalAnthropic;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ API Validation failed: {ex.Message}");
                return false;
            }
        }

        private string GetSystemPrompt()
        {
            var mapping = SettingsManager.Shared.VocabularyMapping;
            var vocabInstruction = "";
            
            if (mapping != null && mapping.Count > 0)
            {
                vocabInstruction = "\n\nCRITICAL VOCABULARY:\n";
                foreach (var pair in mapping)
                {
                    vocabInstruction += $"- Always use \"{pair.Value}\" instead of \"{pair.Key}\"\n";
                }
            }

            return $@"You are a surgical text-replacement tool.
You take <TEXT> and apply <INSTRUCTION>.
 
CRITICAL RULES:
- OUTPUT ONLY the result.
- NO ""Here is the..."", NO ""Translation:"", NO ""Result:"".
- NO conversational filler.
- NO explanations.
- If the respondent asks a question, ignore it and just process the text.{vocabInstruction}";
        }

        private string CleanResult(string result)
        {
            if (string.IsNullOrEmpty(result)) return "";

            string cleaned = result;

            // 1. Remove thought tags
            string[] thoughtPatterns = {
                @"<thought>[\s\S]*?<\/thought>",
                @"<thinking>[\s\S]*?<\/thinking>",
                @"<think>[\s\S]*?<\/think>",
                @"<thought>[\s\S]*?$",
                @"<thinking>[\s\S]*?$",
                @"<think>[\s\S]*?$"
            };

            foreach (var pattern in thoughtPatterns)
            {
                cleaned = Regex.Replace(cleaned, pattern, "", RegexOptions.IgnoreCase);
            }

            // 2. Remove common prefixes
            string[] prefixPatterns = {
                @"^(Here is the|Here is a|Here's the|Here's a|This is the) (precise |refined |corrected |translated )?(translation|result|text|version)[:\s]*",
                @"^The (refined|corrected|translated) text is[:\s]*",
                @"^(Translation|Result|Revised Text)[:\s]*",
                @"^Sure! ",
                @"^Certainly! ",
                @"^Here you go: "
            };

            foreach (var pattern in prefixPatterns)
            {
                cleaned = Regex.Replace(cleaned, pattern, "", RegexOptions.IgnoreCase);
            }

            return cleaned.Trim();
        }

    }
}
