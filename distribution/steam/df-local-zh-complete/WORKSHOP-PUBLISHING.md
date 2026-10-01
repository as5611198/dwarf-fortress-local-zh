# Steam Workshop 發佈流程

這個檔案是給模組維護者使用的發佈檢查表，不是玩家必須執行的遊戲步驟。

## 目前硬性閘門

### DFI18n 中文資料授權紀錄

`https://github.com/DFI18n/dfi18n-data-zh-hans` at commit
`2ed0ac42a43375ce1d3d3fcd1403f825be58b3e6` is licensed CC BY-NC 4.0. The
maintainer `anln666` confirmed permission to modify it, convert between
Traditional and Simplified Chinese, and redistribute it in free modules and
cloud translation libraries. Keep the attribution, license link, change notice
and non-commercial restriction; see `DFI18N-DATA-ZH-HANS-LICENSE.md` and
`ATTRIBUTION.md` in generated packages.

This permission record is separate from the Steam Workshop page check below.
The official R2 library remains a project-authored CC0 corpus and must not be
described as containing this upstream data unless a release report explicitly
lists the imported rows and their attribution.

1. 若要建立「合併上游資料」的完整包，必須先把 `broker/LICENSE-STATUS.json` 的
   `upstreamChineseWorkshopData.redistributionApproved` 改為 `true`。目前頁面列出的作者是
   `wan1694`，頁面沒有寫明再發布授權；請先取得明確的文字同意，並把證據連結記在該 JSON。
   公開 Steam 包應使用適配器模式，讓玩家另外訂閱上游中文資料，不把 `dfi18n-data` 複製進本包。
2. 必須先完成獨立資料夾安裝測試：不依賴本機 `_localization-work`、RimWorld 設定、既有快取或既有存檔。
3. 必須在兩個不同世界與一個新生成世界驗證 Legends、要塞模式、公告、思緒、戰鬥、醫療、書籍、神器，以及已支援的模組文字。
4. 首次顯示、重啟、更新、取消訂閱後殘留資料、沒有 AI 設定，以及 AI 服務失敗時，都要記錄實際結果。

## 重建與檢查

在 `_localization-work` 目錄執行：

```powershell
node broker/prepare-workshop-package.mjs --output=workshop/df-local-zh-complete
node workshop/df-local-zh-complete/broker/validate-workshop-package.mjs workshop/df-local-zh-complete
```

公開適配器包使用：

```powershell
node broker/prepare-workshop-package.mjs --adapter-only --version=0.1.0 --output=workshop/df-local-zh-complete
node workshop/df-local-zh-complete/broker/validate-workshop-package.mjs workshop/df-local-zh-complete
```

適配器包不含 `dfi18n-data`，不需要上游再發布授權，但玩家必須先訂閱 DFI18n
與相容的中文資料 Workshop 項目。未取得上游資料授權時，完整合併包仍會拒絕輸出；只有本機測試可以加上
`--allow-unverified-upstream`，這個輸出不可上傳。

需要指定版本時，例如：

```powershell
node broker/prepare-workshop-package.mjs --version=0.1.0 --output=workshop/df-local-zh-complete
```

建置器會帶入 `preview.png`、`info.txt`、`README.md`、`WORKSHOP-PUBLISHING.md`、
`scripts_modinstalled/`、本地適配資料與 broker 原始碼，並產生 `PACKAGE-MANIFEST.json`。
只有完整測試包會帶入 `dfi18n-data`；適配器包的 manifest 會標示
`releaseMode: adapter-only` 及 `upstreamDataBundled: false`。

## 上傳前

- 適配器包的 Workshop 依賴固定為 DFI18n `3613958631` 與中文資料 `3635900931`。建立或更新項目時，在 Steam 的「Required Items／必要項目」欄位確認兩者都已加入；玩家仍需自行訂閱這兩項。
- 先把完整輸出複製到獨立的 DF 使用者設定，確認 DFHack 與 DFI18n 版本符合 `info.txt`。
- 在遊戲的 DFHack mod 管理／Workshop 發佈介面選取這個模組目錄，檢查標題、描述、標籤、預覽圖與版本。
- 新建立的 Workshop 項目不要手動加入 `[STEAM_FILE_ID:...]`；Steam 建立項目後，才把回傳的 ID 記錄到後續更新流程。
- 不要把 `dfhack-config/mods/df-local-zh-complete`、provider XML、金鑰、日誌、存檔、截圖或未審核快取複製進包。建置器只會打包 Broker 所需的鎖定 production `node_modules`，不會打包 Node.js 執行檔、測試依賴或開發快取。
- 上傳後以乾淨 Steam 使用者設定訂閱該項目，重新做一次啟動、重啟、取消訂閱與殘留檔案檢查。

## Workshop 描述中的誠實範圍

在完成上述驗證前，描述只能說明「繁體中文資料與動態文字適配器」，不能宣稱所有遊戲畫面已經零英文，也不能承諾首次出現的動態句子會同步完成翻譯。遊戲標題、更新日誌、DFHack／DFI18n 自身介面，以及未支援模組可以列為明確例外。適配器包的描述必須明確寫出上游中文資料是外部訂閱依賴。
