import Foundation
import SwiftLlama
import Observation

@MainActor
@Observable
final class LLMManager {
    private(set) var activeModelURL: URL?
    private(set) var isGenerating = false
    private(set) var generatedText = ""
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?

    private let engine = LLMEngine(configuration: .init(contextSize: 2048, batchSize: 256, useGPU: true))

    func loadModel(at url: URL) async {
        errorMessage = nil
        statusMessage = "Model laden…"
        do {
            try await engine.loadModel(at: url)
            activeModelURL = url
            statusMessage = "Model geladen: \(url.lastPathComponent)"
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    func generate(messages: [LlamaChatMessage]) async throws -> String {
        guard !isGenerating else { throw LLMManagerError.generationInProgress }
        isGenerating = true
        generatedText = ""
        errorMessage = nil
        defer { isGenerating = false }

        let stream = try await engine.stream(messages: messages)
        for try await fragment in stream {
            try Task.checkCancellation()
            generatedText += fragment
        }
        return generatedText
    }

    func stopGeneration() async {
        await engine.stopGeneration()
        isGenerating = false
    }

    func unloadModel() async {
        await engine.unloadModel()
        activeModelURL = nil
        statusMessage = "Model vrijgegeven"
    }
}

enum LLMManagerError: LocalizedError {
    case generationInProgress

    var errorDescription: String? {
        "Er wordt al een antwoord gegenereerd."
    }
}
