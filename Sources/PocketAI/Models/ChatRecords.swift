import Foundation
import SwiftData

@Model
final class ChatConversationRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "Nieuw gesprek", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ChatMessageRecord {
    @Attribute(.unique) var id: UUID
    var conversationID: UUID
    var role: String
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), conversationID: UUID, role: String, content: String, createdAt: Date = .now) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
