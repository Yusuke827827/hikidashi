#!/bin/bash
# iOS シミュレーターでアプリを見本モード（-HikidashiDemo）で起動し、画面写真を撮る。
# Mac で実行する。GitHub Actions の screenshots ジョブからも使う。
#
#   scripts/screenshots.sh [出力フォルダ（既定: screenshots）]
#
# 撮る画面: 標準（明・暗）、壁紙いくつか、「ひきだす」の答え、設定、英語版
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-screenshots}"
mkdir -p "$OUT"
BUNDLE_ID=app.hikidashi

# 使える iPhone のシミュレーターを 1 台選ぶ（新しい iOS を優先）
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in data if "iOS" in r), key=lambda r: [int(x) for x in r.rsplit("iOS-", 1)[-1].split("-")], reverse=True)
for r in runtimes:
    phones = [d for d in data[r] if d["name"].startswith("iPhone") and "Pro Max" not in d["name"] and "SE" not in d["name"]]
    if phones:
        print(phones[0]["udid"]); break
')
if [ -z "$UDID" ]; then echo "iPhone のシミュレーターが見つかりません" >&2; exit 1; fi
echo "simulator: $(xcrun simctl list devices | grep "$UDID")"

# ビルド（シミュレーター向け。署名は後でアドホックに付ける）
(cd App && xcodegen generate)
xcodebuild build -quiet \
  -project App/Hikidashi.xcodeproj -scheme Hikidashi \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO
APP=build/Build/Products/Debug-iphonesimulator/Hikidashi.app
for ext in "$APP"/PlugIns/*.appex; do [ -e "$ext" ] && codesign --force --sign - "$ext"; done
codesign --force --sign - "$APP"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

# shot <ファイル名> <明暗 light|dark> <言語 ja|en> [起動引数...]
shot() {
  local name=$1 appearance=$2 lang=$3
  shift 3
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  local locale=ja_JP
  [ "$lang" = en ] && locale=en_US
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -AppleLanguages "($lang)" -AppleLocale "$locale" -HikidashiDemo "$@" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  echo "saved $OUT/$name.png"
}

shot 01-plain-light   light ja -wallpaper plain
shot 02-plain-dark    dark  ja -wallpaper plain
shot 03-recall        light ja -wallpaper plain -HikidashiDemoRecall "旅行の荷造り"
shot 04-washi         light ja -wallpaper washi
shot 05-sakura        light ja -wallpaper sakura
shot 06-sea           light ja -wallpaper sea
shot 07-night         light ja -wallpaper night
shot 08-dusk          light ja -wallpaper dusk
shot 09-settings      light ja -wallpaper plain -HikidashiDemoSettings
shot 10-english       light en -wallpaper dawn

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
