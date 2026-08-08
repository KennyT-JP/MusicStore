#!/usr/bin/env bash
# 手順書にある検証を、まとめて全部実行する（CLAUDE.md / 仕様書 12.6）
#
#   ./scripts/test-all.sh
#
# 中身は test-all.mjs にある。Windows と共通の 1 本にまとめてあるので、
# 直すときはそちらを編集してください。理由はそのファイルの冒頭に書いてあります。
set -euo pipefail
exec node "$(dirname "$0")/test-all.mjs" "$@"
