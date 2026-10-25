// メモを 1 枚の画像カードにして共有する（X などに貼れる）。カードの隅にアプリ名を入れる。

#if os(iOS)
import HikidashiKit
import SwiftUI
import UIKit

struct ShareCardView: View {
    let note: Note
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(note.category.isEmpty ? Heuristics.otherFolder : note.category)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.accent)
            Text(note.title)
                .font(Fonts.mincho(26))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(excerpt(of: note))
                .font(.system(size: 16))
                .foregroundStyle(palette.text.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if !note.situations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("こんなときに", "Handy when"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.muted)
                    ForEach(note.situations.prefix(3), id: \.self) { s in
                        Text("・" + s).font(.system(size: 14)).foregroundStyle(palette.text)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Mindrawer").font(Fonts.mincho(17)).foregroundStyle(palette.text)
                Text("引出").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(palette.accent)
                Spacer()
                Text(L("Tips をしまって、必要なときに", "Save tips. Get them back when it matters."))
                    .font(.system(size: 10))
                    .foregroundStyle(palette.muted)
            }
        }
        .padding(28)
        .frame(width: 360, height: 450, alignment: .topLeading)
        .background(
            LinearGradient(colors: [palette.bg, palette.surface2], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(alignment: .top) { Rectangle().fill(palette.accent).frame(height: 6) }
    }

    private func excerpt(of n: Note) -> String {
        let s = n.summary.isEmpty ? n.text : n.summary
        return s.count > 180 ? String(s.prefix(180)) + "…" : s
    }
}

@MainActor
enum ShareCard {
    static func image(for note: Note, palette: Palette) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(note: note, palette: palette))
        renderer.scale = 3
        return renderer.uiImage
    }
}

struct SharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 共有シート（UIActivityViewController）
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
