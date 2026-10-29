// 初めて開いたときの案内。4 枚で、しまい方・整理・取り出し・始め方を見せる。

#if os(iOS)
import HikidashiKit
import SwiftUI

struct OnboardingView: View {
    var onFinish: (_ addExamples: Bool) -> Void

    @Environment(\.palette) private var p
    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let body: String
    }

    private var pages: [Page] {
        [
            Page(icon: "tray.and.arrow.down",
                 title: L("しまっておけば、\n必要なときに出てくる", "Save it once.\nIt finds you when it matters."),
                 body: L("X で見つけた Tips、スクショ、自分用の備忘録。思いついたら、とりあえずここにしまってください。",
                         "Tips from X, screenshots, notes to self. Whenever you find something useful, just drop it here.")),
            Page(icon: "square.and.arrow.up",
                 title: L("共有ボタンから一発で", "Straight from the share sheet"),
                 body: L("X・Safari・写真などで共有ボタンを押し、「Mindrawer」を選ぶだけ。出てこないときは、アプリの列の右端「その他」から Mindrawer をオンにしてください。",
                         "Tap Share in X, Safari, Photos and more, and pick Mindrawer. If it isn't listed, scroll the app row to More and turn Mindrawer on.")),
            Page(icon: "sparkles",
                 title: L("AI が整理して、\n使う場面を覚えておく", "AI files it and remembers\nwhen it helps"),
                 body: L("フォルダ・タグ・「役立つ場面」を AI が付けます。写真や PDF の文字も読み取ります。",
                         "AI adds folders, tags and the moments a note will help. It reads text in photos and PDFs too.")),
            Page(icon: "magnifyingglass",
                 title: L("「これから◯◯する」で\n取り出す", "Say what you're about to do"),
                 body: L("「ひきだす」に、これからすることや困りごとを書くと、役立つメモが出てきます。予定や通知でも、向こうから知らせます。",
                         "Type what you're about to do or what's bugging you in Recall, and the helpful notes appear. Events and notifications bring them to you, too.")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: pages[i].icon)
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(p.accent)
                        Text(pages[i].title)
                            .font(Fonts.mincho(26))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(p.text)
                        Text(pages[i].body)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(p.muted)
                            .padding(.horizontal, 28)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                if page < pages.count - 1 {
                    Button(L("次へ", "Next")) { withAnimation { page += 1 } }
                        .buttonStyle(PrimaryButtonStyle())
                    Button(L("スキップ", "Skip")) { onFinish(false) }
                        .font(.subheadline)
                        .foregroundStyle(p.muted)
                } else {
                    Button(L("見本のメモを入れて始める", "Start with 3 examples")) { onFinish(true) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button(L("空のまま始める", "Start empty")) { onFinish(false) }
                        .font(.subheadline)
                        .foregroundStyle(p.muted)
                }
            }
            .padding(.bottom, 28)
        }
        .background(p.bg.ignoresSafeArea())
    }
}
#endif
