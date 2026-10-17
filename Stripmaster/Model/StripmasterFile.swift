import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// The native stripmaster board format. JSON keeps documents inspectable and
    /// makes the edit history's command stream easy to evolve.
    static let stripmasterBoard = UTType(
        exportedAs: "cc.hemsley.stripmaster.board",
        conformingTo: .json
    )
}

enum StripmasterFileFormat {
    static let fileExtension = "stripmaster"
    static let contentType = UTType.stripmasterBoard
    static let defaultFilename = "Untitled.stripmaster"
}

/// Everything written into a `.stripmaster` file.
struct StripmasterFile: Equatable, Codable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var state: StripmasterDocumentState

    init(state: StripmasterDocumentState, formatVersion: Int = StripmasterFile.currentFormatVersion) {
        self.formatVersion = formatVersion
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        guard version >= 1 else {
            throw StripmasterDocumentError.unsupportedFormatVersion(version)
        }
        guard version <= StripmasterFile.currentFormatVersion else {
            throw StripmasterDocumentError.unsupportedFormatVersion(version)
        }
        let state = try container.decode(StripmasterDocumentState.self, forKey: .state)
        self.init(state: state.sanitized(), formatVersion: version)
    }
}

enum StripmasterDocumentError: Error, Equatable, LocalizedError {
    case unsupportedFormatVersion(Int)
    case missingFileContents

    var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let version):
            "This stripmaster document was saved by a newer version (format \(version))."
        case .missingFileContents:
            "The stripmaster document is missing its contents."
        }
    }
}

enum StripmasterFileCodec {
    static func encode(_ file: StripmasterFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> StripmasterFile {
        try JSONDecoder().decode(StripmasterFile.self, from: data)
    }

    static func encode(state: StripmasterDocumentState) throws -> Data {
        try encode(StripmasterFile(state: state))
    }

    static func decodeState(_ data: Data) throws -> StripmasterDocumentState {
        try decode(data).state
    }
}
