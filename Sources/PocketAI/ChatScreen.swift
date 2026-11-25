import SwiftUI
import SwiftData

struct ChatScreen: View {
    let conversationID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(LLMManager.self) private var llm
    @Query(sort: \ChatMessageRecord.createdAt) private var allMessages: [ChatMessageRecord]
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
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: llm.generatedText) { _, _ in
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            composer
        }
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Instellingen")
            }
        }
        .onDisappear {
            generationTask?.cancel()
        }
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
                    Image(systemName: "stop.fill")
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityLabel("Genereren stoppen")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .frame(width: 42, height: 42)
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
        let firstUserMessage = messages.first(where: { $0.role == "user" })?.content
        return firstUserMessage.map { String($0.prefix(32)) } ?? "Nieuw gesprek"
    }

    private func displayedContent(for message: ChatMessageRecord) -> String {
        if llm.isGenerating, message.role == "assistant", message.content.isEmpty {
            return llm.generatedText.isEmpty ? "…" : llm.generatedText
        }
        return message.content
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, llm.activeModelURL != nil else { return }
        draft = ""

        let userRecord = ChatMessageRecord(conversationID: conversationID, role: "user", content: text)
        let assistantRecord = ChatMessageRecord(conversationID: conversationID, role: "assistant", content: "")
        modelContext.insert(userRecord)
        modelContext.insert(assistantRecord)
        try? modelContext.save()

        var promptMessages = messages
            .filter { $0.id != assistantRecord.id }
            .map { LlamaChatMessage(role: $0.role == "assistant" ? .assistant : .user, content: $0.content) }
        promptMessages.append(LlamaChatMessage(role: .user, content: text))

        generationTask = Task {
            do {
                let answer = try await llm.generate(messages: promptMessages)
                guard !Task.isCancelled else { return }
                assistantRecord.content = answer
                try? modelContext.save()
            } catch is CancellationError {
                assistantRecord.content = llm.generatedText
                try? modelContext.save()
            } catch {
                assistantRecord.content = "Fout: \(error.localizedDescription)"
                try? modelContext.save()
            }
        }
    }
}

private struct MessageBubble: View {
    let role: String
    let content: String

    var body: some View {
        HStack {
            if role == "assistant" { bubble }
            else {
                Spacer(minLength: 35)
                bubble
            }
            if role == "assistant" { Spacer(minLength: 35) }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(role == "assistant" ? "PocketAI" : "Jij")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(role == "assistant" ? Color(.secondarySystemBackground) : Color.accentColor.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
