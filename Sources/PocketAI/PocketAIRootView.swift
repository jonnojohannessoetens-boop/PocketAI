import SwiftUI
import SwiftData

struct PocketAIRootView: View {
    @Environment(LLMManager.self) private var llm
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatConversationRecord.updatedAt, order: .reverse) private var conversations: [ChatConversationRecord]
    @State private var selectedConversationID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedConversationID) {
                Section("Bibliotheek") {
                    NavigationLink {
                        ModelLibraryView()
                    } label: {
                        Label("Modellen", systemImage: "cpu")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Instellingen", systemImage: "slider.horizontal.3")
                    }
                }
                Section("Gesprekken") {
                    ForEach(conversations) { conversation in
                        Text(conversation.title)
                            .tag(conversation.id)
                    }
                    .onDelete(perform: deleteConversations)
                }
            }
            .navigationTitle("PocketAI")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createConversation) {
                        Label("Nieuw gesprek", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let selectedConversationID {
                ChatScreen(conversationID: selectedConversationID)
            } else {
                ContentUnavailableView(
                    "PocketAI",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start een gesprek of laad eerst een lokaal model.")
                )
            }
        }
        .task {
            if selectedConversationID == nil, let first = conversations.first {
                selectedConversationID = first.id
            }
        }
    }

    private func createConversation() {
        let conversation = ChatConversationRecord()
        modelContext.insert(conversation)
        try? modelContext.save()
        selectedConversationID = conversation.id
    }

    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            let conversation = conversations[index]
            let id = conversation.id
            let descriptor = FetchDescriptor<ChatMessageRecord>(predicate: #Predicate { $0.conversationID == id })
            if let messages = try? modelContext.fetch(descriptor) {
                messages.forEach(modelContext.delete)
            }
            modelContext.delete(conversation)
        }
        try? modelContext.save()
        if !conversations.contains(where: { $0.id == selectedConversationID }) {
            selectedConversationID = conversations.first?.id
        }
    }
}
