// フォルダの色と印（SF Symbols）。メモのカード・フォルダの列・フォルダの管理で使う。

#if os(iOS)
import HikidashiKit
import SwiftUI

enum Looks {
    static func color(_ i: Int) -> Color {
        let hex = UInt32(Heuristics.folderColors[min(max(i, 0), Heuristics.folderColors.count - 1)], radix: 16) ?? 0xC8553D
        return Color(hex: hex)
    }

    static func symbol(_ icon: String) -> String {
        switch icon {
        case "home": return "house"
        case "food": return "fork.knife"
        case "money": return "yensign.circle"
        case "heart": return "heart"
        case "laptop": return "laptopcomputer"
        case "work": return "briefcase"
        case "plane": return "airplane"
        case "cart": return "cart"
        case "users": return "person.2"
        case "paw": return "pawprint"
        case "music": return "music.note"
        case "sparkle": return "sparkles"
        case "doc": return "doc.text"
        case "target": return "target"
        case "bulb": return "lightbulb"
        case "star": return "star"
        default: return "folder"
        }
    }
}

/// フォルダの印（色つきの角丸の中にアイコン）
struct FolderBadge: View {
    let name: String
    let store: NoteStore
    var size: CGFloat = 22

    var body: some View {
        let look = store.folderLook(name)
        let c = Looks.color(look.color)
        Image(systemName: Looks.symbol(look.icon))
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(c)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3).fill(c.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

/// フォルダの色と印を選ぶ
struct FolderLookPicker: View {
    let name: String
    let store: NoteStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let look = store.folderLook(name)
        NavigationStack {
            Form {
                Section(L("色", "Color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(Heuristics.folderColors.indices, id: \.self) { i in
                            Button { store.setFolderLook(name, color: i) } label: {
                                Circle().fill(Looks.color(i)).frame(width: 34, height: 34)
                                    .overlay { if look.color == i { Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white) } }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("色 \(i + 1)", "Color \(i + 1)"))
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section(L("アイコン", "Icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Heuristics.folderIcons, id: \.self) { k in
                            Button { store.setFolderLook(name, icon: k) } label: {
                                Image(systemName: Looks.symbol(k))
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(Looks.color(look.color))
                                    .background(RoundedRectangle(cornerRadius: 12).fill(look.icon == k ? Looks.color(look.color).opacity(0.16) : Color.clear))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(look.icon == k ? Looks.color(look.color) : Color.secondary.opacity(0.25)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(k)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("完了", "Done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
