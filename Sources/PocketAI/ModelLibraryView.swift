import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    @Environment(LLMManager.self) private var llm
    @State private var library = ModelLibrary()
    @State private var showingImporter = false
    @State private var downloadProgress: Double?

    var body: some View {
        List {
            Section("Lokaal op dit apparaat") {
                if library.downloadedFiles.isEmpty {
                    ContentUnavailableView("Geen modellen", systemImage: "shippingbox", description: Text("Importeer of download een GGUF-bestand."))
                } else {
                    ForEach(library.downloadedFiles, id: \.absoluteString) { file in
                        Button { Task { await llm.loadModel(at: file) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.deletingPathExtension().lastPathComponent).foregroundStyle(.primary)
                                    Text(fileSize(for: file)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if llm.activeModelURL == file { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                            }
                        }
                    }
                    .onDelete(perform: deleteModels)
                }
                Button { showingImporter = true } label: {
                    Label("GGUF importeren uit Bestanden", systemImage: "folder")
                }
            }
            Section("Modelcatalogus") {
                ForEach(library.catalog) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.headline)
                        Text(item.description).font(.caption).foregroundStyle(.secondary)
                        Button { Task { await library.download(item) } } label: {
                            Label("Download model", systemImage: "arrow.down.circle")
                        }
                        .disabled(library.isDownloading)
                    }
                    .padding(.vertical, 4)
                }
            }
            if library.isDownloading {
                Section("Download") {
                    if let downloadProgress {
                        ProgressView(value: downloadProgress)
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView(library.downloadMessage ?? "Downloaden…")
                    }
                }
            }
            if let message = llm.statusMessage { Section("Status") { Text(message).font(.footnote) } }
            if let error = llm.errorMessage ?? library.errorMessage { Section("Melding") { Text(error).font(.footnote).foregroundStyle(.red) } }
        }
        .navigationTitle("Modellen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Vernieuwen", systemImage: "arrow.clockwise") { library.refreshFiles() }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let localURL = try library.importModel(from: url)
                Task { await llm.loadModel(at: localURL) }
            } catch { library.report(error) }
        }
    }

    private func fileSize(for url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func deleteModels(at offsets: IndexSet) {
        for index in offsets {
            let file = library.downloadedFiles[index]
            if llm.activeModelURL == file { Task { await llm.unloadModel() } }
            try? FileManager.default.removeItem(at: file)
        }
        library.refreshFiles()
    }
}
