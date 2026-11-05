// 初めて開いたときの案内。3 枚だけ（しまう・ひきだす・今日）。ほかの機能は「今日」のヒントで少しずつ。

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

    /// 最初は 3 つだけ（しまう・ひきだす・今日）。ほかの機能は、慣れてきたら「今日」のヒントで 1 つずつ紹介する
    private var pages: [Page] {
        [
            Page(icon: "tray.and.arrow.down",
                 title: L("しまう", "Save"),
                 body: L("Tips・スクショ・リンク・備忘録を、思いついたら上の欄に入れて「しまう」。共有ボタンからも入れられます。AI がフォルダやタグを付けます。",
                         "Drop tips, screenshots, links or notes to self in the box and tap Save, or use the share sheet. AI adds folders and tags.")),
            Page(icon: "magnifyingglass",
                 title: L("ひきだす", "Recall"),
                 body: L("「これから◯◯する」「◯◯で困っている」と書くと、役立つメモが出てきます。言葉が違っても大丈夫です。",
                         "Write what you're about to do or what's bugging you, and the notes that help come back, even with different words.")),
            Page(icon: "sun.max",
                 title: L("今日", "Today"),
                 body: L("その日に見るメモ・やること・今日のひとつが並びます。ほかの機能は、使っていくうちに少しずつ紹介します。",
                         "Today shows what's due, your to-dos and a daily pick. Other features are introduced bit by bit as you go.")),
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
