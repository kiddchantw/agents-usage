# 疑難排解

## 確認數字正確

第一次請對照 Claude 的 Settings > Usage 與 Codex 的用量頁面,兩邊數字應該一致。不一致時,可能是端點或協定格式已變更,請閱讀 `AgentsUsageApp.swift` 的欄位解析排查。

## 常見狀況

| 狀況 | 處理方式 |
| --- | --- |
| 找不到登入憑證 | 先在終端機執行 `claude` 並登入。若鑰匙圈視窗被你按了「拒絕」,到「鑰匙圈存取」找到 Claude Code-credentials 項目,重新允許 `security`。 |
| 憑證已過期 | 開啟一次 Claude Code,讓它自動更新憑證,再按重新整理。 |
| Codex 區顯示 `Codex CLI was not found.` | 確認已安裝 Codex CLI,且 `codex` 在 `PATH`、`/opt/homebrew/bin`、`/usr/local/bin` 或 `~/.local/bin` 其中之一。 |
| Codex 區顯示 `Could not fetch Codex limits.` | 在終端機執行 `codex` 並以 ChatGPT 帳號登入;若 CLI 剛升級,可能是 `app-server` 協定變更。 |
| HTTP 401 / 403 | 憑證被拒絕。重新登入 Claude Code。 |
| HTTP 429 | 查詢過於頻繁,稍後會自動重試。 |
| 其他 HTTP 錯誤或「格式不符」 | 端點可能已變更。請調整 `AgentsUsageApp.swift` 的欄位解析。 |
| 編譯失敗 | 確認 macOS 13+ 與 Xcode 命令列工具;把錯誤訊息貼出來排查。 |
| 選單列沒有出現 | 確認 App 正在執行(活動監視器搜尋 AgentsUsage);選單列空間不足時,圖示可能被擠到螢幕缺口後面。 |
