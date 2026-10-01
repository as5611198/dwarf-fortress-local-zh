# Dwarf Fortress Local Chinese

繁體中文／簡體中文的 Dwarf Fortress 本機翻譯模組，包含 DFHack native core、Broker、官方譯庫同步與選擇性 AI 補譯。

## 公開內容

- `src/df-local-zh-native`：可建置的 Rust native core 與 DFHack 模組原始碼。
- `src/broker`：本機 Broker、官方譯庫驗證與資料建置工具。
- `src/community-cloud`：獨立的 Dwarf Fortress 投稿／Workers AI 審核 Worker。
- `distribution/steam/df-local-zh-complete`：已通過 validator 的 Steam Workshop 適配器包。

## 安裝

Steam 使用者請安裝 `distribution/steam/df-local-zh-complete`；它依賴 DFI18n 與相容的中文資料 Workshop 項目。離線使用已安裝官方譯庫時不需要 AI API。

## 授權

原始程式碼採 MIT，DFI18n 中文資料採 CC BY-NC 4.0。請閱讀 `LICENSE.md`、`ATTRIBUTION.md` 與 `DFI18N-DATA-ZH-HANS-LICENSE.md`。繁簡轉換與本地修正必須標示，中文資料不得作商業再散布。

公開包不包含玩家存檔、世界名稱、API key、私人快取、runtime journal、Cloudflare secrets 或簽章私鑰。
