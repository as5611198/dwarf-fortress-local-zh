# 0.5.0 快捷鍵檢查

檢查涵蓋模組 Lua 快捷鍵、原生 SDL 輸入攔截、DF 53.16 的 `interface.txt`、DFHack 53.16-r1.1 的預設與實際載入綁定，並區分原版全域動作與特定畫面內的同鍵用途。

## 修正

| 操作 | 原按鍵／問題 | 0.5.0 |
|---|---|---|
| 中文暱稱套用 | Ctrl+S 叫出原版 SAVE_MACRO | Enter |
| 設定套用、提示詞確認 | Ctrl+S 與 SAVE_MACRO 衝突 | Ctrl+Enter |
| 提示詞恢復預設、冒險日誌更新 | Ctrl+R 與 RECORD_MACRO 衝突 | Ctrl+E |
| 歷史較早事件 | Ctrl+P 與 PLAY_MACRO 衝突 | Ctrl+B |
| 設定頁入口 | Ctrl+M 與 DFHack gui/mass-remove 共用；原版設定焦點可能仍為 dwarfmode/Default | Ctrl+E，僅原版設定開啟時 |
| 傳說人物種族篩選 | Alt+S 在文字輸入期間會被 SDL 字母鍵攔截 | Ctrl+E |

歷史下一頁保留 Ctrl+N。Ctrl+E 各用途分屬不同視窗，不會同時觸發。滑鼠操作與 Esc 取消保留。

## 其餘按鍵

- Ctrl+H 只出現在 Legends／Adventure journal，與要塞的 DFHack autodump、動物訓練、單位列表排序不在相同畫面。
- 設定內 Ctrl+T／Ctrl+Y 切換分頁；設定視窗攔截事件，不送到原版動物訓練畫面。DFHack markdown 的單位／物品畫面範圍不匹配設定視窗。
- Ctrl+A/C/X/V 與方向、Home/End、刪除鍵由取得焦點的 UTF-8 編輯器消費；巨集鍵沒有作為任何模組按鈕的綁定。
- 單字母按鈕只在獨立設定／狀態視窗內生效；編輯欄位取得焦點時，文字輸入優先。
- 提示詞 Enter 繼續插入換行；Ctrl+Enter 確認編輯。注音組字期間按鍵仍由既有 IME ownership 處理。
- 實際 DFHack 綁定查詢確認 Ctrl+Return、Ctrl+E、Ctrl+B、Ctrl+N 沒有額外指令綁定。

## 驗證

- 設定 fixture：焦點位於提示詞與金鑰欄時，Ctrl+Enter 只觸發一次確認；Enter 不提前確認；64／80 欄介面文字不裁切。
- `shortcut-routing.lua`：隔離模組環境、不顯示測試視窗、不改存檔；搜尋框有焦點時歷史前後頁及冒險日誌更新正確派發。
- Lua 回歸 33/33 通過；Node 回歸 201 通過、0 失敗、1 跳過。
- 0.5.0 乾淨發布包 847 個 payload files 通過 validator；ZIP CRC 與逐檔 SHA256 通過。
- 此輪沒有改動 Rust 核心；發布 DLL／EXE 與已驗證安裝版逐位元相同。未把自動事件派發測試視為所有實體鍵盤／輸入法與遊玩模式的完整人工驗收。

玩家自行重綁原版或 DFHack 按鍵後仍可能產生新的衝突；本報告確認的是上述版本的預設及本次實際載入設定。

## 發布驗證發現的設定交接問題

CI 的連續設定請求測試捕捉到回覆已可讀、舊請求卻尚未清理的競爭視窗。Lua 現在收到同 ID 的回覆及 `processed` 確認後才解除 pending、執行回呼；下一筆請求不會再被上一筆清理覆蓋。確認缺失仍受原有逾時限制。`settings-mailbox-handoff.lua` 以確定的事件順序驗證回覆先到、確認後到、回呼立刻送下一筆及逾時。Rust EXE 整合測試遵循相同握手順序。
