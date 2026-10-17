# Hikidashi（引出）

X や日常で見つけた Tips・備忘録をしまっておき、必要なときに取り出す iOS アプリです。

- **共有シートから保存**：X・Safari・写真などで「共有 → Hikidashi」を選ぶと保存できます。ひとこと書き足すこともできます。
- **AI が整理**：Claude がタイトル・要約・フォルダ・使う場面・タグを付けます。日付が書いてあればリマインドにも入ります。スクショは文字を読み取ります。
- **ひきだす**：「これから洗濯する」「プレゼン前に緊張する」のように、行動・困りごと・質問を書くと、役立つメモを選んで短い助言と一緒に出します。
- **フォルダ**：分類別と月別を切り替えられます。ピン留め、「役立った」、関連メモ、今日のひとつ、絞り込みもあります。
- **編集・声で入力**：すべての項目を直せます。マイクボタンで話した内容を文字にできます。
- **壁紙**：Flowa と同じ和紙・羊皮紙・セピア・夜空・オーロラに加え、朝焼け・桜・海・森・夕暮れ。
- **Web 版とデータをやりとり**：claude.ai の Hikidashi で書き出した JSON を読み込めます。逆も同じです。

API キーが無くても、簡易の整理（キーワードでのフォルダ分け）とキーワード検索で使えます。

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

1. `App/project.yml` の `BUNDLE_PREFIX` と `APP_GROUP` を自分のものに変える（例: `com.yourname.hikidashi` と `group.com.yourname.hikidashi`）。
2. `xcodegen generate` をやり直す。
3. Xcode で両方のターゲットに App Groups の機能があり、同じグループが選ばれていることを確認する。
4. iPhone をつないで実行する。

### 画面写真

```sh
scripts/screenshots.sh   # screenshots/ に PNG ができる
```

シミュレーターでアプリを見本モード（`-HikidashiDemo`。一時フォルダに見本のメモを入れて起動し、本物のメモには触れない）で開き、壁紙・明暗・言語を変えて撮ります。GitHub Actions でも push のたびに撮り、実行結果の成果物「screenshots」から取り出せます。

### テスト

```sh
cd HikidashiCore && swift test
```

GitHub Actions（`.github/workflows/ios.yml`）でも、push のたびにテストとシミュレーター向けビルドを行います。
