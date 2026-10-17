// 画像を小さな JPEG にする。保存と Claude への送信の両方で、長辺 1600px までに縮める。

#if canImport(UIKit)
import UIKit

public enum ImageTools {
    public static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    public static func jpeg(data: Data, maxSide: CGFloat = 1600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(image, maxSide: maxSide)
    }
}
#endif
