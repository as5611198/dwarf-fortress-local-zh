# 矮人要塞中文化：繁體／簡體整合包

Windows Dwarf Fortress 53.16，DFHack 53.16-r1.1。單一模組包含自己的原生核心、字型、繁體與簡體字典及規則，不需要另訂 DFI18n 或簡體中文資料 Workshop 包。

## 安裝與切換

1. 安裝並啟用 DFHack。
2. 訂閱本 Workshop 模組；GitHub 使用者則把 ZIP 中的 `df-local-zh-complete` 放到 DF 使用者 `mods` 目錄。
3. 在 `dfhack-config/init/dfhack.init` 加入一行 `df-local-zh`，再啟動遊戲。若啟動時模組腳本尚未被發現，在 DFHack console 執行 `df-local-zh`。目前需要這個一次性啟用步驟，不能宣稱訂閱後會自動啟用。
4. 在模組設定頁選擇「繁體中文」或「簡體中文」並套用；也可在 console 執行 `df-local-zh-settings-ui`。

**請勿同時啟用另一個 DFI18n／DFInt 原生核心**，避免重複掛鉤。同時訂閱的中文資料不會被本模組的資料載入器讀取。

## 離線與選用 AI

所有玩家端功能由隨包附帶的 Rust 原生核心與背景服務處理，不需安裝 Node.js、Python、Rust 或開發環境。包內靜態字典、規則及已下載的官方譯庫不需要 API Key 或網路。選用 AI 補譯需要你設定的模型 API；首次下載或更新官方譯庫需要網路。沒有 AI 時，尚未收錄的動態內容可能仍為英文。官方譯庫下載開關與玩家投稿開關分開；投稿預設關閉。

譯庫更新在背景下載、驗證並顯示「待啟用」，下次遊戲啟動才採用新版。下載失敗會保留既有可用版本，不會改動目前正在看的描述。

玩家的設定、API 金鑰、世界名稱與快取保存在 `dfhack-config/mods/df-local-zh-complete`，更新本模組不應移除這個目錄。原生 DLL 更新必須關閉遊戲後才替換。

## 來源與授權

簡體基礎資料來自 DFI18n/dfi18n-data-zh-hans 固定 commit `2ed0ac42a43375ce1d3d3fcd1403f825be58b3e6`。繁體使用 OpenCC 轉換並加入本專案詞彙／介面修正；簡體保留該固定版本原始資料並加入簡體化的本地修正。機械轉換不代表每個術語都已人工校正。

中文資料採 CC BY-NC 4.0，程式依各自 MIT 授權，Noto 字型採 OFL。請保留 `ATTRIBUTION.md`、授權及修改說明。包內不含私人模型快取、玩家世界名稱、存檔或金鑰。官方 R2 CC0 譯庫與這些 CC BY-NC 資料仍分開。

目前未承諾全部畫面零英文，亦未宣稱所有第三方模組或冒險模式畫面都已實測。

## 0.5.0 輸入與閱讀入口

搜尋、設定文字／提示詞草稿與中文暱稱使用同一個 UTF-8 輸入橋。組字期間方向、數字、空白、Enter、Esc 與刪除鍵交由輸入法處理；只有提交文字才修改欄位。候選視窗使用 Windows 公開 IMM／TSF 介面；真實微軟注音與各 DPI／全螢幕組合仍須玩家驗收。

- 選取單位後執行 `df-local-zh-rename`：中文暱稱最多 64 字，按「套用」才寫入世界，取消不修改。此入口處理暱稱，不改造所有遊戲命名畫面。
- 傳說模式按 Ctrl+H，或執行 `df-local-zh-history`：分頁瀏覽結構化事件摘要，Ctrl+B／Ctrl+N 換頁，搜尋支援中文。已識別類型有中文標題，未識別者保留事件類型；不是全部原生歷史敘述的完整翻譯。
- 冒險日誌按 Ctrl+H，或執行 `df-local-zh-adventure`：讀取事件、地點、人物、組織等日誌項目，中文搜尋；Ctrl+E 更新既有譯庫／已啟用 AI 的譯文。不改寫原生日誌或存檔。
- `df-local-zh-local-diagnostics once` 蒐集本機漏譯，`watch` 每 600 畫面更新取樣，`stop` 停止。預設不啟用，最多 8192 筆／5 MiB，記錄於模組私人狀態目錄 `local-diagnostics/residuals.jsonl`；不上传，不掃描設定與自訂草稿視窗。內容可能含世界專名，請留在本機。
- `df-local-zh-local-diagnostics refresh` 重讀本機堡壘介面字典與公告規則。逐個檔案／語言驗證成功才更新該項；不卸載核心或熱換 DLL。刪除舊字典條目仍需重啟。

罕見字會依已載入字型鏈回退；可選用本機 Windows 字型，發布包不包含 Windows 字型。

### 快捷鍵（0.5.0）

- 中文暱稱：Enter 套用、Esc 取消。
- 模組設定與提示詞編輯器：Ctrl+Enter 套用／確認；提示詞內 Enter 保留換行，Ctrl+E 恢復預設。
- 原版設定開啟時：Ctrl+E 進入模組設定。
- 傳說人物清單：Ctrl+E 選擇種族篩選。
- 歷史事件：Ctrl+B 較早、Ctrl+N 較晚；冒險日誌：Ctrl+E 更新。
- 設定分頁 Ctrl+T／Ctrl+Y、中文搜尋 Ctrl+A/C/X/V 沿用原操作。

Ctrl+S／Ctrl+R／Ctrl+P 是原版巨集按鍵，不用來操作本模組。
