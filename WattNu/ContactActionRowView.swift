import SwiftUI

struct ContactActionRowView: View {
    let title: String
    let value: String
    let comment: String?
    let systemImage: String
    let urlScheme: String

    var body: some View {
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

            if let url = actionURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.circle")
                }
            }
        }
    }

    private var actionURL: URL? {
        let normalizedValue = value.replacingOccurrences(of: " ", with: "")
        return URL(string: "\(urlScheme):\(normalizedValue)")
    }
}
