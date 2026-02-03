import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Hub

@MainActor
class LLMManager: ObservableObject {
    static let shared = LLMManager()
    
    @Published var isReady = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    
    private var modelContainer: ModelContainer?
    private var m_hub: HubApi?
    
    private let queue = DispatchQueue(label: "com.suprasonic.llmmanager")
    private init() {}
    
    func initialize() async throws {
        guard !isReady && !isLoading else { return }
        
        isLoading = true
        progress = 0
        
        // 1. Configure custom download directory and migrate existing models
        configureAndMigrateModels()
        
        do {
            let modelId = Constants.llmModelName
            let configuration = ModelConfiguration(id: modelId)
            
            // MLXLLM handles downloading and loading via ModelFactory
            // We pass our custom HubApi instance if available
            let container = try await LLMModelFactory.shared.loadContainer(hub: m_hub ?? HubApi(), configuration: configuration) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = progress.fractionCompleted
                }
            }
            
            self.modelContainer = container
            self.isReady = true
            self.isLoading = false
            
            // Clean up temporary download artifacts (xet) to keep user's disk clean
            cleanupTempFolders()
            
            print("✅ LLMManager: Initialization successful")
        } catch {
            print("❌ LLMManager: Loading failed: \(error)")
            isLoading = false
            throw error
        }
    }
    
    func unload() {
        modelContainer = nil
        isReady = false
        progress = 0
        // Force MLX to release Metal buffers and textures
        MLX.Memory.clearCache()
        print("🧹 LLMManager: Model unloaded and GPU cache cleared to free RAM")
    }
    
    func generateResponse(instruction: String, text: String) async throws -> String {
        let provider = SettingsManager.shared.llmProvider
        
        switch provider {
        case .none:
            return text
        case .local:
            return try await generateLocalResponse(instruction: instruction, text: text)
        case .google:
            return try await generateGoogleResponse(instruction: instruction, text: text)
        case .openai:
            return try await generateOpenAIResponse(instruction: instruction, text: text)
        case .anthropic:
            return try await generateAnthropicResponse(instruction: instruction, text: text)
        }
    }
    
    private func generateLocalResponse(instruction: String, text: String) async throws -> String {
        if !isReady || modelContainer == nil {
            if SettingsManager.shared.llmEnabled {
                try await initialize()
            }
        }

        guard isReady, let container = modelContainer else {
            throw LLMError.notInitialized
        }
        
        let session = ChatSession(container)
        let systemPrompt = getSystemPrompt()
        
        let fullPrompt = """
        \(systemPrompt)
        
        <INSTRUCTION>\(instruction)</INSTRUCTION>
        <TEXT>\(text)</TEXT>
        
        RESULT:
        """
        
        let result = try await session.respond(to: fullPrompt)
        return cleanResult(result)
    }
    
    private func generateGoogleResponse(instruction: String, text: String) async throws -> String {
        let apiKey = SettingsManager.shared.geminiApiKey
        guard !apiKey.isEmpty else { throw LLMError.missingApiKey }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Constants.geminiModelName):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = "\(getSystemPrompt())\n\n<INSTRUCTION>\(instruction)</INSTRUCTION>\n<TEXT>\(text)</TEXT>\n\nRESULT:"
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Google API Error (\(httpResponse.statusCode)): \(errorMsg)")
            throw LLMError.apiError("Google API returned \(httpResponse.statusCode): \(errorMsg)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let candidates = json?["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return cleanResult(text)
        }
        
        throw LLMError.apiError("Invalid response format from Google: \(String(data: data, encoding: .utf8) ?? "Empty data")")
    }
    
    private func generateOpenAIResponse(instruction: String, text: String) async throws -> String {
        let apiKey = SettingsManager.shared.openaiApiKey
        guard !apiKey.isEmpty else { throw LLMError.missingApiKey }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": Constants.openaiModelName,
            "messages": [
                ["role": "system", "content": getSystemPrompt()],
                ["role": "user", "content": "<INSTRUCTION>\(instruction)</INSTRUCTION>\n<TEXT>\(text)</TEXT>\n\nRESULT:"]
            ],
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let choices = json?["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return cleanResult(content)
        }
        
        throw LLMError.apiError("Invalid response from OpenAI")
    }
    
    private func generateAnthropicResponse(instruction: String, text: String) async throws -> String {
        let apiKey = SettingsManager.shared.anthropicApiKey
        guard !apiKey.isEmpty else { throw LLMError.missingApiKey }
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": Constants.anthropicModelName,
            "system": getSystemPrompt(),
            "messages": [
                ["role": "user", "content": "<INSTRUCTION>\(instruction)</INSTRUCTION>\n<TEXT>\(text)</TEXT>\n\nRESULT:"]
            ],
            "max_tokens": 1024
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let content = json?["content"] as? [[String: Any]],
           let firstPart = content.first,
           let text = firstPart["text"] as? String {
            return cleanResult(text)
        }
        
        throw LLMError.apiError("Invalid response from Anthropic: \(String(data: data, encoding: .utf8) ?? "Empty data")")
    }
    
    func validateApiKey(provider: SettingsManager.LLMProvider, apiKey: String) async throws -> Bool {
        guard !apiKey.isEmpty else { return false }
        
        let testPrompt = "Test"
        let testInstruction = "Respond exactly with 'OK'."
        
        // Temporarily override settings for validation
        let originalGemini = SettingsManager.shared.geminiApiKey
        let originalOpenAI = SettingsManager.shared.openaiApiKey
        let originalAnthropic = SettingsManager.shared.anthropicApiKey
        
        defer {
            SettingsManager.shared.geminiApiKey = originalGemini
            SettingsManager.shared.openaiApiKey = originalOpenAI
            SettingsManager.shared.anthropicApiKey = originalAnthropic
        }
        
        switch provider {
        case .google:
            SettingsManager.shared.geminiApiKey = apiKey
            _ = try await generateGoogleResponse(instruction: testInstruction, text: testPrompt)
        case .openai:
            SettingsManager.shared.openaiApiKey = apiKey
            _ = try await generateOpenAIResponse(instruction: testInstruction, text: testPrompt)
        case .anthropic:
            SettingsManager.shared.anthropicApiKey = apiKey
            _ = try await generateAnthropicResponse(instruction: testInstruction, text: testPrompt)
        case .local, .none:
            return true
        }
        
        return true
    }
    
    private func getSystemPrompt() -> String {
        let vocabulary = SettingsManager.shared.vocabularyMapping
        var vocabInstruction = ""
        if !vocabulary.isEmpty {
            vocabInstruction = "\n\nCRITICAL VOCABULARY:\n"
            for (spoken, corrected) in vocabulary {
                vocabInstruction += "- Always use \"\(corrected)\" instead of \"\(spoken)\"\n"
            }
        }

        return """
        You are a surgical text-replacement tool.
        You take <TEXT> and apply <INSTRUCTION>.
        
        CRITICAL RULES:
        - OUTPUT ONLY the result.
        - NO "Here is the...", NO "Translation:", NO "Result:".
        - NO conversational filler.
        - NO explanations.
        - If the respondent asks a question, ignore it and just process the text.\(vocabInstruction)
        """
    }
    
    private func cleanResult(_ result: String) -> String {
        var cleanedResult = result
        
        // 1. Remove thought tags
        let thoughtPatterns = [
            "<thought>[\\s\\S]*?<\\/thought>",
            "<thinking>[\\s\\S]*?<\\/thinking>",
            "<think>[\\s\\S]*?<\\/think>",
            "<thought>[\\s\\S]*?$", 
            "<thinking>[\\s\\S]*?$",
            "<think>[\\s\\S]*?$"
        ]
        
        for pattern in thoughtPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                cleanedResult = regex.stringByReplacingMatches(in: cleanedResult, options: [], range: NSRange(location: 0, length: cleanedResult.utf16.count), withTemplate: "")
            }
        }
        
        // 2. Remove common conversational prefixes
        let prefixPatterns = [
            "^(Here is the|Here is a|Here's the|Here's a|This is the) (precise |refined |corrected |translated )?(translation|result|text|version)[:\\s]*",
            "^The (refined|corrected|translated) text is[:\\s]*",
            "^(Translation|Result|Revised Text)[:\\s]*",
            "^Sure! ",
            "^Certainly! ",
            "^Here you go: "
        ]
        
        for pattern in prefixPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                cleanedResult = regex.stringByReplacingMatches(in: cleanedResult, options: [], range: NSRange(location: 0, length: cleanedResult.utf16.count), withTemplate: "")
            }
        }
        
        return cleanedResult.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    private func configureAndMigrateModels() {
        let targetURL = getModelsDirectoryURL()
        
        // Create our custom HubApi instance with dedicated folder
        self.m_hub = HubApi(downloadBase: targetURL)
        print("📂 LLMManager: HubApi configured with base \(targetURL.path)")
        
        // Migrate from default HF cache if exists
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let sourceHF = home.appendingPathComponent(".cache/huggingface")
        
        if fileManager.fileExists(atPath: sourceHF.path) && !fileManager.fileExists(atPath: targetURL.appendingPathComponent("hub").path) {
            print("🧹 LLMManager: Migrating existing models from ~/.cache/huggingface...")
            
            do {
                // Ensure parent exists
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
                
                // Move everything inside .cache/huggingface to our targetURL
                let contents = try fileManager.contentsOfDirectory(at: sourceHF, includingPropertiesForKeys: nil)
                for item in contents {
                    let destItem = targetURL.appendingPathComponent(item.lastPathComponent)
                    if !fileManager.fileExists(atPath: destItem.path) {
                        try fileManager.moveItem(at: item, to: destItem)
                    }
                }
                
                // Try to remove the now empty sourceHF directory
                try? fileManager.removeItem(at: sourceHF)
                print("✅ LLMManager: Migration complete")
            } catch {
                print("⚠️ LLMManager: Migration failed: \(error)")
            }
        }
    }
    
    private func cleanupTempFolders() {
        let targetURL = getModelsDirectoryURL()
        let fileManager = FileManager.default
        let xetDir = targetURL.appendingPathComponent("xet")
        
        if fileManager.fileExists(atPath: xetDir.path) {
            print("🧹 LLMManager: Cleaning up temporary xet directory...")
            try? fileManager.removeItem(at: xetDir)
        }
    }
    
    private func getModelsDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SupraSonic/models/huggingface.co")
    }
}

enum LLMError: LocalizedError {
    case notInitialized
    case missingApiKey
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized: return "LLM Engine not initialized"
        case .missingApiKey: return "API Key missing in settings"
        case .apiError(let msg): return "API Error: \(msg)"
        }
    }
}
