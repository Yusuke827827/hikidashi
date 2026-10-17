// 見た目。配色と壁紙は Flowa（jp-speed-reader）と同じ値を使う。
//   標準: 生成りの紙色と朱色（端末のダークモードに合わせる）
//   朝焼け・桜・海・和紙・羊皮紙・セピア（明るい）、森・夕暮れ・夜空・オーロラ（暗い）:
//   壁紙ごとに配色を切り替え、カードは半透明にする

#if os(iOS)
import SwiftUI
import HikidashiKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

public enum Wallpaper: String, CaseIterable, Identifiable, Sendable {
    case plain, dawn, sakura, sea, washi, parchment, sepia, forest, dusk, night, aurora

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .plain: return L("標準", "Plain")
        case .dawn: return L("朝焼け", "Dawn")
        case .sakura: return L("桜", "Sakura")
        case .sea: return L("海", "Sea")
        case .forest: return L("森", "Forest")
        case .dusk: return L("夕暮れ", "Dusk")
        case .washi: return L("和紙", "Washi")
        case .parchment: return L("羊皮紙", "Parchment")
        case .sepia: return L("セピア", "Sepia")
        case .night: return L("夜空", "Night sky")
        case .aurora: return L("オーロラ", "Aurora")
        }
    }

    /// 壁紙が決める明暗（標準は端末に合わせる）
    var scheme: ColorScheme? {
        switch self {
        case .plain: return nil
        case .night, .aurora, .forest, .dusk: return .dark
        case .washi, .parchment, .sepia, .dawn, .sakura, .sea: return .light
        }
    }
}

struct Palette: Sendable {
    var bg: Color
    var surface: Color
    var surface2: Color
    var text: Color
    var muted: Color
    var line: Color
    var accent: Color
    var accentText: Color
    /// カードを半透明にしてすりガラスを重ねるか（模様のある壁紙のとき）
    var translucent: Bool

    var accentSoft: Color { accent.opacity(0.12) }

    static func make(_ w: Wallpaper, scheme: ColorScheme) -> Palette {
        switch w {
        case .plain:
            return scheme == .dark
                ? Palette(bg: Color(hex: 0x17181B), surface: Color(hex: 0x212226), surface2: Color(hex: 0x2A2B30), text: Color(hex: 0xECEBE7),
                          muted: Color(hex: 0x9B9A95), line: Color(hex: 0x34353A), accent: Color(hex: 0xE0745A), accentText: Color(hex: 0x1A0D08), translucent: false)
                : Palette(bg: Color(hex: 0xF6F5F2), surface: .white, surface2: Color(hex: 0xEFEDE8), text: Color(hex: 0x1C1C1E),
                          muted: Color(hex: 0x6B6A66), line: Color(hex: 0xE2DFD8), accent: Color(hex: 0xC8553D), accentText: .white, translucent: false)
        case .dawn, .sakura, .sea:
            // 明るい壁紙: 白いすりガラスのカードに濃い文字
            let accent: UInt32 = w == .sea ? 0x1F6E8C : (w == .sakura ? 0xC2456A : 0xC8553D)
            let bg: UInt32 = w == .sea ? 0xBFE0EA : (w == .sakura ? 0xFBEFF2 : 0xF6D5BF)
            return Palette(bg: Color(hex: bg), surface: Color.white.opacity(0.7), surface2: Color(hex: 0x1C1C1E, alpha: 0.06),
                           text: Color(hex: 0x1C1C1E), muted: Color(hex: 0x55565C), line: Color(hex: 0x1C1C1E, alpha: 0.12),
                           accent: Color(hex: accent), accentText: .white, translucent: true)
        case .forest, .dusk:
            return Palette(bg: Color(hex: w == .forest ? 0x1F3327 : 0x2F2752), surface: Color(hex: 0x14181A, alpha: 0.5), surface2: Color.white.opacity(0.08),
                           text: Color(hex: 0xF2EFE8), muted: Color(hex: 0xB9B6AE), line: Color.white.opacity(0.14),
                           accent: Color(hex: w == .forest ? 0xD9C27A : 0xF2B27C), accentText: Color(hex: 0x1A1406), translucent: true)
        case .night, .aurora:
            return Palette(bg: Color(hex: w == .night ? 0x0B1430 : 0x07080D), surface: Color(hex: 0x141828, alpha: 0.55), surface2: Color.white.opacity(0.08),
                           text: Color(hex: 0xEEEBE4), muted: Color(hex: 0xA7A6B4), line: Color.white.opacity(0.12),
                           accent: Color(hex: w == .night ? 0xE9AE4C : 0x8EA4FF), accentText: Color(hex: w == .night ? 0x1A1406 : 0x0B0D1A), translucent: true)
        case .washi, .parchment, .sepia:
            let text: UInt32 = w == .parchment ? 0x34250F : (w == .sepia ? 0x3B2F1E : 0x22201B)
            let muted: UInt32 = w == .parchment ? 0x6E5634 : 0x6D655A
            let accent: UInt32 = w == .parchment ? 0x8A3B1C : (w == .sepia ? 0xB5482F : 0xB0402A)
            let bg: UInt32 = w == .parchment ? 0xE8D6A8 : (w == .sepia ? 0xF1E7D0 : 0xEEE7D8)
            return Palette(bg: Color(hex: bg), surface: Color(hex: 0xFFFCF4, alpha: 0.6), surface2: Color(hex: 0x503C1E, alpha: 0.07),
                           text: Color(hex: text), muted: Color(hex: muted), line: Color(hex: 0x3C2D14, alpha: 0.16),
                           accent: Color(hex: accent), accentText: .white, translucent: true)
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.make(.plain, scheme: .light)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

enum Fonts {
    /// アプリ名・見出し用の明朝（ヒラギノ明朝）
    static func mincho(_ size: CGFloat) -> Font { .custom("HiraMinProN-W6", size: size) }
}

// MARK: カード

struct CardStyle: ViewModifier {
    @Environment(\.palette) private var p
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    if p.translucent { RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial) }
                    RoundedRectangle(cornerRadius: 14).fill(p.surface)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(p.line, lineWidth: 1))
            .shadow(color: .black.opacity(p.translucent ? 0.12 : 0.05), radius: 8, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

/// 小さな札（使う場面・タグ・リマインド）
struct Chip: View {
    enum Kind { case situation, tag, remind, plain }
    @Environment(\.palette) private var p
    let text: String
    var kind: Kind = .plain

    var body: some View {
        Text(kind == .tag ? "#" + text : text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(kind == .situation || kind == .remind ? p.accent : p.muted)
            .background(Capsule().fill(kind == .situation ? p.accentSoft : (kind == .remind ? Color.clear : p.surface2)))
            .overlay { if kind == .remind { Capsule().stroke(p.accent, lineWidth: 1) } }
    }
}

/// 主ボタン（朱色）
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .foregroundStyle(p.accentText)
            .background(RoundedRectangle(cornerRadius: 12).fill(p.accent))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

// MARK: 壁紙

/// 決まった並びの乱数（星や和紙の繊維を毎回同じ位置に描くため）
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

struct WallpaperBackground: View {
    let wallpaper: Wallpaper
    let palette: Palette

    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height)
            ZStack {
                switch wallpaper {
                case .plain:
                    palette.bg
                case .sepia:
                    Color(hex: 0xF1E7D0)
                case .dawn:
                    LinearGradient(colors: [Color(hex: 0xF6D5BF), Color(hex: 0xE9C9D3), Color(hex: 0xBCCBE6), Color(hex: 0x93A9CF)],
                                   startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1))
                case .sakura:
                    LinearGradient(colors: [Color(hex: 0xFBEFF2), Color(hex: 0xF1DFE6)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color(hex: 0xF7C9D4), .clear], center: UnitPoint(x: 0.8, y: 0.1), startRadius: 0, endRadius: r * 0.5)
                    RadialGradient(colors: [Color(hex: 0xF3D6DE), .clear], center: UnitPoint(x: 0.1, y: 0.9), startRadius: 0, endRadius: r * 0.45)
                case .sea:
                    LinearGradient(colors: [Color(hex: 0xBFE0EA), Color(hex: 0x6FA9C2), Color(hex: 0x23566F)], startPoint: .top, endPoint: .bottom)
                case .forest:
                    RadialGradient(colors: [Color(hex: 0x8FAE86), Color(hex: 0x4D6E52), Color(hex: 0x1F3327)],
                                   center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: r * 1.1)
                case .dusk:
                    // 下端まで暗めに保ち、明るい文字が読めるようにする
                    LinearGradient(colors: [Color(hex: 0x2F2752), Color(hex: 0x5A3763), Color(hex: 0x8E4A62), Color(hex: 0xA85A58)],
                                   startPoint: UnitPoint(x: 0.6, y: 0), endPoint: UnitPoint(x: 0.4, y: 1))
                case .washi:
                    RadialGradient(colors: [Color(hex: 0xF4EFE3), Color(hex: 0xEBE3D1), Color(hex: 0xDDD2BB)],
                                   center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: r * 0.8)
                    Canvas { ctx, size in
                        var rng = SeededRandom(seed: 7)
                        for _ in 0..<Int(size.width * size.height / 900) {
                            let x = rng.next() * size.width, y = rng.next() * size.height
                            let w = 20 + rng.next() * 90
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: y))
                            path.addLine(to: CGPoint(x: x + w, y: y + (rng.next() - 0.5) * 3))
                            ctx.stroke(path, with: .color(Color(hex: 0x73664C, alpha: 0.05 + rng.next() * 0.06)), lineWidth: 0.6)
                        }
                    }
                case .parchment:
                    RadialGradient(colors: [Color(hex: 0xF4E6C0), Color(hex: 0xE9D5A1), Color(hex: 0xD2B071), Color(hex: 0x9C6E35)],
                                   center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: r * 0.75)
                case .night:
                    RadialGradient(colors: [Color(hex: 0x23407A), Color(hex: 0x0F1C42), Color(hex: 0x070B1C)],
                                   center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: r * 0.9)
                    Canvas { ctx, size in
                        var rng = SeededRandom(seed: 42)
                        for _ in 0..<Int(size.width * size.height / 2600) {
                            let d = 0.6 + rng.next() * 1.8
                            let rect = CGRect(x: rng.next() * size.width, y: rng.next() * size.height, width: d, height: d)
                            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35 + rng.next() * 0.5)))
                        }
                    }
                case .aurora:
                    Color(hex: 0x07080D)
                    RadialGradient(colors: [Color(red: 84 / 255, green: 120 / 255, blue: 1, opacity: 0.34), .clear],
                                   center: UnitPoint(x: 0.18, y: 0.18), startRadius: 0, endRadius: r * 0.42)
                    RadialGradient(colors: [Color(red: 176 / 255, green: 92 / 255, blue: 1, opacity: 0.28), .clear],
                                   center: UnitPoint(x: 0.85, y: 0.28), startRadius: 0, endRadius: r * 0.48)
                    RadialGradient(colors: [Color(red: 40 / 255, green: 200 / 255, blue: 180 / 255, opacity: 0.2), .clear],
                                   center: UnitPoint(x: 0.45, y: 0.95), startRadius: 0, endRadius: r * 0.52)
                }
            }
        }
        .ignoresSafeArea()
    }
}
#endif
