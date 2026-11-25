# 運作原理

這個 App 只查詢**用量額度**,不會呼叫任何 AI 模型,也不指定或使用特定 model。

## Claude

1. 從鑰匙圈(服務名稱 `Claude Code-credentials`)讀取 Claude Code 的 OAuth 登入憑證。找不到時退回讀取 `~/.claude/.credentials.json`。
2. 以該憑證向 `https://api.anthropic.com/api/oauth/usage` 發送一個 GET 請求。
3. 解析回應中的 `five_hour`、`seven_day`(以及有的話 `seven_day_opus`、`seven_day_sonnet`),每項包含 `utilization`(已使用百分比)與 `resets_at`(重設時間)。有分 Opus、Sonnet 各自額度的方案,會多顯示對應的列。

## Codex

1. 在 `PATH` 與常見安裝位置尋找 `codex` 執行檔。
2. 啟動子行程 `codex app-server --listen stdio://`,透過 stdin/stdout 傳送 JSON-RPC。
3. 依序送出 `initialize`、`initialized`、`account/rateLimits/read`,讀回 `primary` 與 `secondary` 兩個視窗,每個包含 `usedPercent`(已使用百分比)、`windowDurationMins` 與 `resetsAt`。視窗長度 300 分鐘顯示為 `5-hour limit`、10080 分鐘顯示為 `Weekly`。
4. 這條路不經過 token,完全依賴 Codex CLI 自己的 ChatGPT 登入狀態;子行程超過 12 秒會被強制結束。

兩邊的結果顯示在選單列與彈出面板。

## 更新頻率

- Claude 與 Codex **每 5 分鐘**一起查詢一次,啟動時也會立刻查詢一次。
- 手動重新整理有 15 秒的間隔限制。
- 滑鼠停在重設時間上看到的「剩餘時間」,以及進度條上的標線位置,每 30 秒用本機時鐘重算,**不會連網**。
- Mac 睡眠期間計時器暫停,醒來後恢復。

要調整頻率,修改 `AgentsUsageApp.swift` 中 `UsageModel` 的 `init()`:

```swift
timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { ... }
```

把 `300`(秒)改掉後重新執行 `bash build.sh`。不建議設得比 60 秒更短,端點是未公開的,太頻繁可能被限流(HTTP 429)。

## 技術備註

- SwiftUI `MenuBarExtra`(`.window` 樣式),需要 macOS 13+。
- `LSUIElement` 設為 true,所以沒有 Dock 圖示。
- 讀取 Keychain 是透過 `/usr/bin/security` 命令列工具,而不是直接呼叫 Keychain API,這樣重新編譯後不會因為簽章改變而重複詢問授權。
- 重設時間的小數秒會先去除再解析,避免 `ISO8601DateFormatter` 對微秒的相容問題。

## 檔案

| 檔案 | 說明 |
| --- | --- |
| `AgentsUsageApp.swift` | 全部程式碼:Claude 憑證與 API 請求、Codex app-server 查詢、資料模型、介面 |
| `build.sh` | 編譯並打包成 `AgentsUsage.app` 的腳本 |
| `docs/` | 說明文件與 README 使用的面板截圖 |

`AgentsUsage.app` 是編譯產物,已列在 `.gitignore`,不會進版控。
