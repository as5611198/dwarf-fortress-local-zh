# 0.3.1 繁簡單包修正

0.3.0 公開包仍使用舊 adapter-only builder，且缺少自有 core 與 Broker 的必要檔案。0.3.1 改用固定授權 GitHub 來源建置一包繁簡資料，包含自有 DLL、完整 loader、Broker 相依模組與 Noto 字型，不再要求 DFI18n 本體或外部中文 Workshop 訂閱。DFHack 仍為執行環境；啟用步驟見 PLAYER-INSTALL.md。

## 來源與修正

固定來源：DFI18n/dfi18n-data-zh-hans `2ed0ac42a43375ce1d3d3fcd1403f825be58b3e6`，逐檔 SHA256 見 vendor/SOURCE.json。保留 CC BY-NC 4.0、署名及 OFL 字型授權。繁體使用 OpenCC CN->TW 與本地修正；簡體保留原始來源及轉換後本地修正，不宣稱轉換已證明語意。

上游 CSV 的 Macro, Save 列缺少原文引號，Adventure down-fast 列缺少譯文結束引號；建置器只修復這兩筆已定位格式錯誤，不改 vendor 原始資料。舊本地 preference 規則引用固定來源沒有的 ::name 群組，已移除該規則，名稱仍由存檔限定的 adapter 處理，未匯入玩家名稱或快取。

繁體 simple 10,848 列、簡體 simple 14,290 列，各 147 規則檔。列數含重複，不是唯一鍵數或覆蓋率。正式官方 R2 CC0 譯庫仍與這些 CC BY-NC 資料分開。

## 驗證

- 本機開發 Broker 全套 217/217；初次並行執行有一個既有 multi-API fixture 的 scope/status 競爭，重跑全套通過。公開 fixture 已停止與手動 scope 選擇無關的定時狀態刷新。
- 公開 portable Broker suite 197/197。開發環境的額外 audit/存檔素材測試沒有複製私人輸入到公開倉庫。
- Rust workspace 50 passed、7 ignored，0 failures；release core 與 translation-tool 建置成功（43.80 s）。
- 真正 Native 規則載入並翻譯需求描述：繁體 243 ms、簡體 101 ms（各單次，含行程啟動；非完整遊戲效能測量）。
- 全包 validator：743 檔，雙語、依賴、DLL 必需檔、SHA256 與私人狀態排除通過；缺少 DLL 的反向測試拒收。
- 隔離目錄：無 API/provider 呼叫下，兩語各啟動／重載兩次並保留使用者固定修正。這是程式與原生規則測試，沒有宣稱 Steam 訂閱遊戲實測。
- 本次未修改執行中 DLL、使用者設定、金鑰、名稱登錄或快取；10 個私人設定／名稱登錄檔部署前後 SHA256 一致。

ZIP：36,426,455 bytes，SHA256 `9e79a1ef4ade400071dac64cfa28ceae1bbc4d064f51c094710cb547ab97e687`。

Steam 上傳已成功：[Workshop 3811313433](https://steamcommunity.com/sharedfiles/filedetails/?id=3811313433)。SteamCMD 獨立目錄重新下載 56,383,177 bytes，743 檔 SHA256 與發布包一致，離線繁簡重载與固定修正等 3 項測試通過。兩份本機 VDF 都已記錄相同項目 ID，避免再次建立新項目。

Steam 客戶端訂閱後的遊戲畫面、兩世界／新世界、所有冒險與第三方模組仍未在本次實際驗證。0.3.0 Release 保留歷史；回復時關閉遊戲並換回舊包，保留 dfhack-config/mods/df-local-zh-complete。0.3.0 是有缺漏的適配器版，不建議玩家使用。
