# 官方共享譯庫第一階段（已批准設計）

目標：簽章官方通用譯文離線使用；不投稿、不帳號、不 D1、不上傳任何本機資料。

1. 核對現場與備份：非 Git 目錄；188 個 Broker 基準測試；獨立 Cloudflare 帳號與專用資源。保留所有既有修改與私人資料。
2. 建立隔離驗證測試，再實作 schema 1 整包 JSON、Ed25519 簽章信封、SHA256、語言／規則／用途／來源識別。沿用 df-zh-3 與現有模板，既有 cache key 不改。
3. 清點來源。未授權上游、世界名稱、未審模型與來源不明資料排除；本次獨立編寫及逐條校讀的通用詞句使用 CC0，繁簡分包並標記簡化轉換。可重現排序與衝突報告。
4. Broker 獨立官方層與固定修正層；內建字典另存高優先序，AI journal 不改。背景有界 GET 下載到暫存、簽章／內容驗證、原子狀態切換，保留前版與序號水位。失敗保留舊版；撤回以更高簽章序號授權。
5. 沒有完整畫面生命週期：遊戲執行中只能待啟用，遊戲關閉後才可切換。DLL 獨立背景批次讀取，本次程序版本固定。清模型快取不清官方層。
6. 設定頁加入獨立自動下載草稿、手動同步與小型狀態。同步不返回設定 snapshot、不重載 API／提示詞草稿。繁簡及 64／80 欄 fixture。
7. Cloudflare 專用 df-zh-official-library Worker 與 df-zh-official-library R2。GET/HEAD 公開入口，無寫入端點。私鑰存在工作區外、ACL 保護、不打包。
8. 完整 Node/Rust/Lua 回歸、release 建置、組裝／秘密掃描、備份部署；乾淨狀態真 HTTPS 下載後斷網重啟，記錄時間與實測樣本覆蓋。

啟用交易：immutable release 檔案 → atomic state.json（active, previous, pending, highestSequence）→ 可再生成 native 快照。重啟時重新驗證 active，損壞可退回已驗證 previous；網路倒退仍依 highestSequence 拒收。
