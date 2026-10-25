# Mindrawer の Web 版

`index.html` 1 枚で動く。GitHub Pages（`.github/workflows/pages.yml`）で https://yusuke827827.github.io/hikidashi/ に公開する。

- メモはブラウザの中（localStorage）に保存する。書き出し・読み込みのファイルは iOS 版と同じ形
- 右上の「AI を使う」から自分の Anthropic API キーを入れると、Claude が整理と取り出しをする（キーはそのブラウザにだけ保存され、Anthropic にだけ送られる）。キーが無ければ簡易の整理とキーワード検索
- claude.ai の Artifact として開いたときは、claude.ai のアカウントへの保存と AI を使う
