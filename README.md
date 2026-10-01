# Dwarf Fortress Local Chinese

繁體中文／簡體中文的 Dwarf Fortress 本機翻譯模組，包含 DFHack native core、Broker、官方譯庫同步與選擇性 AI 補譯。

## 公開內容

- `src/df-local-zh-native`：可建置的 Rust native core 與 DFHack 模組原始碼。
- `src/df-local-zh-native/broker-rust`：玩家端 Rust Broker，直接處理 HTTPS、AI API、簽章驗證與背景同步。
- `src/broker`：開發用資料建置工具、既有 JavaScript 相容性測試與原生啟動器。
- `src/community-cloud`：獨立的 Dwarf Fortress 投稿／Workers AI 審核 Worker。
- `distribution/steam/df-local-zh-complete`：內含自有原生核心、字型及繁簡資料的整合包。
- `vendor/dfi18n-data-zh-hans`：固定已授權 GitHub 來源及逐檔 SHA256。

## 安裝

Steam Workshop：[矮人要塞中文化（繁體／簡體整合）](https://steamcommunity.com/sharedfiles/filedetails/?id=3811313433)。

只需本模組與 DFHack，不需要另訂 DFI18n 本體或簡體中文資料包，也不需要安裝 Node.js 或其他開發環境。繁簡都在模組設定頁切換，靜態與已安裝官方譯庫離線可用、不需 API Key。啟用與選用 AI 功能見 [玩家安裝說明](docs/PLAYER-INSTALL.md)。不要同時啟用其他 DFI18n 原生核心。

重建與 Steam 上傳流程見 [發布說明](docs/WORKSHOP-PUBLISHING.md)。請使用 0.4.0 Rust 繁簡整合包；0.3.x 的選用背景服務依賴 Node.js，已由新版本取代。

## 授權

原始程式碼採 MIT，DFI18n 中文資料採 CC BY-NC 4.0。請閱讀 `LICENSE.md`、`ATTRIBUTION.md` 與 `DFI18N-DATA-ZH-HANS-LICENSE.md`。繁簡轉換與本地修正必須標示，中文資料不得作商業再散布。

公開包不包含玩家存檔、世界名稱、API key、私人快取、runtime journal、Cloudflare secrets 或簽章私鑰。
