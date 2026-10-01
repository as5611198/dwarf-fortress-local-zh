# 矮人要塞中文化：繁體／簡體整合包

Windows Dwarf Fortress 53.16，DFHack 53.16-r1.1。單一模組包含自己的原生核心、字型、繁體與簡體字典及規則，不需要另訂 DFI18n 或簡體中文資料 Workshop 包。

## 安裝與切換

1. 安裝並啟用 DFHack。
2. 訂閱本 Workshop 模組；GitHub 使用者則把 ZIP 中的 `df-local-zh-complete` 放到 DF 使用者 `mods` 目錄。
3. 在 `dfhack-config/init/dfhack.init` 加入一行 `df-local-zh`，再啟動遊戲。若啟動時模組腳本尚未被發現，在 DFHack console 執行 `df-local-zh`。目前需要這個一次性啟用步驟，不能宣稱訂閱後會自動啟用。
4. 在模組設定頁選擇「繁體中文」或「簡體中文」並套用；也可在 console 執行 `df-local-zh-settings-ui`。

**請勿同時啟用另一個 DFI18n／DFInt 原生核心**，避免重複掛鉤。同時訂閱的中文資料不會被本模組的資料載入器讀取。

## 離線與選用 AI

包內靜態字典與規則不需要 API Key、網路或 Node.js。動態文字的 AI 補譯與官方譯庫背景下載需要 Node.js；沒有 AI 時，尚未收錄的動態內容可能仍為英文。官方譯庫下載開關與玩家投稿開關分開；投稿預設關閉。

玩家的設定、API 金鑰、世界名稱與快取保存在 `dfhack-config/mods/df-local-zh-complete`，更新本模組不應移除這個目錄。原生 DLL 更新必須關閉遊戲後才替換。

## 來源與授權

簡體基礎資料來自 DFI18n/dfi18n-data-zh-hans 固定 commit `2ed0ac42a43375ce1d3d3fcd1403f825be58b3e6`。繁體使用 OpenCC 轉換並加入本專案詞彙／介面修正；簡體保留該固定版本原始資料並加入簡體化的本地修正。機械轉換不代表每個術語都已人工校正。

中文資料採 CC BY-NC 4.0，程式依各自 MIT 授權，Noto 字型採 OFL。請保留 `ATTRIBUTION.md`、授權及修改說明。包內不含私人模型快取、玩家世界名稱、存檔或金鑰。官方 R2 CC0 譯庫與這些 CC BY-NC 資料仍分開。

目前未承諾全部畫面零英文，亦未宣稱所有第三方模組或冒險模式畫面都已實測。
