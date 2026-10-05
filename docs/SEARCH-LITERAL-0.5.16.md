# 搜尋欄原文繪製修正：0.5.16

日期：2026-10-02。玩家回報輸入 `tie` 時欄位顯示「平局」，輸入 `huagangyan` 時顯示「花崗巖」，結果卻正確匹配鐵及花崗岩。

## 根因與修正

`df-local-zh-search.lua` 的 TextAreaContent 繪製攔截原先只有 UTF-8 非 ASCII 或組字時才使用 literal search handle。沒有組字的 ASCII 查詢落回 DFHack 的一般繪製，英文單字 `tie` 會經翻譯器翻成「平局」，而玩家輸入與搜尋匹配本身仍是 `tie`。

移除 ASCII fallback，讓所有有效 UTF-8 搜尋輸入使用既有 slot 120 handle。原生翻譯器在 `display_query` 邊界還原此 handle 並立即返回原文；不清除翻譯快取、不改拼音索引、不把拼音搜尋當作 Windows IME 候選。非搜尋欄與無效 UTF-8 保留原有繪製路徑。

本輪程式行為修改僅在 Lua 搜尋繪製。Rust 輸入橋、TSF 候選、剪貼簿、私人草稿與後續功能沒有新增修改；核心 DLL 保持 0.5.15 的雜湊。

## 驗證

- 新增 `self-tests/search-literal-render.lua`：使用真正 DFHack FilteredList／EditField，攔截最終 draw 呼叫；不開測試畫面、不讀玩家文字、不擷取圖片、不改剪貼簿。
- 修改前已安裝 0.5.15 明確失敗於 `Search input must use literal rendering, including ASCII`。修改後來源及已部署 0.5.16 皆 `SEARCH_LITERAL_RENDER passed`。
- 涵蓋 `tie`、`huagangyan`、英數、空白欄、中文混輸、窄欄捲動、具名搜尋欄、非搜尋欄、無效 UTF-8 fallback，並驗證鐵與花崗岩的拼音匹配。
- 專用 probe 的真實 frame 觀察：兩個 fixture 的 slot 120 原文字串均交給 `dfhack_addstr_flag` 的 single-line handle 路徑，且 FilteredList 僅保留預期 choice（101／102）。結果 `PASS literal frames and pinyin matches (2 fixtures)`；測後清空 probe。
- 已部署 `IME_EDITOR passed`。Rust 核心 58 通過、0 失敗、5 忽略。Windows 靜態 CRT release build 成功，為增量建置，沒有修改 Rust 來源。既有警告未擴大處理。
- 玩家在部署後回報「測試完了 正常」，確認本輪搜尋欄原文顯示修正通過。這不等於已完成存檔內原生庫存欄位驗收；庫存中的注音候選／選字／提交、拼音匹配、剪貼簿及焦點切換仍待補測。
- 此輪沒有重新做實體鍵盤 Windows 注音驗收。先前玩家已通過候選／方向選字／提交／取消／切視窗、中文複製貼上。代理驗證時 SDL keyboard focus 為 false，輸入法未啟用；這次自動測試僅驗證繪製與查詢，不宣稱完整 OS 候選矩陣驗收完成。

## 打包、部署與資料保留

- 0.5.16 套件與 ZIP：829 個 payload SHA-256 逐項符合 manifest，ZIP 沒有額外檔案；無私人 runtime 資料。
- DLL SHA-256：`940C309A3586B72FA4A8D1455239253B7F0EFE7DCDB7B2925BA549F1469F2BD9`。
- ZIP SHA-256：`A782C4361A35234CDBDD978D4F51F506DD23FF8950B6031CD5E5C7A67C139D76`。
- 成品：遊戲目錄 `_localization-work/ime-validation/candidate-fix16-package/df-local-zh-complete-0.5.16-windows.zip`。
- 備份：`_localization-work/ime-validation/backup-candidate-fix16-before-deploy-20261002`。部署時遊戲已停止且未載入世界；changed=4、verified=829、protected=5243。
- 第一次停止命令的路徑比較不符，部署腳本正確拒絕執行中遊戲，未改檔；改用解析後的絕對路徑停止遊戲及該安裝樹 broker 後才成功部署。
- 重啟後核對 AppData 安裝 DLL 的載入路徑與雜湊，遊戲 PID 38404、broker PID 3804 僅為本次快照。
- 部署結束時 5243 個保護檔案全部雜湊相同；啟動並測試後 5242 個仍相同，只有 `data/native-cache-v1.jsonl` 由遊戲 runtime 更新。不能宣稱啟動後整個快取位元組不變。私人設定、API、存檔、偏好、名稱、草稿未被套件覆蓋。
- 未 commit／push；保留先前來源、更動、研究成品與私人資料，沒有本輪更新 `distribution/steam`。
