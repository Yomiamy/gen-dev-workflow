#!/usr/bin/env bash
# 跑完所有可自動化的測試（層 1 狀態機 + 層 2 hook 純函式）。
# 層 3 端到端是手動冒煙測試，見 examples/sandbox/README.md。
set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RC=0

echo "### 層 1：wf-state.sh 狀態機"
"$DIR/test_wf_state.sh" || RC=1
echo
echo "### 層 2：wf-guard-delegate-cwd.sh 純函式"
python3 "$DIR/test_delegate_cwd_logic.py" || RC=1

echo
[ "$RC" -eq 0 ] && echo "==> 全部通過" || echo "==> 有測試失敗" >&2
exit "$RC"
