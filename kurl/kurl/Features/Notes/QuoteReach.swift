import Foundation

/// 인용이 닿는 범위. 누구나 보는 것은 어디서나 인용하고, 방의 것은 그 방 안에서만 인용한다.
/// 서버(NoteComposer·PostNoteQuotes)가 같은 규칙으로 거절하고 센다 — 한쪽을 고치면 다른 쪽도 고친다.
enum QuoteReach: Hashable {
    case anywhere
    case room(NoteRoom)
    case nowhere

    init(note: Note) {
        if let room = note.room {
            self = .room(room)
        } else {
            self = note.noteVisibility.shareable ? .anywhere : .nowhere
        }
    }

    init(post audience: PostAudience?, room: NoteRoom?) {
        switch audience ?? .everyone {
        case .everyone, .followers, .password: self = .anywhere
        case .room: self = room.map(QuoteReach.room) ?? .nowhere
        case .unlisted: self = .nowhere
        }
    }

    var room: NoteRoom? {
        if case .room(let room) = self { room } else { nil }
    }

    /// 방 `roomId`(nil 이면 방 밖)에 올리는 노트·글이 이것을 실을 수 있는가. 노트 인용과 글 속 노트 카드가 같은 답을 쓴다.
    func allows(roomId: Int64?) -> Bool {
        switch self {
        case .anywhere: true
        case .room(let room): room.id == roomId
        case .nowhere: false
        }
    }

    /// 인용한 노트가 이것의 인용 목록에 드는가 — 같은 벽 안에 있을 때만.
    func lists(_ quoting: Note) -> Bool {
        switch self {
        case .anywhere: quoting.room == nil && quoting.noteVisibility.shareable
        case .room(let room): quoting.room?.id == room.id
        case .nowhere: false
        }
    }

    /// 방금 올린 인용 노트를 인용된 노트가 놓인 목록에 끼워도 되는가 — 같은 방이거나 둘 다 방 밖일 때만.
    static func landsBeside(_ quoted: Note, _ created: Note) -> Bool {
        quoted.room?.id == created.room?.id
    }
}
