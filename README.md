# Dwarf Fortress Local Chinese

繁體中文／簡體中文的 Dwarf Fortress 本機翻譯模組，包含 DFHack native core、Broker、官方譯庫同步與選擇性 AI 補譯。

## 公開內容

- `src/df-local-zh-native`：可建置的 Rust native core 與 DFHack 模組原始碼。
- `src/broker`：本機 Broker、官方譯庫驗證與資料建置工具。
- `src/community-cloud`：獨立的 Dwarf Fortress 投稿／Workers AI 審核 Worker。
- `distribution/steam/df-local-zh-complete`：內含自有原生核心、字型及繁簡資料的整合包。
- `vendor/dfi18n-data-zh-hans`：固定已授權 GitHub 來源及逐檔 SHA256。

## 安裝

Steam Workshop：[矮人要塞中文化（繁體／簡體整合）](https://steamcommunity.com/sharedfiles/filedetails/?id=3811313433)。

只需本模組與 DFHack，不需要另訂 DFI18n 本體或簡體中文資料包。繁簡都在模組設定頁切換，包內靜態翻譯離線可用、不需 API Key。啟用方式與選用 Node.js 功能見 [玩家安裝說明](docs/PLAYER-INSTALL.md)。不要同時啟用其他 DFI18n 原生核心。

重建與 Steam 上傳流程見 [發布說明](docs/WORKSHOP-PUBLISHING.md)。0.3.0 使用舊適配器封裝且缺少原生載入必需檔案；請改用 0.3.1 繁簡整合包。

## 授權

原始程式碼採 MIT，DFI18n 中文資料採 CC BY-NC 4.0。請閱讀 `LICENSE.md`、`ATTRIBUTION.md` 與 `DFI18N-DATA-ZH-HANS-LICENSE.md`。繁簡轉換與本地修正必須標示，中文資料不得作商業再散布。

公開包不包含玩家存檔、世界名稱、API key、私人快取、runtime journal、Cloudflare secrets 或簽章私鑰。
