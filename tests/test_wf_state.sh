#!/usr/bin/env bash
# wf-state.sh 的狀態機不變式測試。
#
# 執行：tests/test_wf_state.sh
# 成功印 OK 並以 0 離開；任一斷言失敗即非零離開。
#
# 只測「改錯代價最高」的不變式：棘輪（未確認不得推進）、非法 stage 轉移、
# STAGE 3 的任務完成度閘門、pause_level 三級判定、quick+balanced 短路、
# 批次佇列游標。這些是流程的骨架，壞掉時整條 workflow 會靜默走偏。
#
# 不測：jq 輸出格式、錯誤訊息文字（會隨措辭調整）、實際跑 agent（層 3 手動）。

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF="$SCRIPT_DIR/../skills/gen-dev-workflow/scripts/wf-state.sh"

[ -x "$WF" ] || { echo "FAIL: 找不到或無法執行 $WF" >&2; exit 1; }
command -v jq >/dev/null || { echo "SKIP: 需要 jq" >&2; exit 0; }

PASS=0
FAILED=0

fail() { echo "  ✗ $1" >&2; FAILED=$((FAILED + 1)); }
ok()   { PASS=$((PASS + 1)); }

# 斷言指令成功
ok_run() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok; else fail "$desc（預期成功卻失敗）"; fi
}

# 斷言指令失敗（guard 有擋住）
no_run() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$desc（預期被拒卻通過了）"; else ok; fi
}

# 斷言 state 檔某欄位值
field_is() {
  local f="$1" expr="$2" want="$3" desc="$4"
  local got; got="$(jq -r "$expr" "$f" 2>/dev/null)"
  if [ "$got" = "$want" ]; then ok; else fail "$desc（$expr 期望 '$want'，實得 '$got'）"; fi
}

# 每個測試一個乾淨的 state dir
new_env() {
  WF_STATE_DIR="$(mktemp -d)"
  export WF_STATE_DIR
}

# 建一個位於指定 stage 的 sequence state，回傳檔案路徑。
# sequence 模式只能從 0a 初始化，因此非 0a 的目標一律沿主線推進過去。
mk_state() {
  local branch="$1" stage="${2:-0a}" level="${3:-strict}" f
  "$WF" init --mode sequence --branch "$branch" --pause-level "$level" >/dev/null
  f="$(ls "$WF_STATE_DIR"/*.json | head -1)"
  local hop
  for hop in 0b 1 2 3 4; do
    [ "$(jq -r '.stage' "$f")" = "$stage" ] && break
    "$WF" advance "$f" "$hop" --confirmed >/dev/null 2>&1
  done
  echo "$f"
}

echo "== 棘輪：未確認不得推進 =="
new_env
F="$(mk_state test-ratchet 0a)"
ok_run "stage-done 0a" "$WF" stage-done "$F" 0a
field_is "$F" '.awaiting_confirmation' true "strict 下 stage-done 應進入等待確認"
no_run "未帶 --confirmed 的 advance 應被拒" "$WF" advance "$F" 0b
field_is "$F" '.stage' "0a" "被拒後 stage 不應改變"
ok_run "帶 --confirmed 可推進" "$WF" advance "$F" 0b --confirmed
field_is "$F" '.stage' "0b" "確認後 stage 應推進"
field_is "$F" '.awaiting_confirmation' false "推進後應清除等待旗標"

echo "== 棘輪：confirm 後可不帶旗標推進 =="
new_env
F="$(mk_state test-confirm 0a)"
"$WF" stage-done "$F" 0a >/dev/null
ok_run "confirm" "$WF" confirm "$F"
field_is "$F" '.awaiting_confirmation' false "confirm 應清除等待旗標"
ok_run "confirm 後 advance 免旗標" "$WF" advance "$F" 0b

echo "== 非法 stage 轉移 =="
new_env
F="$(mk_state test-transition 0a)"
no_run "0a 直跳 2 應被拒" "$WF" advance "$F" 2 --confirmed
no_run "0a 直跳 4 應被拒" "$WF" advance "$F" 4 --confirmed
field_is "$F" '.stage' "0a" "非法轉移後 stage 不應改變"
ok_run "0a→0b 合法" "$WF" advance "$F" 0b --confirmed
ok_run "0b→1 合法" "$WF" advance "$F" 1 --confirmed
ok_run "1→2 合法" "$WF" advance "$F" 2 --confirmed
ok_run "2→3 合法" "$WF" advance "$F" 3 --confirmed
ok_run "3→2 退回合法（審查不通過）" "$WF" advance "$F" 2 --confirmed

echo "== STAGE 3 閘門：任務未做完不得推進 =="
new_env
F="$(mk_state test-gate 2)"
"$WF" set "$F" total_tasks=3 >/dev/null
"$WF" task-done "$F" 1 >/dev/null
"$WF" confirm "$F" >/dev/null
no_run "3 個任務只完成 1 個時不得進 STAGE 3" "$WF" advance "$F" 3 --confirmed
"$WF" task-done "$F" 2 >/dev/null; "$WF" confirm "$F" >/dev/null
"$WF" task-done "$F" 3 >/dev/null; "$WF" confirm "$F" >/dev/null
ok_run "全部完成後可進 STAGE 3" "$WF" advance "$F" 3 --confirmed

echo "== task-done 僅限 STAGE 2（sequence）=="
new_env
F="$(mk_state test-taskstage 1)"
no_run "STAGE 1 執行 task-done 應被拒" "$WF" task-done "$F" 1

echo "== pause_level: balanced 只停 0b/2/4 =="
new_env
F="$(mk_state test-balanced 0a balanced)"
"$WF" stage-done "$F" 0a >/dev/null
field_is "$F" '.awaiting_confirmation' false "balanced 不應停在 0a"
"$WF" advance "$F" 0b --confirmed >/dev/null
"$WF" stage-done "$F" 0b >/dev/null
field_is "$F" '.awaiting_confirmation' true "balanced 應停在 0b"

echo "== pause_level: balanced 的 task 迴圈不停 =="
new_env
F="$(mk_state test-balanced-task 2 balanced)"
"$WF" task-done "$F" 1 >/dev/null
field_is "$F" '.awaiting_confirmation' false "balanced 的任務間不應停"

echo "== pause_level: autonomous 全不停 =="
new_env
F="$(mk_state test-autonomous 0b autonomous)"
"$WF" stage-done "$F" 0b >/dev/null
field_is "$F" '.awaiting_confirmation' false "autonomous 不應停在 0b"

echo "== quick + balanced 短路回 strict =="
new_env
"$WF" init --mode quick --stage impl --branch test-quick --pause-level balanced >/dev/null
F="$(ls "$WF_STATE_DIR"/*.json | head -1)"
"$WF" stage-done "$F" impl >/dev/null
field_is "$F" '.awaiting_confirmation' true "quick+balanced 應短路回 strict（要停）"

echo "== pause_level 異常值：schema 校驗直接擋下 =="
# 注意：should_pause() 內有「異常值退回 strict」的防線，但實際上碰不到——
# validate() 的 schema 早一步拒絕非法 pause_level，整個指令失敗。
# 這比退回 strict 更嚴格（壞檔不會被靜默沿用），故斷言「被拒且不落盤」。
new_env
F="$(mk_state test-bogus 0a)"
jq '.pause_level = "bogus"' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
no_run "異常 pause_level 應被 schema 校驗拒絕" "$WF" stage-done "$F" 0a
field_is "$F" '.awaiting_confirmation' false "被拒的指令不應寫入任何變更"

echo "== init 拒絕無效 pause_level =="
new_env
no_run "init 無效 pause_level 應被拒" "$WF" init --mode sequence --branch t --pause-level bogus

echo "== 腐壞的 state 檔應立即失敗，而非靜默續接 =="
new_env
F="$WF_STATE_DIR/corrupt.json"
echo '{"schema_version":1,"stage":"0a"}' > "$F"   # 缺必要欄位
no_run "缺欄位的 state 檔應被 get 拒絕" "$WF" get "$F"
echo 'not json at all' > "$F"
no_run "非 JSON 的 state 檔應被 get 拒絕" "$WF" get "$F"

echo "== 批次佇列游標 =="
new_env
"$WF" batch-init "項目A" "項目B" >/dev/null
B="$(ls "$WF_STATE_DIR"/.batch-*.json | head -1)"
got="$("$WF" batch-next "$B" 2>/dev/null)"
[ "$got" = "項目A" ] && ok || fail "batch-next 首項應為 項目A（實得 '$got'）"
"$WF" batch-done "$B" >/dev/null 2>&1
got="$("$WF" batch-next "$B" 2>/dev/null)"
[ "$got" = "項目B" ] && ok || fail "batch-done 後應移到 項目B（實得 '$got'）"
"$WF" batch-done "$B" >/dev/null 2>&1
got="$("$WF" batch-next "$B" 2>/dev/null)"
[ "$got" = "DONE" ] && ok || fail "全部完成後應回傳 DONE（實得 '$got'）"

echo "== batch-init 拒絕無效 pause_level =="
new_env
no_run "無效 pause_level 應被拒" "$WF" batch-init "X" --pause-level bogus

echo
if [ "$FAILED" -eq 0 ]; then
  echo "OK — $PASS 項斷言全數通過"
  exit 0
else
  echo "FAILED — $FAILED 項失敗 / $((PASS + FAILED)) 項" >&2
  exit 1
fi
