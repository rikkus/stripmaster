import Foundation

/// One recorded change. The label is computed from the edit so it always agrees
/// with the current catalogue wording.
struct HistoryEntry: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var date: Date
    var edit: BoardEdit

    init(id: UUID = UUID(), date: Date = .now, edit: BoardEdit) {
        self.id = id
        self.date = date
        self.edit = edit
    }

    var label: String { edit.label }
}

/// The document's edit history and its undo cursor.
///
/// The cursor counts applied entries: `0...entries.count`. Undo moves it back
/// and reverts the entry; redo moves it forward and re-applies it. Recording a
/// new edit discards anything that was redoable.
struct EditHistory: Equatable, Codable, Sendable {
    private(set) var entries: [HistoryEntry]
    /// Number of entries currently applied. 0 means everything is undone.
    private(set) var cursor: Int

    init(entries: [HistoryEntry] = [], cursor: Int? = nil) {
        self.entries = entries
        self.cursor = min(max(cursor ?? entries.count, 0), entries.count)
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case cursor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent([HistoryEntry].self, forKey: .entries) ?? []
        let cursor = try container.decodeIfPresent(Int.self, forKey: .cursor) ?? entries.count
        self.init(entries: entries, cursor: cursor)
        self = sanitized()
    }

    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor < entries.count }

    var undoLabel: String? {
        guard canUndo, entries.indices.contains(cursor - 1) else { return nil }
        return entries[cursor - 1].label
    }

    var redoLabel: String? {
        guard canRedo, entries.indices.contains(cursor) else { return nil }
        return entries[cursor].label
    }

    var undoCount: Int { cursor }
    var redoCount: Int { entries.count - cursor }
    var isEmpty: Bool { entries.isEmpty }

    @discardableResult
    mutating func record(_ edit: BoardEdit, date: Date = .now, id: UUID = UUID()) -> HistoryEntry {
        if canRedo {
            entries.removeSubrange(cursor...)
        }
        let entry = HistoryEntry(id: id, date: date, edit: edit)
        entries.append(entry)
        cursor = entries.count
        return entry
    }

    /// Steps backwards and returns the edit that must be reverted.
    mutating func undo() -> BoardEdit? {
        guard canUndo else { return nil }
        cursor -= 1
        return entries[cursor].edit
    }

    /// Steps forwards and returns the edit that must be re-applied.
    mutating func redo() -> BoardEdit? {
        guard canRedo else { return nil }
        let edit = entries[cursor].edit
        cursor += 1
        return edit
    }

    mutating func removeAll() {
        entries.removeAll()
        cursor = 0
    }

    /// Clamps anything that could arrive from a damaged or older document.
    func sanitized() -> EditHistory {
        var seen = Set<UUID>()
        let validEntries = entries.filter { seen.insert($0.id).inserted }
        let clampedCursor = min(max(cursor, 0), validEntries.count)
        return EditHistory(entries: validEntries, cursor: clampedCursor)
    }

    /// The most recent applied entries, newest first. Used by a compact history view.
    func appliedEntriesNewestFirst(limit: Int = 20) -> [HistoryEntry] {
        guard cursor > 0 else { return [] }
        let suffix = entries[0..<cursor]
        return Array(suffix.reversed().prefix(max(0, limit)))
    }
}
