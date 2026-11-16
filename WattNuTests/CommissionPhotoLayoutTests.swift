import SwiftUI
import Testing
import UIKit
@testable import WattNu

@MainActor
struct CommissionPhotoLayoutTests {
    @Test(arguments: [CGSize(width: 2400, height: 200), CGSize(width: 200, height: 2400), CGSize(width: 800, height: 800)])
    func photoThumbnailsStayWithinTheGridColumnForEveryImageShape(imageSize: CGSize) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
        }
        let widths: [CGFloat] = [92, 120, 140, 180, 320]
        let heights: [CGFloat] = [110, 130]
        for width in widths {
            for height in heights {
                let controller = UIHostingController(rootView: CommissionPhotoThumbnail(image: image, height: height))
                let measured = controller.sizeThatFits(in: CGSize(width: width, height: height))
                #expect(abs(measured.width - width) < 0.5)
                #expect(abs(measured.height - height) < 0.5)
            }
        }
    }

    @Test func loadingPlaceholderAndLoadedPhotoHaveIdenticalBounds() {
        let placeholder = UIHostingController(rootView: CommissionPhotoThumbnail(image: nil, height: 130))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 200)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 200))
        }
        let loaded = UIHostingController(rootView: CommissionPhotoThumbnail(image: image, height: 130))
        let proposed = CGSize(width: 120, height: 130)
        #expect(placeholder.sizeThatFits(in: proposed) == loaded.sizeThatFits(in: proposed))
    }
}
