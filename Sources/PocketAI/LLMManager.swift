import Foundation
import SwiftLlama
import Observation

struct GenerationStats: Sendable {
    var timeToFirstToken: TimeInterval
    var estimatedTokensPerSecond: Double
    var outputCharacters: Int
}

@MainActor
@Observable
final class LLMManager {
    private(set) var activeModelURL: URL?
    private(set) var isGenerating = false
    private(set) var generatedText = ""
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private(set) var lastGenerationStats: GenerationStats?

    private var contextSize: UInt32
    private var useGPU: Bool
    private var engine: LLMEngine

    init(contextSize: UInt32 = 2048, useGPU: Bool = true) {
        self.contextSize = contextSize
        self.useGPU = useGPU
        self.engine = LLMEngine(configuration: .init(contextSize: contextSize, batchSize: 256, useGPU: useGPU))
    }

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

    func configure(contextSize newContextSize: UInt32, useGPU newUseGPU: Bool) async {
        guard contextSize != newContextSize || useGPU != newUseGPU else { return }
        let modelURL = activeModelURL
        statusMessage = "Instellingen toepassen…"
        await engine.unloadModel()
        contextSize = newContextSize
        useGPU = newUseGPU
        engine = LLMEngine(configuration: .init(contextSize: newContextSize, batchSize: 256, useGPU: newUseGPU))
        activeModelURL = nil
        if let modelURL { await loadModel(at: modelURL) }
        else { statusMessage = "Instellingen opgeslagen" }
    }

    func generate(
        messages: [LlamaChatMessage],
        systemPrompt: String,
        temperature: Float,
        topP: Float
    ) async throws -> String {
        guard !isGenerating else { throw LLMManagerError.generationInProgress }
        guard activeModelURL != nil else { throw LLMEngine.EngineError.noModelLoaded }

        isGenerating = true
        generatedText = ""
        errorMessage = nil
        lastGenerationStats = nil
        defer { isGenerating = false }

        var prompt = messages
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt.insert(LlamaChatMessage(role: .system, content: systemPrompt), at: 0)
        }
        let sampling = LlamaSamplingConfig(
            temperature: temperature,
            seed: UInt32.random(in: .min ... .max),
            topP: topP,
            topK: 40
        )
        let stream = try await engine.stream(messages: prompt, sampling: sampling)
        let startedAt = Date()
        var firstFragmentAt: Date?

        for try await fragment in stream {
            try Task.checkCancellation()
            if firstFragmentAt == nil { firstFragmentAt = Date() }
            generatedText += fragment
        }

        let finishedAt = Date()
        let firstTokenDelay = firstFragmentAt.map { $0.timeIntervalSince(startedAt) } ?? 0
        let generationDuration = max(0.001, finishedAt.timeIntervalSince(firstFragmentAt ?? startedAt))
        // SwiftLlama's legacy text stream does not expose token counts. This estimate
        // is explicitly approximate, based on average UTF-8 output length per token.
        let estimatedTokens = Double(generatedText.utf8.count) / 4.0
        lastGenerationStats = GenerationStats(
            timeToFirstToken: firstTokenDelay,
            estimatedTokensPerSecond: estimatedTokens / generationDuration,
            outputCharacters: generatedText.count
        )
        return generatedText
    }

    func stopGeneration() async {
        await engine.stopGeneration()
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
