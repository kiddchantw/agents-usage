# Security Review: agents-usage（全專案）

- 日期：2026-11-25
- 範圍：整個 repo（`AgentsUsageApp.swift`、`build.sh`、`.gitignore`、`docs/`、`README.md`），基準 `origin/main` @ `5cce9cc`
- 方法：完整閱讀所有程式碼，追蹤憑證、網路請求、子行程、外部輸入剖析四條資料流

## 結論

**未發現達到回報門檻（信心 ≥ 8）的 HIGH 或 MEDIUM 漏洞。**

## 逐項檢視

| 面向 | 檢視結果 |
| --- | --- |
| Claude token 取得 | 以絕對路徑 `/usr/bin/security` 啟動，參數為固定字串，沒有使用者輸入，不經 shell，無 command injection。 |
| Claude token 使用 | 只送往寫死的 `https://api.anthropic.com/api/oauth/usage`，走系統預設 TLS 驗證，沒有關閉憑證檢查、沒有可被外部控制的主機或協定。 |
| Token 外洩路徑 | 錯誤訊息、UI、log 都不含 token；token 不寫檔、不回傳到畫面。 |
| 憑證備援讀取 | 只讀 `~/.claude/.credentials.json`（固定路徑），無 path traversal。 |
| Codex 子行程 | 以 `codex app-server --listen stdio://` 啟動，參數固定；傳入的 JSON-RPC 訊息為寫死字串，沒有拼接外部資料。 |
| 外部輸入剖析 | Claude 回應用 `JSONSerialization` 逐欄位取值，Codex 回應用 `Decodable`，皆無反序列化執行、`eval` 或動態載入。 |
| 硬編碼機密 | 無。Repo 內沒有 token、密碼、金鑰；`docs/` 與 README 亦無。 |
| 相依套件 | 無第三方相依，只用 SwiftUI、AppKit、Foundation。 |
| Build 腳本 | `set -euo pipefail`；`rm -rf "$APP"` 的 `APP` 為腳本內固定字串；heredoc 帶引號，不會展開變數。 |

## 未列為漏洞的觀察（信心不足，或屬排除項目）

1. **`codex` 以 `PATH` 順序尋找並執行。** 若攻擊者能寫入 `PATH` 中靠前或 `~/.local/bin` 等使用者可寫目錄，就能讓 App 執行其程式。但這需要先具備該使用者的寫入權限，等同已能直接以該使用者執行程式，且 `PATH` 屬受信任環境變數，不構成新的提權路徑。
2. **Ad-hoc 簽署、未啟用 hardened runtime。** 屬加固建議，不是具體漏洞。本機自行編譯使用，沒有發佈給他人的情境。
3. **子行程輸出讀取為阻塞式。** 屬 DoS／資源問題，依規則排除；且已有 12 秒逾時。

## 非安全的附帶發現（程式缺陷）

- **已修正：** `AgentsUsageApp.swift` 的 `UsageError.http` 與 `.badFormat` 錯誤訊息原本寫「Select {} to view the response.」，但 `{}` 按鈕已移除，會把使用者引導去找不存在的按鈕。已移除該句，`.badFormat` 改為提示端點可能已變更。
- **未處理：** Bundle identifier（`local.claude-usage-menubar`）與 User-Agent（`claude-usage-menubar/1.0`）仍是舊名稱，未隨專案改名為 AgentsUsage。

這兩項不影響安全，屬於改名與移除功能後的殘留。
