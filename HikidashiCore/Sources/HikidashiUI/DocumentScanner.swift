// 書類のスキャン（iPhone のカメラで紙を撮る）。撮ったページを 1 つの PDF にして添付する。文字は保存後に端末の中で読み取る。

#if os(iOS)
import SwiftUI
import UIKit
import VisionKit

struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<min(scan.pageCount, 20)).map { scan.imageOfPage(at: $0) }
            onFinish(Self.pdf(from: pages))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish(nil)
        }

        static func pdf(from pages: [UIImage]) -> Data? {
            guard let first = pages.first else { return nil }
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first.size))
            return renderer.pdfData { ctx in
                for page in pages {
                    let rect = CGRect(origin: .zero, size: page.size)
                    ctx.beginPage(withBounds: rect, pageInfo: [:])
                    page.draw(in: rect)
                }
            }
        }
    }
}
#endif
