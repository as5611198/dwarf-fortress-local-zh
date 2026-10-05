# 人物暱稱輸入入口修補（2026-10-03）

## 原因與修改

玩家使用人物概況頁姓名旁的羽毛筆時，遊戲啟用
`view_sheets.unit_overview_entering_nickname`；這個原版單位元組編輯器不是
`cur_textbox` 或既有搜尋 widget，因此沒有啟動模組的中文輸入／注音橋接。
先前直接測試模組的 `RenameScreen` 沒有涵蓋這條實際入口。

- `df-local-zh-search.lua` 的 overlay update 偵測原生人物暱稱入口，首次需要時載入並快取改名模組。
- `df-local-zh-rename.lua` 的 `poll_native()` 只在原生 dwarfmode 頂層、已有選定人物時交接到「中文暱稱」視窗。
- 視窗成功開啟後才結束原版暱稱輸入旗標。輸入框自動取得 DFHack 焦點；使用既有 UTF-8 編輯與 IME 路徑。
- 只在玩家套用時寫入暱稱；取消維持原名。職業暱稱入口不在本次修補範圍。
- 不在 render callback 開啟視窗，也不在每幀重複 `reqscript`。

## 驗證

證據目錄：遊戲目錄 `_localization-work/rename-ime-fix-20261003/`。

- `red.log`：新增的原生入口測試在修補前確實失敗。
- `green.log`、`installed-tests.log`：原生入口交接、焦點、取消保留原名、沒有選定人物、職業入口隔離通過。測試使用脫離存檔的 `df.unit:new()`。
- `regressions.log`、`lua-results.json`：31 項 Lua 回歸測試全數通過。
- `installed-tests.log`：`IME_EDITOR`、`EXTENDED_ADAPTERS` 通過，涵蓋注音組字狀態、UTF-8／補充平面字元編輯、候選字排版與取消。
- 當時的實際人物暱稱入口已自動開啟中文視窗，native entry 旗標已清除，人物原名保持不變。
- `package-validation.log`：實際安裝包 842 個 payload files 通過 validator；兩支已安裝 Lua 與 source SHA-256 相同。

**尚未完成的驗收：本次修補後，以實體 Windows 注音打字、選候選字並套用到人物的完整人工操作。**
自動 UI 操作未能讓遊戲恢復鍵盤焦點，診斷回報 `sdl_keyboard_focus=false`、
`sdl_text_input_active=false`。因此上述程式測試不代表實際 Windows 注音流程已重新通過。
沒有為測試改寫玩家人物暱稱或保存測試名字。

## 安裝狀態與人工複驗

Source 與 AppData 實際掛載模組已更新兩支 Lua；安裝 manifest 已更新對應雜湊。
這是 `0.5.22-audit.2` 安裝內容上的本機 Lua hotfix，既有 audit.2 ZIP 未重打包、未公開發布。
當前遊戲已熱載入；另作一次性 wrapper 重綁，避免 Lua 腳本重新載入造成新舊焦點狀態混用。
正常重新啟動會直接載入修補後 source，不需要執行一次性 helper。

1. 關閉遮擋的螢幕小鍵盤，點一下遊戲使其取得焦點。
2. 開人物概況頁，按姓名旁的羽毛筆；應顯示「中文暱稱」視窗。
3. 切換 Windows 中文注音，輸入並選字；候選選字時不應提前套用名字。
4. 按取消確認人物原名不變；再重新輸入所需名字，以「套用」或 Enter 確認。
5. 保存／重新載入後檢查暱稱。這一步是人工驗收，未在本次修補中替玩家執行。
