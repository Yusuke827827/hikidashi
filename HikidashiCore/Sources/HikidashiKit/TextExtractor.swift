// 画像とファイルから文字を取り出す。すべて端末の中で行う（Apple の Vision と PDFKit。料金なし）。
//   写真・スクショ: 文字認識（日本語・英語）
//   PDF: 文字があればそのまま、無ければ（スキャンした PDF）先頭 3 ページを画像にして文字認識
//   テキストファイル: そのまま

import Foundation
#if canImport(Vision)
import Vision
#endif
#if canImport(PDFKit)
import PDFKit
#endif
import CoreGraphics
import ImageIO

public enum TextExtractor {
    /// 本文に足したことの目印
    public static let imageMarker = "📷 "
    public static let fileMarker = "📄 "

    /// 取り出す文字の上限（AI に渡す長さを抑える）
    static let maxLength = 4000

    /// 添付の種類を拡張子で決める
    public enum Kind: Equatable { case image, pdf, text, other }

    public static func kind(ofExtension ext: String) -> Kind {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp": return .image
        case "pdf": return .pdf
        case "txt", "md", "markdown", "csv", "json", "html", "htm", "rtf", "log": return .text
        default: return .other
        }
    }

    /// 画像の文字認識
    public static func ocr(imageData: Data) async -> String? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return await ocr(cgImage: image)
    }

    public static func ocr(cgImage: CGImage) async -> String? {
        #if canImport(Vision)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        guard (try? VNImageRequestHandler(cgImage: cgImage).perform([request])) != nil else { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(maxLength))
        #else
        return nil
        #endif
    }

    /// ファイルの文字（PDF・テキスト・画像）
    public static func text(fromFile data: Data, extension ext: String) async -> String? {
        switch kind(ofExtension: ext) {
        case .image:
            return await ocr(imageData: data)
        case .text:
            let s = (String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : String(s.prefix(maxLength))
        case .pdf:
            return await pdfText(data)
        case .other:
            return nil
        }
    }

    static func pdfText(_ data: Data) async -> String? {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(data: data) else { return nil }
        let s = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 20 { return String(s.prefix(maxLength)) }
        // 文字が入っていない PDF（スキャン）は、先頭 3 ページを画像にして読む
        var pages: [String] = []
        for i in 0..<min(3, doc.pageCount) {
            guard let page = doc.page(at: i), let image = render(page) else { continue }
            if let t = await ocr(cgImage: image) { pages.append(t) }
        }
        let joined = pages.joined(separator: "\n\n")
        return joined.isEmpty ? nil : String(joined.prefix(maxLength))
        #else
        return nil
        #endif
    }

    #if canImport(PDFKit)
    static func render(_ page: PDFPage) -> CGImage? {
        guard let ref = page.pageRef else { return nil }
        let box = ref.getBoxRect(.mediaBox)
        let scale = min(2.0, 2000 / max(box.width, box.height, 1))
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(ref)
        return ctx.makeImage()
    }
    #endif

    /// 取り出した文字を本文に足す。二度は足さない
    public static func merge(_ text: String, extracted: String, marker: String) -> String {
        let add = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !add.isEmpty, !text.contains(marker) else { return text }
        let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? marker + add : base + "\n\n" + marker + add
    }
}
