# 微軟注音候選修正與驗證：0.5.12

日期：2026-10-02。此版已建置、打包、部署並重啟驗證。真正 Windows IME 的組字、候選頁、方向鍵選字、翻頁、提交、取消與焦點恢復已由 Computer Use 按鍵測試通過。螢幕小鍵盤實際點鍵、使用者的遠端輸入來源、候選框目視外觀及 DPI／全螢幕矩陣仍未完成驗收。

## 問題與修正

保留原有 Rust SDL 輸入橋、公開 IMM／TSF 介面及 Lua 搜尋編輯器。沒有 SDL 私有位址、外部原創程式移植或拼音候選替代。此輪沒有修改命名、歷史事件或冒險功能；來源中先前已存在的變更保持原樣。

實測曾在 ↓ 後收到 TSF 候選 begin／end，失去候選更新，後續 Enter 未保留文字。設定 BeginUIElement 的 pbShow 為 false，由 Lua 顯示 Windows 提供的真實候選頁，維持 TSF 的更新與結束通知。按鍵仍由微軟注音處理；查詢只接收 SDL 已提交文字。狀態回報 candidate_ui=tsf_game_fallback。獨立的 Windows 原生浮窗未修復；本版採遊戲內候選框。

候選資料存在時仍看不到候選的另一原因是繪製順序。DFHack ZScreen 先繪製原生父畫面與 overlay，之後搜尋 Window 的背景把候選覆蓋。本版在当前 DFHack Screen 完成繪製後追加候選框；原生 DF 輸入欄仍沿用 SearchOverlay。候選框靠近游標，限制在畫面內；過長候選列優先保留選中項。

實際繪製呼叫回歸測試，不擷取畫面或輸入內容：

- 舊版失敗：screen begin → candidate text → window background → screen end。
- 新版通過：screen begin → candidate text → window background → candidate text → screen end。

## 驗證

- cargo test -p df_local_zh_core --lib -- --test-threads=1：56 通過、0 失敗、5 忽略。忽略項需要外部譯庫整合資料，與本輪 IME 修正無關。
- cargo build --target x86_64-pc-windows-msvc --release -p df_local_zh_core -p df-local-zh-broker：通過；使用靜態 CRT。保留既有未使用相依／欄位警告。
- IME_EDITOR：通過，包括 Unicode 編輯、組字按鍵保護、取消保留查詢、草稿、秘密欄位與候選框邊界／選中項測試。
- LIVE_BRIDGE：通過。此為合成 SDL 回歸，與下列實際 Windows IME 驗證分開。
- Windows IME：Computer Use 的 sky.press_key 送出 s、u、3，收到真實注音組字；組字時 query_bytes=0。
- ↓：候選頁保留 9 項，選中索引由 0 移至 1；查詢尚未提交。
- Enter：此台輸入法先確認候選、再由下一次 Enter 提交。最後查詢精確等於 Windows 選中候選，組字與候選清除；沒有用延遲或自行拼接組字偽造提交。
- Escape：取消新的組字，原有已提交字保留。
- Page Down：first=0 → 9；Page Up：first=9 → 0；每頁 9 項，查詢不變。
- 切到 osk.exe：候選／組字收起、已提交查詢保留。切回 DF：SDL 文字輸入與焦點恢復，能開始新組字。
- 控制工具的小鍵盤文字狀態只有視窗／標題列，未提供可點選的按鍵，因此不宣稱小鍵盤實際點鍵測試已通過。
- 測試使用主選單上的既有獨立 IME probe，沒有載入或改動堡壘存檔。未目視驗證候選框；繪製呼叫與候選資料已驗證。

來源保留 self-tests/ime-editor.lua、ime-render-order.lua、os-ime-acceptance.lua。後兩者需開啟專用測試搜尋窗，並在實際 Windows 按鍵後執行；不能以 search_push_text／search_push_composition 代替 OS 驗收。

## 發布與資料保護

- 套件／安裝樹驗證：df-local-zh-complete 0.5.12，827 個 payload 檔案。
- ZIP 每個 payload 的 SHA-256 已與 manifest 逐項核對，827 項全部符合。
- DLL SHA-256：745F29B71B2B007BF18B84CC067E7617361071A18A083A5E00F8BB50929D6345。
- ZIP SHA-256：6011641761E3CFA892EB3E86BCE2F1B66F243DBA0091A898BF9A2129A5A351BD。
- 安裝位置：%APPDATA%/Bay 12 Games/Dwarf Fortress/mods/df-local-zh-complete。
- 遊戲停止後才部署；重啟程序確認載入新版安裝位置的 DLL。
- 部署備份：_localization-work/ime-validation/backup-candidate-fix12-before-deploy-20261002。
- 部署與現場回歸後，5243 個受保護檔案的 SHA-256 全部未變，包括存檔、偏好、私人設定、名称與快取。
- 本轮一度建立的 save/current 測試副本已另外保留，原本 save/current 已還原。

獨立的公開 TSF Show(true) 診斷曾導致主選單測試程序退出，Windows 記錄位於 textinputframework.dll。該診斷 DLL 不在套件內，新版正式核心沒有呼叫 Show(true)，也沒有載入診斷 DLL。保留本機研究成品供後續調查，不宣稱已證明該 Windows 異常的完整原因。

## 待玩家驗收

目前遊戲留在空白 IME 搜尋測試窗。需要目視確認候選框，並重測實際遠端與螢幕小鍵盤輸入。實體鍵盤、原生 DF 各搜尋欄、繁簡介面、DPI 100%／125%／150%、全螢幕及 64／80 欄矩陣未在本輪逐項操作；不得以這次測試窗結果代替全部場景驗收。
