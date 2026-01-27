import Foundation
import MLX
import MLXLLM
import MLXLMCommon

@MainActor
class LLMManager: ObservableObject {
    static let shared = LLMManager()
    
    @Published var isLoading = false
    @Published var isReady = false
    @Published var progress: Double = 0
    
    private var modelContainer: ModelContainer?
    
    private init() {}
    
    func initialize() async throws {
        guard !isReady && !isLoading else { return }
        
        isLoading = true
        progress = 0
        
        do {
            let modelId = Constants.llmModelName
            let configuration = ModelConfiguration(id: modelId)
            
            // MLXLLM handles downloading and loading via ModelFactory
            let container = try await LLMModelFactory.shared.loadContainer(configuration: configuration) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = progress.fractionCompleted
                }
            }
            
            self.modelContainer = container
            self.isReady = true
            self.isLoading = false
            print("✅ LLMManager: Model loaded successfully")
        } catch {
            print("❌ LLMManager: Loading failed: \(error)")
            isLoading = false
            throw error
        }
    }
    
    func generateResponse(prompt: String) async throws -> String {
        guard isReady, let container = modelContainer else {
            throw LLMError.notInitialized
        }
        
        // Using ChatSession for higher level interaction
        let session = ChatSession(container)
        
        // System prompt for refinement
        let systemPrompt = "You are a helpful assistant. The following text is a transcription of a user's voice. Please clean it up, fix any obvious grammar or spelling errors, and expand on it naturally. Output ONLY the refined text."
        
        // In the latest MLXLLM, we can set a system prompt in the session or include it in the messages
        // Here we'll just use a simple respond call which handles the chat template
        let fullPrompt = "\(systemPrompt)\n\nUser text: \(prompt)"
        
        let result = try await session.respond(to: fullPrompt)
        return result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

enum LLMError: LocalizedError {
    case notInitialized
    
    var errorDescription: String? {
        switch self {
        case .notInitialized: return "LLM Engine not initialized"
        }
    }
}
