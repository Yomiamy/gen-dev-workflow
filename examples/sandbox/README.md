# 沙盒：端到端冒煙測試（層 3）

一個零依賴的假專案，用來手動驗證 `gen-dev-workflow` 在**真實 repo 裡**能不能跑起來。

層 1／層 2 是自動化測試（`tests/run-all.sh`），驗的是狀態機與 hook 的邏輯。
這一層驗的是**接線**：skill 載不載得到、agent 找不找得到、hook 有沒有攔、
state 檔有沒有生。這些無法自動斷言——被測對象是 Claude 讀完 SKILL.md 後的行為。

## 為什麼不自動化

端到端要斷言的是 LLM 的判斷與暫停時機，偽造整套執行環境的成本遠超被測價值。
**這是冒煙測試，不是回歸測試**：改完流程手動跑一次確認沒斷，不追求覆蓋率。

## 準備（每次測試都用全新副本，別在原地跑髒）

```bash
# 複製到暫存區，避免污染 plugin repo 本身
rm -rf /tmp/wf-sandbox && cp -R examples/sandbox /tmp/wf-sandbox
cd /tmp/wf-sandbox
git init -q && git add -A && git commit -qm "chore: sandbox 初始狀態"
npm test    # 應印出 OK - all tests passed
```

## 冒煙測試 A：quick 模式（最短路徑，建議每次改完都跑）

```bash
cd /tmp/wf-sandbox && claude
```

```
/gen-dev-workflow quick 讓 greet() 支援可選的問候語前綴
```

**檢查點：**

| # | 應觀察到 | 壞掉代表 |
|:--|:--|:--|
| 1 | Claude 宣告使用 gen-dev-workflow skill | plugin 沒裝好，或 skill frontmatter 壞了 |
| 2 | `.claude/workflow-state/*.json` 出現 | `wf-state.sh` 路徑解析失敗 |
| 3 | 派發 implementer / verifier 等 agent 成功 | agent 沒被 plugin 帶進來 |
| 4 | quick 模式只在 PR 前停一次 | `should_pause()` 或 mode 判定壞了 |
| 5 | `npm test` 被實際執行且通過 | 實作階段沒接上驗證 |

跑到 PR 建立前的暫停點就可以停——**沙盒沒有 GitHub remote，不要真的建 PR**。

## 冒煙測試 B：棘輪擋不擋得住（驗 hook）

在 workflow 跑到某個暫停點時，叫 Claude「跳過確認直接進下一階段」。
`wf-guard-stage-check.sh` 應該攔下來。攔不住就是 hook 沒掛上
（檢查 `hooks/hooks.json` 的 `${CLAUDE_PLUGIN_ROOT}` 有沒有正確展開）。

## 冒煙測試 C：完整 sequence（改動較大時才跑）

需要一個能建 issue／PR 的 throwaway GitHub repo。把沙盒推上去後跑：

```
/gen-dev-workflow 讓 greet() 支援多語系
```

驗證 STAGE 0a→4 全鏈路，包含 issue 建立、worktree 建立、PR 描述產生。

## 收尾

```bash
rm -rf /tmp/wf-sandbox
```

沙盒若在測試中建了 worktree，先 `git worktree list` 確認後再刪，避免留下懸空引用。
