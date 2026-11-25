import SwiftUI
import UniformTypeIdentifiers

struct DocumentLibraryView: View {
    @Environment(LocalDocumentStore.self) private var store
    @State private var isImporting = false

    var body: some View {
        List {
            Section {
                Text("Geïmporteerde documenten blijven lokaal. Relevante tekstfragmenten worden bij een vraag toegevoegd aan de prompt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button { isImporting = true } label: {
                    Label("Document toevoegen", systemImage: "doc.badge.plus")
                }
            }
            Section("Documenten") {
                if store.documents.isEmpty {
                    ContentUnavailableView("Geen documenten", systemImage: "doc.text", description: Text("Voeg een TXT- of PDF-bestand toe voor lokale documentvragen."))
                }
                ForEach(store.documents) { document in
                    Label(document.id, systemImage: document.url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.text")
                }
                .onDelete { offsets in
                    offsets.map { store.documents[$0] }.forEach(store.remove)
                }
            }
            if let error = store.errorMessage {
                Section("Melding") { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Documenten")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.plainText, .pdf],
            allowsMultipleSelection: true
        ) { result in
            do {
                for url in try result.get() { try store.importDocument(from: url) }
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}
