# gen-dev-workflow

從需求到 PR 的完整開發流程編排器，以 Claude Code plugin 形式發布。

一句話：**你說「幫我做 X 功能」，它自動驅動 planner → implementer → verifier → reviewer → publisher 跑完整個週期，只在關鍵決策點停下來問你。**

暫停點不靠自律，靠 `wf-state.sh` 的狀態機棘輪強制——未經確認就想推進階段，腳本直接拒絕。

## 安裝

```bash
/plugin marketplace add Yomiamy/gen-dev-workflow
/plugin install gen-dev-workflow
```

開發中要測本機修改，改用本機路徑：

```bash
/plugin marketplace add /Users/yomiry/AiWorkspace/gen-dev-workflow
```

安裝後 hook 由 `hooks/hooks.json` 自動掛載，**不需要**手動寫進 `settings.json`。

## 相依

| 相依 | 必要性 | 說明 |
|:---|:---|:---|
| `jq` | **必要** | `wf-state.sh` 的 JSON 讀寫全靠它 |
| `gh` CLI | STAGE 1／4 必要 | 建 issue 與 PR |
| `git` ≥ 2.5 | 必要 | worktree 支援 |
| `gemini-mcp-tool` | 選用 | 委派用；未裝時退回主對話自行執行 |

## 內容

```
skills/gen-dev-workflow/     主體：SKILL.md + 8 份 references + wf-state.sh
skills/（其餘 15 個）         配套：gen-pr / gen-commit / gen-gh-issue /
                             ticket-id-dev-prep / worktree-close-cleanup 等
agents/                      7 個角色：planner / implementer / verifier /
                             reviewer / publisher / brancher / responder
hooks/                       stage-check（棘輪強制）＋ delegate-cwd（委派越界防護）
tests/                       層 1 狀態機 + 層 2 hook 純函式
examples/sandbox/            層 3 端到端冒煙測試用的假專案
```

## 測試

```bash
./tests/run-all.sh          # 層 1 + 層 2，約 2 秒
```

三層策略：

| 層 | 對象 | 自動化 |
|:--|:--|:--|
| 1 | `wf-state.sh` 狀態機不變式（棘輪、非法轉移、pause_level、批次游標） | ✅ 35 項斷言 |
| 2 | hook 純函式（白名單、路徑判定、diff 計算） | ✅ |
| 3 | 端到端接線（skill 載入、agent 派發、hook 攔截） | ❌ 手動，見 `examples/sandbox/README.md` |

層 3 不自動化是刻意的：被測對象是 Claude 讀完 SKILL.md 後的行為，
偽造整套環境的成本遠超被測價值。改完流程手動跑一次 quick 模式即可。

## 使用

```
/gen-dev-workflow 幫我做 X 功能          # 完整流程
/gen-dev-workflow quick 修正 Y           # 快速通道，單暫停點、不建 worktree
/gen-dev-workflow 開發 issue #42         # 跳過規劃，直接進 STAGE 1
/gen-dev-workflow batch A B C            # 批次，各自 worktree/branch/PR
```

暫停頻率用 `pause_level` 調：`strict`（預設，全停）／`balanced`（只停計畫、實作完成、PR 前）／`autonomous`（全不停，會讓 `gh pr create` 免確認執行，選前必須先警示）。

完整指令清單見 `skills/gen-dev-workflow/references/command-cheatsheet.md`。

## 狀態檔放哪

腳本在 plugin 目錄，**狀態在你的專案**——兩者刻意分離：

- 狀態檔：當前工作目錄的 `.claude/workflow-state/`（可用 `WF_STATE_DIR` 覆寫）
- worktree：當前 repo 的 `.claude/worktrees/`

STAGE 1 之後每個 workflow 在自己的 worktree 裡，state 檔天然隔離，同一 repo 可並行多條 workflow。
