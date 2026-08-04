#!/usr/bin/env bash
# エミュレータを起動する（仕様書 12.6）
#
# Functions のビルドを先に済ませてから起動する。ビルドを忘れると
# 「Failed to load function definition from source」で起動に失敗するため。
#
#   ./scripts/dev-emulators.sh
#
# 停止するときは Ctrl+C。データは毎回消える。
set -euo pipefail

cd "$(dirname "$0")/.."

# エミュレータ専用のダミープロジェクト。
# demo- で始まる ID を使うと、Firebase CLI がクラウドへ一切アクセスしなくなる。
# （firebase login も不要）
PROJECT="demo-musiclist"

echo "==> functions の依存パッケージを確認"
if [ ! -d functions/node_modules ]; then
  (cd functions && npm install)
fi

echo "==> functions をビルド"
(cd functions && npm run build)

echo "==> エミュレータを起動（プロジェクト: $PROJECT）"
echo "    管理画面: http://127.0.0.1:4000"
echo ""
echo "    別のターミナルで次を実行するとアプリが繋がります:"
echo "      flutter run -d chrome --dart-define=USE_EMULATOR=true"
echo ""

# localhost がプロキシ経由になる環境だと、エミュレータ同士の通信が失敗する。
# 念のため除外しておく。
export NO_PROXY="${NO_PROXY:-},127.0.0.1,localhost,::1"
export no_proxy="$NO_PROXY"

exec firebase emulators:start --project "$PROJECT"
