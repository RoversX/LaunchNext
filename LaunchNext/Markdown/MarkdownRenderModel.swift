import Foundation

struct MarkdownRenderModel {
    let blocks: [MarkdownBlock]
    let previewText: String

    nonisolated static let empty = MarkdownRenderModel(blocks: [], previewText: "")
}

enum MarkdownBlock: Identifiable {
    case heading(UUID, level: Int, text: String)
    case paragraph(UUID, text: String)
    case bulletList(UUID, items: [String])
    case orderedList(UUID, items: [String])
    case quote(UUID, text: String)
    case codeBlock(UUID, language: String?, code: String)
    case image(UUID, alt: String, source: String)
    case divider(UUID)

    var id: UUID {
        switch self {
        case .heading(let id, _, _),
             .paragraph(let id, _),
             .bulletList(let id, _),
             .orderedList(let id, _),
             .quote(let id, _),
             .codeBlock(let id, _, _),
             .image(let id, _, _),
             .divider(let id):
            return id
        }
    }
}
