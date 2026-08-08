#!/usr/bin/env bash
# 配信前の検証を、全部まとめて並列に実行する
#
#   ./scripts/check.sh
#
# 中身は check.mjs にある。Windows と共通の 1 本にまとめてあるので、
# 直すときはそちらを編集してください。
set -euo pipefail
exec node "$(dirname "$0")/check.mjs" "$@"
