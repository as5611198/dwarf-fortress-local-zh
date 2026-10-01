# 矮人要塞繁體中文化

這是 DFHack／DFI18n 的繁體中文資料擴充，包含靜態介面字典、Legends 名稱與動態敘述適配器。

## 依賴

- Dwarf Fortress 53.16
- DFHack 53.16-r1.1
- DFI18n 0.2.4
- 上游中文資料 Workshop 項目（請玩家自行訂閱；本包不含該資料）
- 動態 AI 補譯需要玩家自行安裝 Node.js，並在本機設定 RimWorld Auto AI Translation Core；模組不包含金鑰。

## 啟用

DFHack 會自動發現本模組的腳本。請在 DFHack 的 `dfhack.init` 加入一行 `df-local-zh`，重新啟動遊戲後套用繁體中文。

## Workshop 發佈

請先訂閱 DFI18n 與相容的中文資料，再安裝本模組。建置與上傳流程、授權閘門及獨立安裝檢查，請看根目錄的 `WORKSHOP-PUBLISHING.md`。

## 隱私與狀態

世界名稱、翻譯快取、未解決文字、AI 設定與日誌會寫入 `dfhack-config/mods/df-local-zh-complete`，不會寫回 Workshop 模組。沒有 AI 設定時，已編譯字典仍可使用；首次遇到的動態文字可能維持英文，直到本機翻譯完成。

## 發佈狀態

這是可供公開發佈的適配器包；上游中文資料由玩家透過 Steam Workshop 另外訂閱。 上傳正式版前，仍必須完成獨立安裝、兩個世界、要塞模式、Legends、動態敘述與模組文字驗證。

## 動態報告

公告、戰鬥與醫療報告會在產生時加入本機翻譯佇列，並沿用世界限定的名稱與數字驗證。

## 文字頁

矮人思緒、物品與神器描述、書籍與歷史文字頁會在 textviewer 焦點下遮罩尚未翻譯的英文列，並保留原生輸入與滾動。

包內已附鎖定的 Broker production 依賴；只有在自行重建包且未安裝依賴時，才需要在 broker 目錄執行 `npm ci --omit=optional`。
