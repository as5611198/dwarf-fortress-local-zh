# 0.5.11 離線候選驗證

本候選修正物品描述中 `diamond` 的語意衝突：藝術圖案中的 `diamonds` 保留為「菱形」，鑲嵌、材質與製作語境翻譯為「鑽石／钻石」。共享狀態檔的並行發布也改為序列化，避免 Windows `rename` 的 EPERM 造成設定套用失敗。

驗證：

- Rust workspace：全部測試通過；核心、Broker、輸入法、佇列與快取回歸均通過。
- Node Broker：209 通過、0 失敗、1 個明確跳過的真實雲端下載測試。
- 實際打包資料：繁簡兩種語言，鑽石材質與菱形圖案語意測試通過，AI 請求 0；人格離線語料測試通過，AI 請求 0。
- Workshop package validator：0.5.11、864 個檔案通過。
- ZIP：`df-local-zh-complete-0.5.11-offline-candidate.zip`
- SHA-256：`a0b9b9fbcd91c3107993655b84821e5b4201b6f8a78b5c4ce534ca708e63875f`

這是本機候選包；本輪沒有上傳 Steam 或 GitHub，也沒有修改玩家存檔。
