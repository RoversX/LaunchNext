import SwiftUI

struct ReleaseNotesMarkdownView: View {
    enum Mode {
        case preview
        case full
    }

    private let model: MarkdownRenderModel
    private let mode: Mode
    private let imageCornerRadius: CGFloat = 14

    init(model: MarkdownRenderModel, mode: Mode) {
        self.model = model
        self.mode = mode
    }

    init(source: String, mode: Mode) {
        self.model = SimpleMarkdownParser.parse(source)
        self.mode = mode
    }

    var body: some View {
        switch mode {
        case .preview:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(previewBlocks) { block in
                    previewBlockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .full:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.blocks) { block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func previewBlockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(_, let level, let text):
            Text(SimpleMarkdownParser.inlineAttributedText(from: text))
                .font(previewHeadingFont(level))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(_, let text), .quote(_, let text):
            Text(SimpleMarkdownParser.inlineAttributedText(from: text))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bulletList(_, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\u{2022}")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(SimpleMarkdownParser.inlineAttributedText(from: item))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .orderedList(_, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Text(SimpleMarkdownParser.inlineAttributedText(from: item))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .codeBlock(_, _, let code):
            Text(code)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

        case .image(_, let alt, let source):
            markdownImageView(alt: alt, source: source, isPreview: true)

        case .divider:
            Divider()
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(_, let level, let text):
            Text(SimpleMarkdownParser.inlineAttributedText(from: text))
                .font(headingFont(level))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(_, let text):
            Text(SimpleMarkdownParser.inlineAttributedText(from: text))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

        case .bulletList(_, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\u{2022}")
                            .foregroundStyle(.secondary)
                        Text(SimpleMarkdownParser.inlineAttributedText(from: item))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .orderedList(_, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(SimpleMarkdownParser.inlineAttributedText(from: item))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .quote(_, let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 4)
                Text(SimpleMarkdownParser.inlineAttributedText(from: text))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .codeBlock(_, _, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

        case .image(_, let alt, let source):
            markdownImageView(alt: alt, source: source)

        case .divider:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.weight(.semibold)
        case 2: return .headline.weight(.semibold)
        case 3: return .subheadline.weight(.semibold)
        default: return .footnote.weight(.semibold)
        }
    }

    private func previewHeadingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .headline.weight(.semibold)
        case 2: return .subheadline.weight(.semibold)
        default: return .footnote.weight(.semibold)
        }
    }

    private var previewBlocks: [MarkdownBlock] {
        Array(model.blocks.prefix(3))
    }

    @ViewBuilder
    private func markdownImageView(alt: String, source: String, isPreview: Bool = false) -> some View {
        if let url = URL(string: source), let scheme = url.scheme, scheme.hasPrefix("http") {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: isPreview ? 150 : nil)
                    case .failure:
                        markdownImagePlaceholder(alt: alt)
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: isPreview ? 100 : 120)
                            ProgressView()
                                .controlSize(.small)
                        }
                    @unknown default:
                        markdownImagePlaceholder(alt: alt)
                    }
                }
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))

                if !alt.isEmpty {
                    Text(alt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            markdownImagePlaceholder(alt: alt)
        }
    }

    private func markdownImagePlaceholder(alt: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text(alt.isEmpty ? "Image" : alt)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
