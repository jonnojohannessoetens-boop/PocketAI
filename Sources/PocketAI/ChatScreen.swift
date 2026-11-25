import SwiftUI
import UniformTypeIdentifiers

struct ChatScreen: View {
    let conversationID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(LLMManager.self) private var llm
    @Environment(LocalDocumentStore.self) private var documents
    @AppStorage("pocketai.systemPrompt") private var systemPrompt = "Je bent een behulpzame assistent. Antwoord in de taal van de gebruiker."
    @AppStorage("pocketai.temperature") private var temperature = 0.7
    @AppStorage("pocketai.topP") private var topP = 0.9
    @AppStorage("pocketai.useRAG") private var useRAG = false
    @Query(sort: \ChatMessageRecord.createdAt) private var allMessages: [ChatMessageRecord]
    @Query private var allConversations: [ChatConversationRecord]
    @State private var draft = ""
    @State private var generationTask: Task<Void, Never>?

    private var messages: [ChatMessageRecord] {
        allMessages.filter { $0.conversationID == conversationID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let modelURL = llm.activeModelURL {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                    Text(modelURL.lastPathComponent).lineLimit(1)
                    Spacer()
                    if useRAG, !documents.documents.isEmpty {
                        Label("RAG", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
            } else {
                ContentUnavailableView(
                    "Geen model geladen",
                    systemImage: "cpu",
                    description: Text("Open Modellen om een lokaal GGUF-model te importeren of te downloaden.")
                )
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(messages) { message in
                            MessageBubble(role: message.role, content: displayedContent(for: message))
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in scrollToLatest(using: proxy) }
                .onChange(of: llm.generatedText) { _, _ in scrollToLatest(using: proxy) }
            }

            if let stats = llm.lastGenerationStats {
                HStack {
                    Text(String(format: "Eerste token %.2f s", stats.timeToFirstToken))
                    Text("·")
                    Text(String(format: "~%.1f t/s", stats.estimatedTokensPerSecond))
                    Text("·")
                    Text("\(stats.outputCharacters) tekens")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            composer
        }
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { DocumentLibraryView() } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("Documenten")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Instellingen")
            }
        }
        .onDisappear { generationTask?.cancel() }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Typ je bericht…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .disabled(llm.isGenerating || llm.activeModelURL == nil)
            if llm.isGenerating {
                Button {
                    generationTask?.cancel()
                    Task { await llm.stopGeneration() }
                } label: {
                    Image(systemName: "stop.fill").frame(width: 42, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityLabel("Genereren stoppen")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up").frame(width: 42, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || llm.activeModelURL == nil)
                .accessibilityLabel("Versturen")
            }
        }
        .padding()
        .background(.bar)
    }

    private var conversationTitle: String {
        allConversations.first(where: { $0.id == conversationID })?.title ?? "Nieuw gesprek"
    }

    private func displayedContent(for message: ChatMessageRecord) -> String {
        if llm.isGenerating, message.role == "assistant", message.content.isEmpty {
            return llm.generatedText.isEmpty ? "…" : llm.generatedText
        }
        return message.content
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, llm.activeModelURL != nil, !llm.isGenerating else { return }
        draft = ""

        // Capture existing history before inserting the current user/assistant records.
        let history = messages.sorted { $0.createdAt < $1.createdAt }.map {
            LlamaChatMessage(role: $0.role == "assistant" ? .assistant : .user, content: $0.content)
        }
        let userRecord = ChatMessageRecord(conversationID: conversationID, role: "user", content: text)
        let assistantRecord = ChatMessageRecord(conversationID: conversationID, role: "assistant", content: "")
        modelContext.insert(userRecord)
        modelContext.insert(assistantRecord)
        if let conversation = allConversations.first(where: { $0.id == conversationID }) {
            if conversation.title == "Nieuw gesprek" { conversation.title = String(text.prefix(40)) }
            conversation.updatedAt = .now
        }
        try? modelContext.save()

        generationTask = Task { @MainActor in
            do {
                var prompt = history
                if useRAG {
                    let context = documents.relevantContext(for: text)
                    if !context.isEmpty {
                        prompt.append(LlamaChatMessage(role: .system, content: "Gebruik de volgende lokale documentfragmenten alleen als relevante context. Als het antwoord er niet in staat, zeg dat duidelijk.\n\n\(context)"))
                    }
                }
                prompt.append(LlamaChatMessage(role: .user, content: text))
                let answer = try await llm.generate(
                    messages: prompt,
                    systemPrompt: systemPrompt,
                    temperature: Float(temperature),
                    topP: Float(topP)
                )
                assistantRecord.content = answer
            } catch is CancellationError {
                assistantRecord.content = llm.generatedText
            } catch {
                assistantRecord.content = "Fout: \(error.localizedDescription)"
            }
            try? modelContext.save()
        }
    }
}

private struct MessageBubble: View {
    let role: String
    let content: String

    var body: some View {
        HStack {
            if role == "assistant" { bubble }
            else { Spacer(minLength: 35); bubble }
            if role == "assistant" { Spacer(minLength: 35) }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(role == "assistant" ? "JJS" : "Jij")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            MarkdownMessageView(markdown: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(role == "assistant" ? Color(.secondarySystemBackground) : Color.accentColor.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
