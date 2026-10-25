# Mindrawer（頭の引き出し）

> 名前は mind（頭）と drawer（引き出し）を合わせた造語。リポジトリ名やプログラム内部の名前（HikidashiCore など）は旧名の Hikidashi のまま。

X や日常で見つけた Tips・備忘録をしまっておき、必要なときに取り出す iOS アプリです。

- **共有シートから保存**：X・Safari・写真などで「共有 → Mindrawer」を選ぶと保存できます。ひとこと書き足すこともできます。
- **AI が整理**：Claude がタイトル・要約・フォルダ・使う場面・タグを付けます。日付が書いてあればリマインドにも入ります。スクショは文字を読み取ります。
- **ひきだす**：「これから洗濯する」「プレゼン前に緊張する」のように、行動・困りごと・質問を書くと、役立つメモを選んで短い助言と一緒に出します。
- **フォルダ**：分類別と月別を切り替えられます。ピン留め、「役立った」、関連メモ、今日のひとつ、絞り込みもあります。
- **リマインド通知**：リマインド日の朝 9 時に通知が届き、押すとそのメモが開きます（端末の中だけで動き、サーバーは使いません）。
- **編集・声で入力**：すべての項目を直せます。マイクボタンで話した内容を文字にできます。
- **壁紙**：Flowa と同じ和紙・羊皮紙・セピア・夜空・オーロラに加え、朝焼け・桜・海・森・夕暮れ。
- **Web 版とデータをやりとり**：claude.ai の Mindrawer で書き出した JSON を読み込めます。逆も同じです。

API キーが無くても、簡易の整理（キーワードでのフォルダ分け）とキーワード検索で使えます。

## 販売（Mindrawer Plus）

月額の購読をした人は、API キーなしで AI を使える。アプリは購読の証明を付けて中継サーバー（`server/`、Cloudflare Workers）に送り、サーバーが証明を確かめてから運営側のキーで Claude を呼ぶ。`App/project.yml` の `SERVER_URL` が空のあいだは購読の機能は出ない。公開の手順は `server/README.md`。

## 構成

```
HikidashiCore/            Swift Package
  Sources/HikidashiKit/   画面に依存しない処理（保存、共有シートの受け口、Claude 呼び出し）
  Sources/HikidashiUI/    SwiftUI の画面
  Tests/                  swift test で動くテスト
App/
  project.yml             XcodeGen の設定（アプリ本体と共有シートの拡張機能）
  Sources/                アプリ本体の入口
  ShareExtension/         共有シートの拡張機能
```

共有シートの拡張機能は、受け取ったものを App Group の `Inbox/` に置くだけです。整理（Claude の呼び出し）は、アプリ本体を開いたときにまとめて行います。

## Claude の使い方

- モデル: `claude-opus-5-5`。整理は effort `low`、取り出しは `medium`。
- 返事の形は JSON スキーマ（`output_config.format`）で決めています。
- 安全のための判定で断られたときに別のモデルで続ける設定（`fallbacks: "default"`）を入れています。
- API キーは設定画面で入力し、端末のキーチェーンにだけ保存します。利用料は自分の Anthropic アカウントにかかります。

販売する場合は、API キーを持つサーバーを間に置く形に変える必要があります（利用者にキーを入れてもらう形は自分用・試用向けです）。

## ビルド

Mac で:

```sh
brew install xcodegen
cd App && xcodegen generate && open Hikidashi.xcodeproj
```

Xcode の「Signing & Capabilities」で、Hikidashi と HikidashiShare の両方に自分のチームを選びます。

### 自分の iPhone に入れる（Apple Developer Program 登録後）

共有シートの拡張機能とアプリ本体でデータを共有するため、App Group が必要です。

Mac が無い場合は、GitHub Actions から App Store Connect に送れる（`docs/release.md`）。Mac で開発する場合は次のとおり。

1. `App/project.yml` の `BUNDLE_PREFIX` と `APP_GROUP` を自分のものに変える（例: `com.yourname.mindrawer` と `group.com.yourname.mindrawer`）。
2. `xcodegen generate` をやり直す。
3. Xcode で両方のターゲットに App Groups の機能があり、同じグループが選ばれていることを確認する。
4. iPhone をつないで実行する。

### 画面写真

```sh
scripts/screenshots.sh   # screenshots/ に PNG ができる
```

シミュレーターでアプリを見本モード（`-HikidashiDemo`。一時フォルダに見本のメモを入れて起動し、本物のメモには触れない）で開き、壁紙・明暗・言語を変えて撮ります。GitHub Actions でも push のたびに撮り、実行結果の成果物「screenshots」から取り出せます。main の写真は `screenshots` ブランチにも置かれ、GitHub 上でそのまま見られます。

### App Store に出す準備

- アイコン: `App/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`（`python3 scripts/make_icon.py` で描き直せる）
- プライバシー情報: `App/Sources/PrivacyInfo.xcprivacy`（データ収集なし・追跡なし）
- プライバシーポリシー: `docs/privacy-policy.md`（日本語・英語）
- ストアの説明文と提出前チェック: `docs/app-store.md`
- ストア用の宣伝画像（見出し付き、日本語・英語 5 枚ずつ）: `python3 scripts/store_shots.py`。GitHub Actions でも毎回作り、`screenshots` ブランチの `store/` に置く

### テスト

```sh
cd HikidashiCore && swift test
```

GitHub Actions（`.github/workflows/ios.yml`）でも、push のたびにテストとシミュレーター向けビルドを行います。
