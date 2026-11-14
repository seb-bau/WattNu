import SwiftUI

struct ContactActionRowView: View {
    let title: String
    let value: String
    let comment: String?
    let systemImage: String
    let urlScheme: String

    var body: some View {
        Group {
            if let url = ContactActionDestination.url(scheme: urlScheme, value: value) {
                Link(destination: url) { content }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(title): \(value)")
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body)

                if let comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "arrow.up.right.circle")
        }
        .contentShape(Rectangle())
    }
}

enum ContactActionDestination {
    static func url(scheme: String, value: String) -> URL? {
        let normalized: String
        switch scheme {
        case "tel":
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let dialable = trimmed.hasPrefix("+") || trimmed.hasPrefix("00")
                ? trimmed.replacingOccurrences(of: "(0)", with: "") : trimmed
            normalized = dialable.filter { "+0123456789*#".contains($0) }
            guard normalized.contains(where: { $0.isNumber }) else { return nil }
        case "mailto":
            normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.contains("@"), !normalized.contains(where: { $0.isWhitespace }) else { return nil }
        default:
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.path = normalized
        return components.url
    }
}
