# 原生快取預載實作計畫

執行者：主代理自行實作，不使用子代理。使用者已批准優化既有預載，並要求將大量載入工作放進 DLL。

目標：移除 Lua 的全量 JSON 解析與每批 4～8 筆匯入限制，避免本機快取等候模型；用實際資料量測，不預先保證毫秒數。

設計：DLL 的獨立工作執行緒讀取现有 `native-prewarm*.json`，使用 serde_json 驗證世界、語言、版本、數字、標記及中文字串。現有固定字典優先；相同譯文跳過，動態新增／更新建立世界及語言隔離的唯讀快照，以 Arc 原子替換。短時間讀寫鎖只用於發布快照，讀檔、解析、驗證都在鎖外。Lua 僅每秒提供檔案路徑與目前世界／語言、暫停狀態及顯示進度。模型工作使用原本的排程與工作執行緒。

限制：原生工作不碰 Lua、DF 物件或遊戲 UI；不呼叫模型，不逐筆持久化，不覆蓋審定字典。取消／世界切換後舊工作不得發布。已載入的 DLL 不重置或替換；正式部署需遊戲退出。保留原競技場及私人設定。

1. [x] 在 `dfi18n/src/prewarm.rs` 建立失敗回歸測試：固定譯文跳過、動態快照讀取、數字／色碼錯誤拒絕、世界／語言隔離、取消與重新載入。命令：`cargo test -p df_local_zh_core prewarm:: -- --test-threads=1`。將實際字典查詢抽成 `translator::static_lookup(language, source)`，讓背景工作不讀 DF 狀態。
2. [x] 實作獨立原生背景服務及 `native_prewarm_request(path, world, language, paused)`、`native_prewarm_status()`；加入 `native_cache::lookup` 的快照查詢，以及分批世界隔離的搜尋索引更新。用實際預載檔和 release 測試量測讀檔、解析、驗證、發布耗時與零模型提交。
3. [x] 簡化 `df-local-zh-native-prewarm.lua` 為原生服務控制／進度橋接。Broker 輸出小型 `native-prewarm-unit*.json` 供執行期名稱及色碼恢复，避免執行期再解析整份大檔；保留舊版檔案相容回退。先加 Node 與 Lua 的失敗測試，再實作。完整 Lua 測試透過 DFHack fixture sandbox 指向來源，避免變更執行中 DLL。
4. [x] 跑 Broker、native、實際檔案整合及 Lua fixture 測試，編譯 release，組裝完整包、驗證清單及 DLL exports，完成部署腳本與備份。遊戲退出後部署並啟動，驗證原生進度完成、雙語重繪與零模型提交；記錄最後限制及時間數據。若遊戲仍在使用，先完成可審閱成品，再要求最後一步退出遊戲。

完成證據：text-audit/native-prewarm-20261001.md；40 個原生單元測試、11 個翻譯整合測試、158 個 Broker 測試、27 個 Lua fixture 均通過。release 真實檔冷載入約 18.5 ms；實際 DLL 的繁簡兩語各 11,368 筆全量查詢無缺漏；176 次抽樣重繪（每語 88 次）不提交模型。DLL 已於 PID 17776 啟動前備份部署，1072 個包檔案雜湊驗證成功。
