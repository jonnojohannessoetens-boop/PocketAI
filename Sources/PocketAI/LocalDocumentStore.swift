import Foundation
import SwiftData
import PDFKit
import Observation

struct KnowledgeDocument: Identifiable, Hashable {
    let id: String
    let url: URL
}

@MainActor
@Observable
final class LocalDocumentStore {
    private(set) var documents: [KnowledgeDocument] = []
    private(set) var errorMessage: String?

    init() {
        refresh()
    }

    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knowledge", isDirectory: true)
    }

    func refresh() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            documents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { ["txt", "pdf"].contains($0.pathExtension.lowercased()) }
            .map { KnowledgeDocument(id: $0.lastPathComponent, url: $0) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importDocument(from source: URL) throws {
        let ext = source.pathExtension.lowercased()
        guard ext == "txt" || ext == "pdf" else { throw DocumentStoreError.unsupportedType }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = source.deletingPathExtension().lastPathComponent
            destination = directory.appendingPathComponent("\(base)-\(suffix).\(ext)")
            suffix += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        refresh()
    }

    func remove(_ document: KnowledgeDocument) {
        try? FileManager.default.removeItem(at: document.url)
        refresh()
    }

    func relevantContext(for query: String, maximumCharacters: Int = 5_000) -> String {
        let terms = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        guard !terms.isEmpty else { return "" }
        let chunks = documents.flatMap { document -> [(String, Int)] in
            guard let text = Self.readText(document.url) else { return [] }
            return Self.chunks(text, size: 1_000, overlap: 150).compactMap { chunk in
                let words = Set(chunk.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
                let score = terms.intersection(words).count
                return score > 0 ? ("[\(document.id)]\n\(chunk)", score) : nil
            }
        }
        return chunks.sorted { $0.1 > $1.1 }
            .prefix(5)
            .map(\.0)
            .joined(separator: "\n\n")
            .prefix(maximumCharacters)
            .description
    }

    private static func readText(_ url: URL) -> String? {
        if url.pathExtension.lowercased() == "txt" { return try? String(contentsOf: url, encoding: .utf8) }
        guard let pdf = PDFDocument(url: url) else { return nil }
        return (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    }

    private static func chunks(_ text: String, size: Int, overlap: Int) -> [String] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        var result: [String] = []
        var start = 0
        while start < characters.count {
            let end = min(start + size, characters.count)
            result.append(String(characters[start..<end]))
            if end == characters.count { break }
            start = max(start + 1, end - overlap)
        }
        return result
    }
}

enum DocumentStoreError: LocalizedError {
    case unsupportedType
    var errorDescription: String? { "Kies een .txt- of .pdf-document." }
}
