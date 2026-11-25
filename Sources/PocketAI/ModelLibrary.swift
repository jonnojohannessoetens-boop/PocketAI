import Foundation
import Observation

struct ModelCatalogItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let downloadURL: URL

    static let featured: [ModelCatalogItem] = [
        .init(
            id: "qwen25-15b-q4km",
            title: "Qwen 2.5 1.5B · Q4_K_M",
            description: "Compact instruct-model, geschikt als eerste test.",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf")!
        ),
        .init(
            id: "llama32-1b-q4km",
            title: "Llama 3.2 1B · Q4_K_M",
            description: "Klein Llama-instruct-model voor mobiele apparaten.",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!
        ),
        .init(
            id: "gemma2-2b-q4km",
            title: "Gemma 2 2B · Q4_K_M",
            description: "Een compact open model van Google.",
            downloadURL: URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf")!
        )
    ]
}

@MainActor
@Observable
final class ModelLibrary {
    private(set) var isDownloading = false
    private(set) var downloadMessage: String?
    private(set) var errorMessage: String?
    private(set) var downloadedFiles: [URL] = []

    let catalog = ModelCatalogItem.featured

    init() {
        refreshFiles()
    }

    var modelsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Models", isDirectory: true)
    }

    func refreshFiles() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            downloadedFiles = try FileManager.default.contentsOfDirectory(
                at: modelsDirectory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension.lowercased() == "gguf" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importModel(from sourceURL: URL) throws -> URL {
        guard sourceURL.pathExtension.lowercased() == "gguf" else {
            throw ModelLibraryError.invalidFileType
        }
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: sourceURL.lastPathComponent)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        refreshFiles()
        return destination
    }

    func download(_ item: ModelCatalogItem) async {
        guard !isDownloading else { return }
        isDownloading = true
        errorMessage = nil
        downloadMessage = "Download wordt gestart…"
        defer {
            isDownloading = false
            downloadMessage = nil
        }

        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            let (temporaryURL, response) = try await URLSession.shared.download(from: item.downloadURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw ModelLibraryError.httpStatus(http.statusCode)
            }
            let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
            let required = Int64(values.fileSize ?? 0)
            let available = try modelsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage ?? 0
            guard required == 0 || available > required else {
                throw ModelLibraryError.insufficientStorage
            }
            let fileName = item.downloadURL.lastPathComponent.removingPercentEncoding ?? item.downloadURL.lastPathComponent
            let destination = uniqueDestination(for: fileName)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            downloadMessage = "Download voltooid"
            refreshFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uniqueDestination(for name: String) -> URL {
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        var candidate = modelsDirectory.appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = modelsDirectory.appendingPathComponent("\(base)-\(suffix).gguf")
            suffix += 1
        }
        return candidate
    }
}

enum ModelLibraryError: LocalizedError {
    case invalidFileType
    case insufficientStorage
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            return "Dit bestand is geen GGUF-model."
        case .insufficientStorage:
            return "Er is niet genoeg vrije opslagruimte om dit model op te slaan."
        case let .httpStatus(code):
            return "De modelserver gaf HTTP-status \(code) terug."
        }
    }
}
