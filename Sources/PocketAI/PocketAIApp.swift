import SwiftUI
import SwiftData

@main
struct PocketAIApp: App {
    @State private var llmManager = LLMManager()
    @State private var documentStore = LocalDocumentStore()

    var body: some Scene {
        WindowGroup {
            PocketAIRootView()
                .environment(llmManager)
                .environment(documentStore)
                .tint(Color(red: 0.08, green: 0.14, blue: 0.30))
        }
        .modelContainer(for: [ChatConversationRecord.self, ChatMessageRecord.self])
    }
}
