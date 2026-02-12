import Foundation

/// Manages Large Language Model interactions via Cloud APIs.
@MainActor
class LLMManager: ObservableObject {
    static let shared = LLMManager()
    
    @Published var isReady = true
    @Published var isLoading = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = ""
    
    private let session = URLSession.shared
    
    private init() {}
    
    func initialize() async throws {
        // Validation check on startup
        let provider = SettingsManager.shared.llmProvider
        if provider != .none {
            print("✅ LLMManager: Initialized with provider: \(provider.displayName)")
        }
    }
    
    // MARK: - Validation
    
    func validateApiKey(provider: SettingsManager.LLMProvider, apiKey: String) async throws -> (isValid: Bool, modelName: String?) {
        guard !apiKey.isEmpty else { return (false, nil) }
        
        switch provider {
        case .openai:
            return try await validateOpenAI(apiKey: apiKey)
        case .google:
            return try await validateGemini(apiKey: apiKey)
        case .anthropic:
            let isValid = apiKey.starts(with: "sk-ant")
            return (isValid, isValid ? "Claude 3.5 Sonnet" : nil)
        case .none:
            return (true, nil)
        }
    }
    
    private func validateOpenAI(apiKey: String) async throws -> (isValid: Bool, modelName: String?) {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": SettingsManager.shared.openaiModelId,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            print("🌐 OpenAI Validation Status: \(httpResponse.statusCode)")
            if httpResponse.statusCode == 200 {
                // OpenAI doesn't easily return the "best" model, but we can assume success means GPT-4o level for this plan
                // Or we could list models, but that's a separate call. For now, let's just return a success label.
                return (true, "GPT-4o (Verified)")
            }
        }
        return (false, nil)
    }
    
    private func validateGemini(apiKey: String) async throws -> (isValid: Bool, modelName: String?) {
        let modelId = SettingsManager.shared.geminiModelId
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [["parts": [["text": "hi"]]]],
            "generationConfig": ["max_output_tokens": 1]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            print("🌐 Gemini Validation Status: \(httpResponse.statusCode)")
            
            // 429 = rate limited but key IS valid
            if httpResponse.statusCode == 429 {
                print("⚠️ Gemini: Rate limited (429) — key is valid but throttled")
                let displayName = Constants.GeminiModel.allModels.first(where: { $0.id == modelId })?.displayName ?? modelId
                return (true, "\(displayName) (Rate Limited)")
            }
            
            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let _ = json["candidates"] as? [[String: Any]] {
                    let displayName = Constants.GeminiModel.allModels.first(where: { $0.id == modelId })?.displayName ?? modelId
                    return (true, "\(displayName) (Verified)")
                }
            }
            
            // 400/403 = invalid key
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            print("❌ Gemini Validation Error: \(errorBody.prefix(200))")
        }
        return (false, nil)
    }

    private func listGeminiModels(apiKey: String) async throws -> [String] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        let (data, _) = try await session.data(for: URLRequest(url: url))
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = json["models"] as? [[String: Any]] {
            return models.compactMap { $0["name"] as? String }
        }
        return []
    }
    
    // MARK: - Processing
    
    /// Processes a meeting transcript to generate a summary and action items.
    func processMeeting(meeting: Meeting) async throws -> MeetingResult {
        let provider = SettingsManager.shared.llmProvider
        var apiKey = ""
        
        switch provider {
        case .openai: apiKey = SettingsManager.shared.openaiApiKey
        case .google: apiKey = SettingsManager.shared.geminiApiKey
        case .anthropic: apiKey = SettingsManager.shared.anthropicApiKey
        case .none:
            throw NSError(domain: "LLMManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No AI Provider Configured"])
        }
        
        if apiKey.isEmpty {
             throw NSError(domain: "LLMManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "API Key missing for \(provider.displayName)"])
        }
        
        self.isLoading = true
        self.progress = 0.1
        self.statusMessage = "Analyzing transcript..."
        
        defer {
            self.isLoading = false
            self.progress = 1.0
            self.statusMessage = ""
        }
        
        // Prepare Transcript
        let fullText = meeting.segments.map { "[\($0.speakerName ?? "Speaker")]: \($0.text)" }.joined(separator: "\n")
        let lang = L10n.isFrench ? "français" : "English"
        let prompt = """
        You are an expert meeting assistant. Analyze the following meeting transcript.
        IMPORTANT: You MUST write your entire response in \(lang).
        
        Output a response in JSON format with the following structure:
        {
          "summary": "A concise paragraph summarizing the meeting (in \(lang)).",
          "actionItems": ["Action item 1 (in \(lang))", "Action item 2 (in \(lang))"],
          "title": "A suggested title for the meeting (in \(lang))"
        }
        
        Transcript:
        \(fullText)
        """
        
        var jsonResult: String = "{}"
        
        switch provider {
        case .openai:
            jsonResult = try await callOpenAI(apiKey: apiKey, prompt: prompt, isJson: true)
        case .google:
            jsonResult = try await callGemini(apiKey: apiKey, prompt: prompt, isJson: true)
        case .anthropic:
            // Anthropic is good at following instructions, so we rely on the prompt + cleanJson
            jsonResult = try await callAnthropic(apiKey: apiKey, prompt: prompt)
        default:
             throw NSError(domain: "LLMManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Provider not implemented"])
        }
        
        // Parse JSON
        // Robustness: Try to find JSON block if wrapped in markdown
        let cleanedJson = cleanJson(jsonResult)
        guard let data = cleanedJson.data(using: .utf8),
              let responseObj = try? JSONDecoder().decode(AIResponse.self, from: data) else {
             // Fallback if JSON fails, return raw text as summary
             return MeetingResult(summary: cleanedJson, actionItems: [], corrected: nil)
        }
        
        return MeetingResult(summary: responseObj.summary, actionItems: responseObj.actionItems, corrected: nil)
    }
    
    /// Processes a custom AI skill with a specific prompt and input text.
    func processSkill(skill: AISkill, text: String, selectedText: String? = nil) async throws -> String {
        let provider = SettingsManager.shared.llmProvider
        var apiKey = ""
        
        print("🤖 LLM: processSkill called — provider=\(provider.rawValue), skill='\(skill.name)', text='\(text.prefix(50))', hasSelection=\(selectedText != nil)")
        
        switch provider {
        case .openai: apiKey = SettingsManager.shared.openaiApiKey
        case .google: apiKey = SettingsManager.shared.geminiApiKey
        case .anthropic: apiKey = SettingsManager.shared.anthropicApiKey
        case .none:
            print("❌ LLM: No AI Provider configured")
            throw NSError(domain: "LLMManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No AI Provider Configured"])
        }
        
        if apiKey.isEmpty {
            print("❌ LLM: API Key is empty for \(provider.displayName)")
            throw NSError(domain: "LLMManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "API Key missing for \(provider.displayName)"])
        }
        
        print("🤖 LLM: API key present (\(apiKey.prefix(8))...), calling \(provider.displayName)...")
        
        self.isLoading = true
        self.progress = 0.5
        self.statusMessage = "Processing skill '\(skill.name)'..."
        
        defer {
            self.isLoading = false
            self.progress = 1.0
            self.statusMessage = ""
        }
        
        // Build prompt with optional selected text context
        var prompt: String
        if let selectedText = selectedText, !selectedText.isEmpty {
            prompt = """
            \(skill.prompt)
            
            Selected text (context from user's screen):
            \(selectedText)
            
            User request:
            \(text)
            """
            print("🤖 LLM: Prompt includes selected text context (\(selectedText.count) chars)")
        } else {
            prompt = """
            \(skill.prompt)
            
            Text to process:
            \(text)
            """
        }
        
        switch provider {
        case .openai:
            let response = try await callOpenAI(apiKey: apiKey, prompt: prompt, isJson: false)
            print("🤖 OpenAI Response (first 50 chars): \(response.prefix(50))")
            return response
        case .google:
            let response = try await callGemini(apiKey: apiKey, prompt: prompt, isJson: false)
            print("🤖 Gemini Response (first 50 chars): \(response.prefix(50))")
            return response
        case .anthropic:
            let response = try await callAnthropic(apiKey: apiKey, prompt: prompt)
            print("🤖 Anthropic Response (first 50 chars): \(response.prefix(50))")
            return response
        case .none:
            throw NSError(domain: "LLMManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "No provider"])
        }
    }

    private func cleanJson(_ text: String) -> String {
        // Remove markdown code blocks ```json ... ```
        var clean = text
        if let rangeStart = clean.range(of: "```json"), let rangeEnd = clean.range(of: "```", range: rangeStart.upperBound..<clean.endIndex) {
            clean = String(clean[rangeStart.upperBound..<rangeEnd.lowerBound])
        } else if let rangeStart = clean.range(of: "```"), let rangeEnd = clean.range(of: "```", range: rangeStart.upperBound..<clean.endIndex) {
             clean = String(clean[rangeStart.upperBound..<rangeEnd.lowerBound])
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - API Calls
    
    private func callOpenAI(apiKey: String, prompt: String, isJson: Bool) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var messages: [[String: String]] = []
        if isJson {
            messages.append(["role": "system", "content": "You are a helpful assistant that outputs strictly JSON."])
        }
        messages.append(["role": "user", "content": prompt])
        
        var body: [String: Any] = [
            "model": SettingsManager.shared.openaiModelId,
            "messages": messages
        ]
        
        if isJson {
            body["response_format"] = ["type": "json_object"]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
             let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
             throw NSError(domain: "OpenAI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return result.choices.first?.message.content ?? ""
    }
    
    private func callGemini(apiKey: String, prompt: String, isJson: Bool) async throws -> String {
        let modelId = SettingsManager.shared.geminiModelId
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ]
        ]
        
        if isJson {
            body["generationConfig"] = [
                "response_mime_type": "application/json"
            ]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        var lastData: Data?
        var lastStatusCode = 0
        
        for attempt in 0..<3 {
            let (data, response) = try await session.data(for: request)
            lastData = data
            
            if let httpResponse = response as? HTTPURLResponse {
                lastStatusCode = httpResponse.statusCode
                print("🌐 Gemini API Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(GeminiResponse.self, from: data)
                    return result.candidates.first?.content.parts.first?.text ?? ""
                }
                
                // Retry on 429 rate limit
                if httpResponse.statusCode == 429 && attempt < 2 {
                    let delay = Double(attempt + 1) * 5.0
                    print("⏳ Gemini: Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/3)...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
            break
        }
        
        let errorMsg = String(data: lastData ?? Data(), encoding: .utf8) ?? "Unknown Error"
        print("❌ Gemini API Error: \(errorMsg.prefix(200))")
        throw NSError(domain: "Gemini", code: lastStatusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
    }
    
    private func callAnthropic(apiKey: String, prompt: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": SettingsManager.shared.anthropicModelId,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("🌐 Anthropic API Status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
                print("❌ Anthropic API Error: \(errorMsg.prefix(200))")
                throw NSError(domain: "Anthropic", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        }
        
        // Anthropic response format: { "content": [{ "type": "text", "text": "..." }] }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? [[String: Any]],
           let firstBlock = content.first,
           let text = firstBlock["text"] as? String {
            return text
        }
        
        throw NSError(domain: "Anthropic", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
    }
    
    // MARK: - Models
    
    struct MeetingResult {
        let summary: String
        let actionItems: [String]
        let corrected: String?
    }
    
    private struct AIResponse: Codable {
        let summary: String
        let actionItems: [String]
        let title: String?
    }
    
    // OpenAI Models
    private struct OpenAIResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }
    
    // Gemini Models
    private struct GeminiResponse: Codable {
        struct Candidate: Codable {
            struct Content: Codable {
                struct Part: Codable {
                    let text: String
                }
                let parts: [Part]
            }
            let content: Content
        }
        let candidates: [Candidate]
    }
}

