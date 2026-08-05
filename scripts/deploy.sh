#!/usr/bin/env bash
# クラウドの Firebase プロジェクトへデプロイする（仕様書 12.2）
#
#   ./scripts/deploy.sh        検証環境
#   ./scripts/deploy.sh prod   本番環境
#
# 中身は deploy.mjs にある。Windows と共通の 1 本にまとめてあるので、
# 直すときはそちらを編集してください。
set -euo pipefail
exec node "$(dirname "$0")/deploy.mjs" "$@"
