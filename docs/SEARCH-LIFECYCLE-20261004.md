# 搜尋預載索引生命週期修補

2026-10-04，0.5.11 候選包之後的來源碼增量，尚未打包或安裝。

## 缺陷與修正

1. `SearchMemo::remove` 移除最後一筆文字時沒有刪除世界的空 HashMap。
   10,000 次不同世界 insert/remove 的測試在修正前失敗，修正後世界表、
   順序佇列與計數都為零，文字 Arc 的 Weak 引用也確認已失效。
2. 原生預載快照會替換，但搜尋 `preloaded_batch` 只追加，不回收消失的來源
   或先前世界資料。搜尋 memo 也可能繼續命中已移除的譯文。
   已改成每語言保存一份具世界識別的完整搜尋快照；有效空快照同樣會清除舊資料。
3. 搜尋索引在背景 worker 中建好，通過 prewarm generation／pause 檢查後，
   與原生預載快照在同一段 generation 鎖保護下發布。搜尋鎖內只清除有界 memo
   並交換索引，不在 render hook 建索引或讀檔。退休的預載及搜尋索引在鎖外釋放。
   原有靜態詞典、規則別名、已完成模型結果的優先權保留。

## 驗證

- 兩個確定缺陷均先取得失敗測試，再實作修正。
- 原生核心測試：74 passed、0 failed、9 ignored；ignored 仍須各自環境才能驗證。
- 包含 1,000 次世界／快照替換、空快照刪除、舊世代與暫停取消、
  靜態複合詞搜尋不退化、後完成模型譯文優先等案例。
- 額外執行讀取現有預載檔的整合基準：3,427,436 bytes、28,011 rows；
  27,998 accepted、13 rejected。Debug 測試程序中讀取＋驗證＋搜尋發布約 343 ms，
  其中建立／發布搜尋索引約 50 ms；這不是遊戲幀時間或 release 性能數據。
  重複準備 imported=0、worker submissions added=0。
- 修正人物頁 fixture 缺少 `start(runtime)` 初始化、typed unit status 與 literal
  alias 測試替身；原有姓名占位符和錯誤 token 拒絕斷言保留。相關 Lua fixtures
  6/6 通過（公告顯示、公告佇列、人物頁、價值觀色彩、離線喜好、離線思想）。
- 靜態 CRT 的 Windows release native core 建置成功。
- Lua 使用目前已安裝遊戲的 DFHack 執行隔離 fixture，未載入世界。
  這不是新 DLL 已安裝或存檔中 soak 通過的證據。

證據在遊戲目錄 `_localization-work/search-lifecycle-20261004/`，
包括 `native-tests.log`、`prewarm-benchmark.json`、`lua-results.json`、`release-build.log`。
初次重跑舊 audit runner 的結果另存 `initial-broad-rerun-results.json`；
該 runner 會覆寫舊結果路徑，舊結果已從原 deliverables/evidence 副本恢復。

## 尚未結案

A026 的動態字典／UI alias 與 trie 生命週期仍需分離，本次只處理搜尋預載及 memo。
A027 公告紀錄的 FIFO＋widget 引用還原草案已撤回：可能淘汰仍使用中的資料，
且保存原生 widget 指標供日後解參照並不安全。正式程式及公告原測試均已還原。
公告仍需可靠的生命週期回收方案；不得據此宣稱其成長問題已修復。
A028 的 journal 整理與 durable index、A029 FFI、A030 輸入法實體操作及 A034
多模式／長時間實測也仍未全部完成。90% 原版離線覆蓋率尚未經獨立樣本證實。

本輪沒有更新版本號、安裝套件或發布 Steam／GitHub。
