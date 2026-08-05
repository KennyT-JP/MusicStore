#!/usr/bin/env bash
# エミュレータを起動する（仕様書 12.6）
#
#   ./scripts/dev-emulators.sh
#
# 中身は dev-emulators.mjs にある。Windows と共通の 1 本にまとめてあるので、
# 直すときはそちらを編集してください。理由はそのファイルの冒頭に書いてあります。
set -euo pipefail
exec node "$(dirname "$0")/dev-emulators.mjs" "$@"
