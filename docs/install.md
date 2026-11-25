# 安裝細節

## 編譯

把 `AgentsUsageApp.swift` 與 `build.sh` 放在同一個資料夾,然後:

```bash
bash build.sh
open AgentsUsage.app
```

`build.sh` 會用 `swiftc` 編譯並產生 `AgentsUsage.app`,不需要開 Xcode 專案,也會做 ad-hoc 簽署,讓 macOS 能執行本機建置的 App。

## 第一次執行

macOS 會跳出鑰匙圈視窗,詢問是否允許 `security` 讀取 Claude Code 的憑證。選「**始終允許**」,之後就不會再問。

## 開機自動啟動

把 `AgentsUsage.app` 放進「應用程式」資料夾,再到 系統設定 > 一般 > 登入項目 加入。

## 解除安裝

結束 App(面板右下角的 `Quit`),刪除 `AgentsUsage.app` 即可。它沒有在其他地方寫入任何資料。

如果你曾加入「登入項目」,也請一併移除。
