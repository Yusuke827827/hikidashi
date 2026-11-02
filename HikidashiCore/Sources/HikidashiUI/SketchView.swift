// 手書き・スケッチ。Apple Pencil や指で描き、画像として添付する（中の文字は、しまうときに読み取る）。

#if os(iOS)
import PencilKit
import SwiftUI

struct SketchView: View {
    /// 描いた絵（JPEG）。キャンセルなら nil
    var onDone: (Data?) -> Void

    @State private var canvas = PKCanvasView()

    var body: some View {
        NavigationStack {
            CanvasRepresentable(canvas: canvas)
                .background(Color.white)
                .navigationTitle(L("手書き", "Sketch"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("キャンセル", "Cancel")) { onDone(nil) } }
                    ToolbarItem(placement: .principal) {
                        Button { canvas.drawing = PKDrawing() } label: { Image(systemName: "trash") }
                            .accessibilityLabel(L("消す", "Clear"))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("添付する", "Attach")) { onDone(render()) }
                    }
                }
        }
    }

    /// 白い背景に描いた部分を画像にする
    private func render() -> Data? {
        let d = canvas.drawing
        guard !d.strokes.isEmpty else { return nil }
        let rect = d.bounds.insetBy(dx: -24, dy: -24)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: rect.size))
            d.image(from: rect, scale: 2).draw(in: CGRect(origin: .zero, size: rect.size))
        }
        return image.jpegData(compressionQuality: 0.85)
    }
}

private struct CanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        context.coordinator.picker = picker
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var picker: PKToolPicker?
    }
}
#endif
