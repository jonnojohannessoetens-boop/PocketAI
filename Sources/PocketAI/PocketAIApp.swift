import SwiftUI
import SwiftData

@main
struct PocketAIApp: App {
    @State private var llmManager = LLMManager()

    var body: some Scene {
        WindowGroup {
            PocketAIRootView()
                .environment(llmManager)
                .tint(Color(red: 0.255, green: 0.412, blue: 0.882))
        }
        .modelContainer(for: [ChatConversationRecord.self, ChatMessageRecord.self])
    }
}
