# 中文暱稱後方姓氏與職業漏翻

## 確認原因

人物原生名稱包含暱稱、原文姓氏、英文意譯姓氏與職業。羽毛筆設定的是暱稱，不會刪除姓氏。
實機 unit 16285 的原生名稱尾段為 `Amemdakost`，英文意譯為 `Curlfloor`，職業為 `Mason`。
原版重新打開人物頁會重新組合這些欄位；並非舊暱稱殘留。

native 的 `chinese::direct` 遇到含中文字的整行便返回，導致暱稱後的 ASCII 姓氏與職業沒有翻譯。
玩家選擇保留姓氏，將姓氏及職業漢化。

## 修補

- 新增 Lua nickname display adapter，在既有 20-frame 人物文字更新週期中處理當前人物標題。
- 從名稱的獨立副本取得不含暱稱的本名及姓氏，原人物與存檔欄位不變；副本在成功與錯誤路徑都釋放。
- 使用既有本名譯文與第一名字典的精確前綴，取得一致的姓氏譯文；若無法證明前綴吻合，才單獨查詢原文姓氏，不猜測切字。
- 原文姓氏及英文意譯姓氏採用同一譯文，職業獨立查詢。玩家暱稱逐字保留，不送入翻譯、不進行繁簡轉換。
- Native 在一般中文直出之前，查詢最多 8 筆暫時標題映射。映射比對完整來源、世界、語言；5 秒失效，離開人物頁清空，不寫入全域字典或持久快取。
- 改名視窗底部按鈕固定分開：左側 Enter 套用，右側 Esc 取消，避免自動寬度造成重疊。

## 驗證與交付狀態

證據：遊戲目錄 `_localization-work/nickname-header-fix-20261003/`。

- `red.log`：修補前因缺少 nickname header adapter 失敗。
- `green.log`：暱稱逐字保留（含補充平面漢字與 ASCII）、姓氏一致、職業翻譯、引號、缺少翻譯、不向翻譯器傳暱稱、無姓氏人物等測試通過。
- `core-tests.log`：67 passed，0 failed，5 ignored。包含世界／語言隔離、完整來源比對、筆數上限、失效與清空。
- `regressions.log`：31 項 Lua fixture 通過。
- `build.log`：MSVC release core 編譯成功。
- `candidate-validation.log`：843 個 payload files 校驗通過；候選包在 `candidate/`。
- 初次 core 測試曾因 SDL DLL 搜尋路徑缺失而無法啟動；加入遊戲 DLL 路徑後上述測試全部通過。

2026-10-03 已確認遊戲退出，完成本機安裝與重啟；`installed-validation.log` 確認 843 個 payload files 校驗通過。
實際替換清單為 `installed-changes.json`，舊檔備份在 `installed-before/`。新核心匯出的 nickname API 已在遊戲中載入。

`installed-live.log`：脫離存檔的測試人物通過 6 種姓名／職業格式、同步與 render 查詢、production poll／renewal／close／reopen；補充平面字元及 ASCII 暱稱逐字保留，原存檔人物沒有被改名。
真機重新載入 `region3`、開啟人物頁與原生羽毛筆入口成功；畫面 50 FPS；當時視窗顯示 `Ctrl+s: 套用` 與 `ESC: 取消`（Ctrl+S 後續確認與原版 SAVE_MACRO 衝突，已改成 Enter）。

此次載入的 `region3` 中 unit 16285 暱稱欄位為空，因此沒有聲稱先前中文暱稱已完成實際人物頁保存／重載的視覺往返驗收。
已告知玩家，並將遊戲留在空白的中文暱稱輸入框；未以測試名覆寫角色或保存測試內容。

## Ctrl+S 巨集衝突後續修正

原版 prefs/interface.txt 同時將 SAVE_MACRO 與 CUSTOM_CTRL_S 綁到 Ctrl+S；實機長輸入框確認為 MacroScreenSave。只檢查 DFHack keybinding list 不足以排除原版按鍵衝突。
改名視窗套用提示與動作改為 SELECT（Enter），沿用 NameEdit 原有 on_submit；Esc 與滑鼠套用不變。Source、實際掛載模組及 candidate 已同步更新，兩個套件 validator 均通過 843 個 payload files；遊戲內脫離存檔的單位測試確認 Enter 只呼叫一次 accept，未改寫存檔人物。
本次只熱載入 rename 模組，未重載 search 或替換 DLL。自動鍵盤操作仍未關閉原版巨集框，因此修正後的實體鍵盤／注音選字與視覺驗收留待玩家重新開啟暱稱視窗確認。證據在 `_localization-work/rename-macro-key-fix-20261003/installed-enter-test.log`。
