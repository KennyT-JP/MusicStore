#!/usr/bin/env bash
# Flutter 側の Firebase 接続設定を生成する（仕様書 12.2）
#
#   ./scripts/configure-firebase.sh        検証環境
#   ./scripts/configure-firebase.sh prod   本番環境
#
# 中身は configure-firebase.mjs にある。Windows と共通の 1 本にまとめてあるので、
# 直すときはそちらを編集してください。
set -euo pipefail
exec node "$(dirname "$0")/configure-firebase.mjs" "$@"
