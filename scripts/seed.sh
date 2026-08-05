#!/usr/bin/env bash
# 動作確認用のデータをエミュレータに入れる
#
#   ./scripts/seed.sh
#
# 中身は seed.mjs にある。Windows と共通の 1 本にまとめてあるので、
# 直すときはそちらを編集してください。
set -euo pipefail
exec node "$(dirname "$0")/seed.mjs" "$@"
