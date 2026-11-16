import SwiftUI
import UIKit

struct CommissionPhotoThumbnail: View {
    let image: UIImage?
    let height: CGFloat
    var cornerRadius: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.secondary.opacity(0.12))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
