#!/usr/bin/env bash
# GitHub Actions から中継サーバーを Cloudflare に公開する（.github/workflows/server.yml）。
# 必要な環境変数: CLOUDFLARE_API_TOKEN（と、アカウントが複数あるなら CLOUDFLARE_ACCOUNT_ID）。
# ANTHROPIC_API_KEY があれば、サーバーの秘密の値として登録する。BUNDLE_PREFIX があれば Bundle ID と商品 ID をそれに合わせる。
# 利用回数を数える保存場所（KV「mindrawer-usage」）が無ければ作る。
set -euo pipefail
cd "$(dirname "$0")/.."

KV_TITLE=mindrawer-usage
find_kv() {
  npx wrangler kv namespace list 2>/dev/null | node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      const list = JSON.parse(s.slice(s.indexOf("[")));
      const hit = list.find(n => n.title === process.argv[1]);
      if (hit) console.log(hit.id);
    });' "$KV_TITLE"
}

id=$(find_kv)
if [ -z "$id" ]; then
  echo "KV「$KV_TITLE」を作ります"
  npx wrangler kv namespace create "$KV_TITLE" >/dev/null
  id=$(find_kv)
fi
[ -n "$id" ] || { echo "KV の id が取れませんでした" >&2; exit 1; }
sed -i "s/REPLACE_WITH_KV_NAMESPACE_ID/$id/" wrangler.toml

node scripts/build-pages.mjs
# Bundle ID を GitHub の Variables（BUNDLE_PREFIX）で決めていれば、それに合わせる
vars=()
if [ -n "${BUNDLE_PREFIX:-}" ]; then
  vars=(--var "BUNDLE_ID:$BUNDLE_PREFIX" --var "PRODUCT_IDS:$BUNDLE_PREFIX.plus.monthly")
fi
npx wrangler deploy "${vars[@]}" | tee /tmp/deploy.log

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  printf '%s' "$ANTHROPIC_API_KEY" | npx wrangler secret put ANTHROPIC_API_KEY >/dev/null
  echo "ANTHROPIC_API_KEY を登録しました"
fi

url=$(grep -oE 'https://[a-zA-Z0-9.-]+\.workers\.dev' /tmp/deploy.log | head -1)
[ -n "$url" ] || { echo "公開した URL が見つかりませんでした" >&2; exit 1; }
curl -fsS "$url/health" >/dev/null
echo "url=$url" >> "${GITHUB_OUTPUT:-/dev/null}"
{
  echo "## 中継サーバーを公開しました"
  echo
  echo "| 用途 | URL |"
  echo "|---|---|"
  echo "| \`App/project.yml\` の \`SERVER_URL\` | $url |"
  echo "| プライバシーポリシー（\`PRIVACY_URL\`・App Store Connect） | $url/privacy |"
  echo "| サポート URL（App Store Connect） | $url/support |"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
