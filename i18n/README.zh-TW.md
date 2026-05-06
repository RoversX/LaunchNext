# LaunchNext

**語言**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 下載

**[按此下載](https://github.com/RoversX/LaunchNext/releases/latest)** - 取得最新版本

🌐 **網站**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **說明文件**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ 請考慮為 [LaunchNext](https://github.com/RoversX/LaunchNext) 和原專案 [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) 給 star！

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe 移除了 Launchpad，新的介面很難用，也不能充分利用你的 Bio GPU。蘋果，至少給使用者一個切換回去的選項吧。在此之前，這裡是 LaunchNext。

*基於 [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)（作者 ggkevinnnn）開發——非常感謝原專案！❤️*

*LaunchNow 選擇了 GPL 3 授權條款，LaunchNext 遵循相同的授權條款。*

⚠️ **如果 macOS 阻止 App 執行，請在終端機執行：**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**原因**：我買不起蘋果的開發者憑證（$99/年），所以 macOS 會阻止未簽名 App。這個命令移除隔離標籤讓 App 正常執行。**僅對信任的 App 使用此命令。**

## LaunchNext 提供什麼

- ✅ **一鍵匯入舊系統 Launchpad** - 直接讀取你的原生 Launchpad SQLite 資料庫，重建資料夾、App 位置和佈局
- ✅ **手動整理 App** - 移動 App、建立資料夾，並按你的方式保留佈局
- ✅ **兩套渲染路徑** - `Legacy Engine` 用於相容性，`Next Engine + Core Animation` 提供最佳體驗
- ✅ **緊湊和全螢幕模式** - 支援分別儲存設定
- ✅ **鍵盤優先工作流程** - 快速搜尋、導航與啟動
- ✅ **CLI / TUI 自動化支援** - 可透過終端機檢查和管理佈局
- ✅ **Hot Corner 與原生手勢啟用** - 提供多種全域開啟方式
- ✅ **直接拖曳 App 到 Dock** - 在 Core Animation 引擎中可用
- ✅ **支援 Markdown 版本說明的更新中心** - 更豐富的 App 內更新體驗
- ✅ **備份與恢復工具** - 更安全的匯出與恢復流程
- ✅ **輔助使用與控制器支援** - 語音回饋和控制器導航都有改善
- ✅ **多語言支援** - 覆蓋較廣的本地化語言

## macOS Tahoe 拿走了什麼

- ❌ 無法自訂 App 組織
- ❌ 無法建立使用者自訂資料夾
- ❌ 無拖曳自訂功能
- ❌ 無視覺化 App 管理
- ❌ 強制分類分組

## 資料儲存

應用資料儲存在：

```text
~/Library/Application Support/LaunchNext/Data.store
```

## 原生 Launchpad 整合

LaunchNext 可以直接讀取系統 Launchpad 資料庫：

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## 安裝

### 系統要求

- macOS 26（Tahoe）或更高版本
- Apple Silicon 或 Intel 處理器
- Xcode 26（從原始碼建置時需要）

### 從原始碼建置

1. **複製儲存庫**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **在 Xcode 中開啟**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **建置並執行**
   - 選擇目標裝置
   - 按 `⌘+R` 建置並執行
   - 或按 `⌘+B` 僅建置

### 命令列建置

**常規建置：**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**通用二進位建置（Intel + Apple Silicon）：**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## 使用方法

### 快速開始

1. LaunchNext 首次啟動時會掃描所有已安裝 App
2. 匯入舊 Launchpad 佈局，或從空佈局開始
3. 透過搜尋、鍵盤導航、滑鼠拖曳和資料夾整理 App
4. 在設定中設定引擎、佈局模式、啟用方式和自動化功能

### 匯入你的 Launchpad

1. 開啟設定
2. 點擊 **Import Launchpad**
3. 現有佈局和資料夾會自動匯入

### 引擎與佈局模式

- **Legacy Engine** - 保留舊渲染路徑，優先相容性
- **Next Engine + Core Animation** - 推薦，整體體驗和新功能支援更好
- **緊湊 / 全螢幕** - LaunchNext 支援兩種模式，並可分別儲存設定

## 關鍵功能

### 啟用與輸入

- **Hot Corner 支援** - 從可設定的螢幕角落開啟 LaunchNext
- **實驗性原生手勢支援** - 四指 pinch / tap 動作
- **全域快速鍵支援** - 從任何位置開啟 LaunchNext
- **拖曳 App 到 Dock** - 在 Core Animation 引擎中將 App 直接交給 macOS Dock

### 自動化與進階工作流程

- **CLI / TUI 支援** - 檢視佈局、搜尋 App、建立資料夾、移動 App 並自動化工作流程
- **對 agent 友好** - 適合終端機型 AI agent 和 shell 自動化
- **設定中啟用命令列** - 可安裝或移除託管的 `launchnext` 命令

### 更新體驗

- **App 內更新中心** - 不離開 App 即可檢查更新
- **Markdown 版本說明** - 在設定中直接顯示更豐富的版本說明
- **現代通知 API** - 適配更新後的 macOS 通知機制

### 備份與恢復

- 在設定中建立和恢復備份
- 更可靠的備份匯出行為
- 更安全的臨時檔案和清理邏輯處理

### 輔助使用與導航

- **語音回饋支援** - 導航時播報 App 和資料夾名稱
- **控制器支援** - 可用遊戲控制器操作 LaunchNext 和資料夾
- **鍵盤優先互動** - 不依賴滑鼠也能快速搜尋和導航

## 效能與穩定性

- 智慧圖示快取，保證瀏覽流暢
- 延遲載入和背景掃描，適配大型 App 庫
- 更好的設定和導航狀態同步
- 更新處理、備份匯出和手勢恢復的可靠性提升

## 故障排除

### 常見問題

**問：App 無法啟動？**  
答：請確認系統版本為 macOS 26 或更高，必要時移除 quarantine，並確保你執行的是可信建置。

**問：應該使用哪個引擎？**  
答：推薦使用 `Next Engine + Core Animation`。如果你確實需要舊相容路徑，再使用 `Legacy Engine`。

**問：為什麼還沒有 CLI 命令？**  
答：先在設定中啟用命令列介面。LaunchNext 可以為你安裝和移除託管的 `launchnext` shim。

## 貢獻

歡迎貢獻。

1. Fork 儲存庫
2. 建立功能分支（`git checkout -b feature/amazing-feature`）
3. 提交更改（`git commit -m 'Add amazing feature'`）
4. 推送分支（`git push origin feature/amazing-feature`）
5. 開啟 Pull Request

### 開發指南

- 遵循 Swift 風格約定
- 為複雜邏輯新增有意義的註解
- 儘可能在多個 macOS 版本上測試
- 避免把實驗性功能散落到無關檔案中
- 儘量隔離可移除的整合

## App 管理的未來

隨著 Apple 逐漸遠離可自訂的 App 啟動介面，LaunchNext 試圖在現代 macOS 上保留手動組織、使用者控制和高效存取。

**LaunchNext** 不只是 Launchpad 的替代品，它是對工作流程退化的一種實際回應。

---

**LaunchNext** - 重新掌控你的 App 啟動器 🚀

*為拒絕在自訂化上妥協的 macOS 使用者打造。*

## 開發工具

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- 實驗性手勢支援基於 [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) 及其 [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport) 分支。❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
