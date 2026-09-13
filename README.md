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

## 編排流程

📊 **[互動式流程圖](docs/diagrams/gen-dev-workflow.html)**（在瀏覽器開啟，含 model／effort／委派標註、三組引導視圖、搜尋與匯出）

七個 stage，⏸ 是暫停點（`strict` 預設全停）。STAGE 0a→4 是主線，5／6 是獨立入口，由你手動觸發。

| Stage | 任務內容 | Agent／Skill | Model | Effort | 委派 |
|:--|:--|:--|:--|:--|:--|
| **0a** 功能規格 | 並行雙線：專案 context 收集 ／ 相似功能代碼調查，收斂後寫 `docs/features/` | planner | `opus` | `xhigh` | ❌ 不委派 |
| **0b** 實作計畫 | 資料結構、檔案異動、任務拆分，逐任務標註複雜度 → `docs/plans/` | planner | `opus` | `xhigh` | ❌ 不委派 |
| **1** Issue + Worktree | Issue body 五區段 zh-tw；依 `ticket-id-dev-prep` 規則建 worktree + branch | gen-gh-issue skill + brancher | `sonnet` | `high` | ✦ `gh issue create`、`git worktree add` |
| **2** 實作 | ≥2 獨立任務且寫入路徑不重疊 → 並行；否則序列 | implementer | `sonnet` | `max` | ✦ 代碼 + 測試 + commit |
| **2** 驗收 | 兩階段：spec compliance → code quality | verifier | `opus` | `xhigh` | ❌ 親自驗收 |
| **3** 審查 | 根因判斷，不讓產出代碼的同源 model 自審 | reviewer | `opus` | `xhigh` | ❌ 不委派 |
| **4** 發布 | `gen-pr` 產描述（Summary + 修正問題／方式），push + 建 PR | publisher + gen-pr skill | `sonnet` | `high` | ✦ Diff 分析；`gh pr create` 自己執行 |
| **5** 回覆 Review | 逐條意見判斷 → reviewer 交叉驗證 → publisher 更新 PR | responder → reviewer → publisher | `sonnet`／`opus`／`sonnet` | `high`／`xhigh`／`high` | ❌ |
| **6** 清理 Worktree | 文件回寫 → commit → 移除 worktree（**branch 一律保留**） | gen-sync-docs-by-branchs → gen-commit → worktree-close-cleanup | — | — | ❌ 主對話執行 |

### STAGE 2 的逐任務分級

implementer 不對所有任務用同一 model，讀完計畫後逐任務判定：

| 任務複雜度信號 | 委派等級 | 範例 |
|:--|:--|:--|
| 觸及 1–2 檔、規格完整、機械性 | 快／便宜（委派後端內部 fast model） | 新增 DTO 欄位、補 util function |
| 觸及多檔、需整合協調 | 標準 `sonnet`／`max` | 跨 service 串接、改既有流程 |
| 需設計判斷或廣泛 codebase 理解 | 最強推論 `opus`／`xhigh` | 重構狀態機、新增跨層架構 |

> ⚠️ **effort 必須在派發時顯式帶入。** commit `a6fcd29` 已把 `effort:` 從各 agent frontmatter 移除，子 agent 預設繼承主對話當前 effort。不帶 `effort` 參數＝上表的 stage 間差異化**不會發生**，全部落回 session 預設值。

### 不委派的硬規則

即使 MCP 委派可用也不委派：STAGE 3 審查報告（reviewer 親自判斷）、對外動作（`gh pr create`／`git push`）、commit message 生成、單一檔案 < 50 行的小修正。

### 兩個不同層級的迴圈

- **STAGE 2 內部 retry**：同 tier 失敗 2 次 → 升一級 tier 再試 1 次（最多升一次）。基礎設施錯誤（400 effort/thinking、429、5xx、連線中斷）**不計入失敗次數**——換更強的 model 對它零幫助。
- **STAGE 3 退回**：審查不通過才退回 STAGE 2 整體重做。

兩者不可混用。另有**主動中斷**：context > 150k 時依 Token Budget Gate 保存並切 session，續接時直接接回原 stage。

### 並行加速（需 opt-in）

說「ultracode」／「用 workflow」／「多 agent」才啟用，未 opt-in 一律退回序列 `Task(...)`，功能相同。只有三處適用：STAGE 0a 雙線 context 收集、STAGE 2 同批獨立任務、STAGE 3 多 angle 對抗式審查。

**絕不**把整條 orchestrator 包成單一 Workflow——Workflow 背景執行、跑完才回，中途無法問人，會摧毀上面所有暫停點。

各 stage 的底層規則見 `skills/gen-dev-workflow/references/`：`state-machine.md`、`delegation-and-parallel.md`、`branch-worktree-rules.md`、`token-budget-gate.md`、`execution-modes.md`、`mcp-delegation-discipline.md`。

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
docs/diagrams/               編排流程互動圖（.workflow.json 原始規格 + .html）
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
