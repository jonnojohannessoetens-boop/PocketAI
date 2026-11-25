import Foundation
import SwiftLlama
import os

/// Thread-safe, single-model inference owner for local GGUF files.
///
/// `SwiftLlama` loads models with llama.cpp's default model parameters. In the
/// pinned upstream runtime, `use_mmap` is enabled by default; this wrapper also
/// checks that the linked backend reports mmap support before loading a model.
/// Model weights and context are released when `unloadModel()` drops the service.
public actor LLMEngine {
    public struct Configuration: Sendable {
        public var contextSize: UInt32
        public var batchSize: UInt32
        public var useGPU: Bool
        public var threadCount: Int32?

        public init(
            contextSize: UInt32 = 2048,
            batchSize: UInt32 = 256,
            useGPU: Bool = true,
            threadCount: Int32? = nil
        ) {
            self.contextSize = contextSize
            self.batchSize = batchSize
            self.useGPU = useGPU
            self.threadCount = threadCount
        }

        fileprivate var llamaConfig: LlamaConfig {
            LlamaConfig(
                batchSize: batchSize,
                maxTokenCount: contextSize,
                useGPU: useGPU,
                nThreads: threadCount,
                nThreadsBatch: threadCount
            )
        }
    }

    public enum EngineError: LocalizedError, Sendable {
        case modelFileMissing
        case invalidModelFile
        case mmapUnavailable
        case modelMayExceedMemory(modelBytes: UInt64, availableBytes: UInt64)
        case noModelLoaded

        public var errorDescription: String? {
            switch self {
            case .modelFileMissing:
                return "Het GGUF-modelbestand is niet gevonden."
            case .invalidModelFile:
                return "Kies een geldig bestand met de extensie .gguf."
            case .mmapUnavailable:
                return "Deze llama.cpp-build ondersteunt geen geheugen-mapping (mmap)."
            case let .modelMayExceedMemory(modelBytes, availableBytes):
                let modelGB = Double(modelBytes) / 1_073_741_824
                let availableGB = Double(availableBytes) / 1_073_741_824
                return String(
                    format: "Dit model is mogelijk te groot voor het beschikbare app-geheugen (%.2f GB model; circa %.2f GB beschikbaar). Kies een kleiner GGUF-model.",
                    modelGB,
                    availableGB
                )
            case .noModelLoaded:
                return "Laad eerst een GGUF-model."
            }
        }
    }

    private let configuration: Configuration
    private var service: LlamaService?
    private var loadedModelURL: URL?
    private var loadRequestID: UUID?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Validates and prepares a local GGUF model. No network access is performed.
    public func loadModel(at url: URL) async throws {
        guard url.pathExtension.lowercased() == "gguf" else {
            throw EngineError.invalidModelFile
        }
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else {
            throw EngineError.modelFileMissing
        }
        guard LlamaBackend.supportsMmap else {
            throw EngineError.mmapUnavailable
        }
        try Self.checkMemoryBudget(modelBytes: fileSize, contextSize: configuration.contextSize)

        let requestID = UUID()
        loadRequestID = requestID
        let previousService = service
        service = nil
        loadedModelURL = nil
        await previousService?.stopCompletion()

        let newService = LlamaService(modelUrl: url, config: configuration.llamaConfig)
        do {
            // Prompt processing causes LlamaService to create the model and context now,
            // so loading errors are reported before the first user message is sent.
            try await newService.processMessages([
                LlamaChatMessage(role: .system, content: "You are a helpful assistant.")
            ])
            guard loadRequestID == requestID else {
                await newService.stopCompletion()
                throw CancellationError()
            }
            service = newService
            loadedModelURL = url
        } catch {
            await newService.stopCompletion()
            if loadRequestID == requestID {
                loadRequestID = nil
            }
            throw error
        }
    }

    /// Streams UTF-8-safe text chunks produced by the model.
    public func stream(
        messages: [LlamaChatMessage],
        sampling: LlamaSamplingConfig = .init(temperature: 0.7, seed: UInt32.random(in: .min ... .max))
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let service, loadedModelURL != nil else {
            throw EngineError.noModelLoaded
        }
        return try await service.streamCompletion(of: messages, samplingConfig: sampling)
    }

    /// Stops the active generation and waits for llama.cpp to finish using the context.
    public func stopGeneration() async {
        await service?.stopCompletion()
    }

    /// Stops inference, releases model/context ownership, and clears the loaded model URL.
    public func unloadModel() async {
        loadRequestID = nil
        let oldService = service
        service = nil
        loadedModelURL = nil
        await oldService?.stopCompletion()
        // Releasing this final strong reference releases the wrapper's Llama actor,
        // its context, and model weights; no memory-limit entitlement is requested.
    }

    public var modelURL: URL? { loadedModelURL }

    private static func checkMemoryBudget(modelBytes: UInt64, contextSize: UInt32) throws {
        #if os(iOS)
        let availableBytes = UInt64(os_proc_available_memory())
        #else
        let availableBytes = ProcessInfo.processInfo.physicalMemory
        #endif

        // GGUF file size is a rough lower bound for resident weights. Reserve 15%
        // for runtime overhead plus a conservative context/KV estimate and 256 MiB
        // for the UI, tokenizer, and other app allocations.
        let weightEstimate = modelBytes.multipliedReportingOverflow(by: 115).partialValue / 100
        let contextEstimate = UInt64(contextSize).multipliedReportingOverflow(by: 64 * 1024).partialValue
        let baseEstimate = weightEstimate.addingReportingOverflow(contextEstimate).partialValue
        let estimate = baseEstimate.addingReportingOverflow(256 * 1_048_576).partialValue

        guard estimate < availableBytes else {
            throw EngineError.modelMayExceedMemory(
                modelBytes: modelBytes,
                availableBytes: availableBytes
            )
        }
    }
}
