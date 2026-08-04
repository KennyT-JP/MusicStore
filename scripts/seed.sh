#!/usr/bin/env bash
# 動作確認用のデータをエミュレータに入れる
#
#   ./scripts/seed.sh
#
# エミュレータが起動している状態で実行してください。
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -d node_modules ]; then
  npm install
fi

export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080

exec node seed-emulator.js
