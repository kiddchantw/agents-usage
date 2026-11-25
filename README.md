# Agents Usage 選單列小工具

一個 macOS 原生的選單列小 App,隨時顯示你 Claude 方案的**目前工作階段**與**每週限制**用量,不用再打開 Settings > Usage。

> **非官方工具。** 它使用 Anthropic 未公開的端點,與 Anthropic 沒有任何關係,之後隨時可能失效。使用前請閱讀下方「限制與風險」。

## 它做什麼

- 選單列顯示兩個百分比,例如 `15% / 4%`(工作階段 / 每週)。
- 點開後看到:
  - 每個限制的用量進度條,依用量變色(50% 以下青色、50% 以上橘色、80% 以上紅色)。
  - 重設時間(例如「於 下午4:10 重設」、「於 週二 下午4:00 重設」)與剩餘時間。
  - 進度條上的**細標線**,代表這個時段已經過去的時間。用量在標線前面,代表消耗得比時間快。
- 右上角 `{}` 可查看 API 的原始回應,`↻` 手動重新整理。
- 沒有 Dock 圖示,只存在於選單列。

## 需求

- macOS 13 (Ventura) 或更新版本
- Xcode 命令列工具(沒有的話執行 `xcode-select --install`)
- 已安裝並登入 **Claude Code**(小工具讀取它存放的登入憑證)
- 付費方案(Pro、Max、Team 等)。有每個時段限額的方案才有資料可顯示

## 安裝與執行

把 `AgentsUsageApp.swift` 與 `build.sh` 放在同一個資料夾,然後:

```bash
bash build.sh
open AgentsUsage.app
```

`build.sh` 會用 `swiftc` 編譯並產生 `AgentsUsage.app`,不需要開 Xcode 專案,也會做 ad-hoc 簽署,讓 macOS 能執行本機建置的 App。

### 第一次執行

macOS 會跳出鑰匙圈視窗,詢問是否允許 `security` 讀取 Claude Code 的憑證。選「**始終允許**」,之後就不會再問。

### 確認數字正確

第一次請對照 Claude 的 Settings > Usage,兩邊數字應該一致。不一致時,按 `{}` 看原始回應。

### 開機自動啟動

把 `AgentsUsage.app` 放進「應用程式」資料夾,再到 系統設定 > 一般 > 登入項目 加入。

### 解除安裝

結束 App(選單裡的「結束」),刪除 `AgentsUsage.app` 即可。它沒有在其他地方寫入任何資料。

## 運作原理

1. 從鑰匙圈(服務名稱 `Claude Code-credentials`)讀取 Claude Code 的 OAuth 登入憑證。找不到時退回讀取 `~/.claude/.credentials.json`。
2. 以該憑證向 `https://api.anthropic.com/api/oauth/usage` 發送一個 GET 請求。
3. 解析回應中的 `five_hour`、`seven_day`(以及有的話 `seven_day_opus`、`seven_day_sonnet`),每項包含 `utilization`(百分比)與 `resets_at`(重設時間)。
4. 顯示在選單列與彈出面板。

### 更新頻率

- **每 5 分鐘**查詢一次,啟動時也會立刻查詢一次。
- 手動重新整理有 15 秒的間隔限制。
- 畫面上的「剩餘時間」每 30 秒用本機時鐘重算,**不會連網**。
- Mac 睡眠期間計時器暫停,醒來後恢復。

要調整頻率,修改 `AgentsUsageApp.swift` 中 `UsageModel` 的 `init()`:

```swift
timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { ... }
```

把 `300`(秒)改掉後重新執行 `bash build.sh`。不建議設得比 60 秒更短,端點是未公開的,太頻繁可能被限流(HTTP 429)。

## 隱私與安全

- 憑證只用來向 `api.anthropic.com` 發送查詢請求,不會寫入磁碟、不會記錄、不會顯示在畫面上。
- 程式只有兩項對外行為:讀取憑證、發送一個查詢請求。沒有其他連線,沒有分析或回報。
- 這是你自己編譯的程式,不會自動更新。想確認行為,直接閱讀 `AgentsUsageApp.swift`,檔案不長。
- 這個請求是查詢用量,不是呼叫模型,預期不會消耗你的額度。這一點沒有經過官方確認,建議自己觀察一陣子。

## 限制與風險

- **端點未公開。** `/api/oauth/usage` 沒有官方文件,Anthropic 可能隨時更動或移除,屆時小工具會顯示錯誤或失效。
- **依賴 Claude Code 的登入狀態。** 憑證過期時,需要開一次 Claude Code 讓它更新,小工具本身不會更新憑證。
- **使用條款不確定。** 在 Claude Code 之外使用它的憑證是否被允許,並沒有明確的官方說法。正式依賴前請自行確認 Anthropic 的使用條款。
- 回應格式是依公開的第三方資料推測的。若你的方案回傳的欄位不同,按 `{}` 查看原始回應,再調整程式的欄位對應。

## 疑難排解

| 狀況 | 處理方式 |
| --- | --- |
| 找不到登入憑證 | 先在終端機執行 `claude` 並登入。若鑰匙圈視窗被你按了「拒絕」,到「鑰匙圈存取」找到 Claude Code-credentials 項目,重新允許 `security`。 |
| 憑證已過期 | 開啟一次 Claude Code,讓它自動更新憑證,再按重新整理。 |
| HTTP 401 / 403 | 憑證被拒絕。重新登入 Claude Code。 |
| HTTP 429 | 查詢過於頻繁,稍後會自動重試。 |
| 其他 HTTP 錯誤或「格式不符」 | 端點可能已變更。按 `{}` 查看原始回應。 |
| 編譯失敗 | 確認 macOS 13+ 與 Xcode 命令列工具;把錯誤訊息貼出來排查。 |
| 選單列沒有出現 | 確認 App 正在執行(活動監視器搜尋 AgentsUsage);選單列空間不足時,圖示可能被擠到螢幕缺口後面。 |

## 檔案

| 檔案 | 說明 |
| --- | --- |
| `AgentsUsageApp.swift` | 全部程式碼:憑證讀取、API 請求、資料模型、介面 |
| `build.sh` | 編譯並打包成 `AgentsUsage.app` 的腳本 |
| `README.md` | 本文件 |

`AgentsUsage.app` 是編譯產物,若放在 git 倉庫,建議加進 `.gitignore`。

## 技術備註

- SwiftUI `MenuBarExtra`(`.window` 樣式),需要 macOS 13+。
- `LSUIElement` 設為 true,所以沒有 Dock 圖示。
- 讀取 Keychain 是透過 `/usr/bin/security` 命令列工具,而不是直接呼叫 Keychain API,這樣重新編譯後不會因為簽章改變而重複詢問授權。
- 重設時間的小數秒會先去除再解析,避免 `ISO8601DateFormatter` 對微秒的相容問題。

## 免責聲明

本工具為個人使用的非官方實作,不隸屬於 Anthropic,也不受其背書。風險自負。
