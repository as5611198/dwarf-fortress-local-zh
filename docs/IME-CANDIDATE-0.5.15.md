# 遊戲內複製與剪下的 UTF-8 修正：0.5.15

日期：2026-10-02。已建置、打包、部署並確認新版 DLL 載入。玩家在遊戲內複製／剪下貼上測試後回報「正常了」，本輪剪貼簿問題已獲玩家驗收。

## 根因與前版診斷更正

玩家確認外部輸入後貼進遊戲正常，只有遊戲內複製後貼回出現 `σÑ╜`／`Θâ¥`。DFHack `gui.widgets.text_area.text_area_content:copy()` 使用 `setClipboardTextCp437()`，將搜尋欄內有效 UTF-8 的每個位元組當作 CP437 解碼後寫入 Windows 剪貼簿。例如 `好` 的 E5 A5 BD 會變成 σÑ╜。0.5.13 的繪製邊界假說及 0.5.14 的讀取端變更不足以修正此複製端問題；前版紀錄不能作為剪貼簿 bug 已修復的證據。

## 變更

- 沿用 Rust SDL 輸入橋，在已提交文字編輯時攔截 Ctrl+C／Ctrl+X，避免傳至 DFHack 的 CP437 複製函式。組字／候選期間仍由 Windows IME 擁有按鍵。
- Lua 使用實際 UTF-8 查詢及選取範圍，由公開 `SDL_SetClipboardText` 寫入剪貼簿。沒有複製搜尋 handle，也沒有在貼上後猜測反向修復亂碼。
- Ctrl+A 複製整段；滑鼠的反向／位元組選取端點對齊 Unicode 字元；無選取時單行複製整行，多行沿用目前行語意。只有剪貼簿寫入成功才刪除剪下內容；秘密欄位不輸出到剪貼簿。
- 新增 `self-tests/ime-clipboard.lua`：專用 probe 的複製、剪下、貼上往返，使用固定「好郝𠮷gjsok184」fixture。各階段需在不同事件 frame 執行；這項合成 SDL 回歸不能代替真實注音驗收。
- 本輪不新增命名、歷史或冒險功能，未使用 DFCN 原創程式或 SDL 私有位址。

## 驗證與限制

- 0.5.14 實際 probe 執行 seed → copy → paste → verify，明確失敗於文字往返不相同，提供修正前失敗證據。
- Rust 核心：58 通過、0 失敗、5 忽略。新增 Ctrl+C／Ctrl+X 按下與放開攔截回歸；既有 IME 按鍵所有權與 UTF-16 測試通過。
- Lua IME_EDITOR：來源與部署版本皆通過，包括選取／剪下、中文與 supplementary Unicode、組字取消、秘密欄位及候選框邊界。
- 靜態 CRT Windows release build 通過。既有編譯警告保留。
- Computer Use 採不擷取畫面的文字狀態，送出 Ctrl+A／Ctrl+C。首次 OS 剪貼簿 fixture 比對失敗；玩家告知當時正在複製其他東西，故這次不能當作有效驗收。
- 原生 `search_clipboard_write('ABC')` 後立即讀回及外部 Windows CF_UNICODETEXT 比對，兩者皆精確等於 ABC，證實 API 可更新實際剪貼簿。代理停止操作後，玩家自行測試中文複製／剪下貼上並回報「正常了」。
- 玩家先前確認注音候選／方向選字／提交／取消，以及切視窗清除未提交組字再恢復输入（第 1～3、5 項）通過。0.5.15 後的完整注音回歸仍應重測；DPI／全螢幕／原生 DF 各欄矩陣仍未全數驗證。

## 套件與部署

- 0.5.15 套件與 ZIP 的 828 個 payload 逐項 SHA-256 全部符合 manifest。
- DLL SHA-256：940C309A3586B72FA4A8D1455239253B7F0EFE7DCDB7B2925BA549F1469F2BD9。
- ZIP SHA-256：DE007DAB2B5B22C32B749327ABF6BC2B9956962B117BCD9BF2657A3F4636A95A。
- ZIP：`_localization-work/ime-validation/candidate-fix15-package/df-local-zh-complete-0.5.15-windows.zip`。
- 部署備份：`_localization-work/ime-validation/backup-candidate-fix15-before-deploy-20261002`，changed=9、verified=828、protected=5243。
- 遊戲停止後才部署；重啟後確認 DLL 載入自 AppData 安裝樹，雜湊符合套件。遊戲 31700 與 broker 20204 僅為最後核對時 PID，不是固定識別值。
- 部署後再次核對私人設定／存檔／偏好／名稱／快取，5243/5243 雜湊未变。沒有刪除私人草稿或舊研究成品，沒有 commit／push。
