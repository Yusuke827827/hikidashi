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
        // 小さい画像は 2 倍にしてから読む（細かい字の読み違いを減らす）
        let image = cgImage.width < 1100 ? (upscale(cgImage, by: 2) ?? cgImage) : cgImage
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        if #available(iOS 16.0, macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return nil }
        let boxes: [OCRLine] = (request.results ?? []).compactMap { o in
            guard let t = o.topCandidates(1).first?.string else { return nil }
            let b = o.boundingBox
            return OCRLine(text: t, minX: b.minX, maxX: b.maxX, minY: b.minY, maxY: b.maxY)
        }
        let text = arrange(boxes).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(maxLength))
        #else
        return nil
        #endif
    }

    static func upscale(_ img: CGImage, by f: Int) -> CGImage? {
        let w = img.width * f, h = img.height * f
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// 読み取った 1 行（位置は 0〜1。Vision と同じく下が 0）
    public struct OCRLine: Sendable, Equatable {
        public var text: String
        public var minX: Double, maxX: Double, minY: Double, maxY: Double
        public init(text: String, minX: Double, maxX: Double, minY: Double, maxY: Double) {
            self.text = text; self.minX = minX; self.maxX = maxX; self.minY = minY; self.maxY = maxY
        }
        var midY: Double { (minY + maxY) / 2 }
        var height: Double { maxY - minY }
    }

    /// 読む順（上から下、同じ高さなら左から右）に並べ、折り返しでちぎれた文をつなぐ
    public static func arrange(_ boxes: [OCRLine]) -> String {
        guard !boxes.isEmpty else { return "" }
        // 同じ高さの文字を 1 行にまとめる
        var rows: [[OCRLine]] = []
        for b in boxes.sorted(by: { $0.midY > $1.midY }) {
            if let i = rows.indices.last, let ref = rows[i].first, abs(ref.midY - b.midY) < min(ref.height, b.height) * 0.5 {
                rows[i].append(b)
            } else {
                rows.append([b])
            }
        }
        struct Row { var text: String; var minX: Double; var maxX: Double; var top: Double; var bottom: Double; var height: Double }
        let lines: [Row] = rows.map { r in
            let sorted = r.sorted { $0.minX < $1.minX }
            var t = ""
            for (i, b) in sorted.enumerated() {
                if i > 0 {
                    let prev = sorted[i - 1].text, gap = b.minX - sorted[i - 1].maxX
                    // 大きく離れていれば区切り、英数どうしなら空白、日本語どうしならそのまま
                    if gap > 0.08 { t += "  " } else if prev.last.map(isWordChar) == true && b.text.first.map(isWordChar) == true { t += " " }
                }
                t += b.text
            }
            return Row(text: t, minX: sorted.map(\.minX).min() ?? 0, maxX: sorted.map(\.maxX).max() ?? 1,
                       top: r.map(\.maxY).max() ?? 0, bottom: r.map(\.minY).min() ?? 0, height: r.map(\.height).max() ?? 0)
        }
        let right = lines.map(\.maxX).max() ?? 1
        var out: [String] = []
        for (i, l) in lines.enumerated() {
            guard i > 0, let last = out.last else { out.append(l.text); continue }
            let prev = lines[i - 1]
            let gap = prev.bottom - l.top
            // 前の行が右端近くまであり、文の終わりでなく、行の間が狭く、箇条書きで始まらなければ、折り返しとみなしてつなぐ
            let wrapped = prev.maxX > right - 0.08 && gap < prev.height * 0.9
                && !(last.last.map { "。．.!?！？」』）):：".contains($0) } ?? true)
                && l.text.range(of: #"^\s*(?:[・•\-*●◆■□☐☑]|\d+[.)、])"#, options: .regularExpression) == nil
            if wrapped {
                out[out.count - 1] = last + ((last.last.map(isWordChar) == true && l.text.first.map(isWordChar) == true) ? " " : "") + l.text
            } else {
                // 段落の切れ目（行の間が広い）は空行にする
                if gap > max(prev.height, l.height) * 1.6 { out.append("") }
                out.append(l.text)
            }
        }
        return out.joined(separator: "\n")
    }

    static func isWordChar(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }

    /// 写真に写った QR コード・バーコードの中身
    public static func barcodes(_ data: Data) async -> [String] {
        #if canImport(Vision)
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let req = VNDetectBarcodesRequest()
            guard (try? VNImageRequestHandler(data: data).perform([req])) != nil else { return [] }
            var seen: [String] = []
            for r in req.results ?? [] { if let s = r.payloadStringValue, !s.isEmpty, !seen.contains(s) { seen.append(s) } }
            return seen
        }.value
        #else
        return []
        #endif
    }

    /// ファイルの文字（PDF・テキスト・画像）
    /// 写真に写っているもの（Vision の分類。自信が高いものを 6 つまで、よく使うものは日本語に）
    public static func imageLabels(_ data: Data) async -> [String] {
        #if canImport(Vision)
        return await Task.detached(priority: .utility) { () -> [String] in
            let req = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(data: data)
            guard (try? handler.perform([req])) != nil, let results = req.results else { return [] }
            return results.filter { $0.confidence > 0.35 }.prefix(6).map { labelName($0.identifier) }
        }.value
        #else
        return []
        #endif
    }

    static let jaLabels: [String: String] = [
        "food": "食べ物", "dish": "料理", "meal": "料理", "dessert": "デザート", "drink": "飲み物", "coffee": "コーヒー", "bread": "パン",
        "dog": "犬", "cat": "猫", "animal": "動物", "plant": "植物", "flower": "花", "tree": "木", "sky": "空", "outdoor": "屋外",
        "building": "建物", "structure": "建物", "city": "街", "street": "道", "car": "車", "vehicle": "乗り物", "train": "電車",
        "document": "書類", "text": "文字", "screenshot": "スクショ", "people": "人", "person": "人", "clothing": "服", "shoes": "靴",
        "furniture": "家具", "room": "部屋", "kitchen": "台所", "electronics": "電子機器", "computer": "パソコン", "phone": "スマホ",
        "book": "本", "receipt": "レシート", "map": "地図", "sign": "看板", "beach": "海辺", "mountain": "山",
    ]

    static func labelName(_ id: String) -> String {
        let key = id.lowercased().replacingOccurrences(of: "_", with: " ")
        if AppLanguage.current == .ja, let ja = jaLabels[key] ?? jaLabels[key.components(separatedBy: " ").last ?? key] { return ja }
        return key
    }

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
