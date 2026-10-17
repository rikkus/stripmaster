import SwiftUI

/// Maps the document-creation source (iOS launch scene) to a board template.
enum LaunchTemplateSelection {
    static func template(for context: DocumentCreationContext) -> BoardTemplate {
        #if os(iOS)
        if let source = context.creationSource {
            if source == .sixteenByEight { return .sixteenByEight }
            if source == .twentyFourByTwelve { return .twentyFourByTwelve }
            if source == .thirtyTwoBySixteen { return .thirtyTwoBySixteen }
            if source == .fortyEightByTwentyFour { return .fortyEightByTwentyFour }
        }
        #endif
        return .default
    }

    static func wasExplicit(_ context: DocumentCreationContext) -> Bool {
        context.creationSource != nil
    }
}

#if os(iOS)
extension DocumentCreationSource {
    static let sixteenByEight = DocumentCreationSource(id: "stripmaster.template.16x8")
    static let twentyFourByTwelve = DocumentCreationSource(id: "stripmaster.template.24x12")
    static let thirtyTwoBySixteen = DocumentCreationSource(id: "stripmaster.template.32x16")
    static let fortyEightByTwentyFour = DocumentCreationSource(id: "stripmaster.template.48x24")
}
#endif
