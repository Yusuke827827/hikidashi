#!/usr/bin/env bash
# App Store Connect にアプリを送る（TestFlight と App Store 提出用）。Mac が無くても GitHub Actions から動かせる。
# .github/workflows/release.yml から呼ぶ。手順は docs/release.md。
#
# 必要な環境変数:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8   App Store Connect API キー（役割は Admin）
#   APPLE_TEAM_ID                           Apple Developer のチーム ID（10 文字）
#   BUNDLE_PREFIX                           Bundle ID（例: com.yourname.mindrawer）
#   SERVER_URL, PRIVACY_URL                 中継サーバーの URL と /privacy（空なら Plus は出ない）
#   BUILD_NUMBER                            ビルド番号（毎回増やす）
#   UPLOAD                                  true なら App Store Connect に送る。false ならビルドだけ
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?ASC_KEY_ID が未設定です}" "${ASC_ISSUER_ID:?ASC_ISSUER_ID が未設定です}" "${ASC_KEY_P8:?ASC_KEY_P8 が未設定です}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID が未設定です}" "${BUNDLE_PREFIX:?BUNDLE_PREFIX が未設定です}"
BUILD_NUMBER=${BUILD_NUMBER:-1}
UPLOAD=${UPLOAD:-true}
WORK=${RUNNER_TEMP:-$(mktemp -d)}

KEY="$WORK/AuthKey_$ASC_KEY_ID.p8"
printf '%s\n' "$ASC_KEY_P8" > "$KEY"
AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

(cd App && xcodegen generate)

echo "▶ アーカイブを作ります（Bundle ID: $BUNDLE_PREFIX, ビルド番号: $BUILD_NUMBER）"
xcodebuild archive \
  -project App/Hikidashi.xcodeproj -scheme Hikidashi \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$WORK/Mindrawer.xcarchive" \
  "${AUTH[@]}" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  BUNDLE_PREFIX="$BUNDLE_PREFIX" \
  APP_GROUP="group.$BUNDLE_PREFIX" \
  SERVER_URL="${SERVER_URL:-}" \
  PRIVACY_URL="${PRIVACY_URL:-}" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  | tail -n 40

DEST=export
[ "$UPLOAD" = "true" ] && DEST=upload
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DEST</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "▶ 書き出します（$DEST）"
xcodebuild -exportArchive \
  -archivePath "$WORK/Mindrawer.xcarchive" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/export" \
  "${AUTH[@]}"

rm -f "$KEY"
if [ "$UPLOAD" = "true" ]; then
  echo "✅ App Store Connect に送りました。10〜30 分ほどで TestFlight に出ます。"
else
  echo "✅ ビルドできました（送ってはいません）。"
fi
