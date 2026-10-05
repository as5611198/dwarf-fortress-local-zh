# 翻譯主紀錄啟動整理（2026-10-04）

## 本輪處理

延續 A028 與 [持久快取修補](CACHE-PERSISTENCE-20261004.md)，新增 `broker-rust/src/journal_compaction.rs`，由 `TranslationCache::open` 在 Broker 接受請求前執行主紀錄維護。

本輪只整理 `translations.jsonl`。檢查目前 Rust／Node 使用處後，這個檔案沒有遊戲端的 byte offset 消費者；開發用 prewarm／compose 工具整檔讀取。Runtime request／response／UI journals 有各自游標，仍需要 generation／ack 輪替協定，不能套用同一整理方法。

## 保留規則與安全邊界

- 對權威 journal 重新串流掃描，建立 **file-backed temporary SQLite offset table**。不從既有衍生 `records` index 匯出，避免漏掉索引中遺失的有效原文。
- 僅當後方存在同 key 的有效譯文時，移除前方已被覆蓋的有效列。validation／policy／language／kind／name preferred 沿用現行讀取器；繁簡與不同 kind 的 key 保持隔離。
- 所有不理解／無效／不同 policy／超過 512 KiB／截斷的列都原樣保留。有效列保留原 bytes，輸出按原 offset 排序，保留相對次序、額外欄位、CRLF 及末尾未換行。整理不是壞資料刪除器。
- >=16 MiB 才考慮整理；需至少節省 1 MiB 且 >=25%。不值得整理時原檔完全不變。
- 記錄 maintenance watermark；同內容或自上次檢查後新增不足 8 MiB 時略過再掃描。變短或相同長度但 digest 改變會重新評估。此規則假設 Broker 是單一 append writer。
- 先寫唯一 sibling staging file，flush＋sync，重新核對當前 source SHA-256、length、mtime、creation time，最後以現有 atomic replacement 替換。開始掃描時也核對先前驗證的 SHA-256。
- 替換前任何失敗保留原檔並清除自己建立的暫存檔。僅在 `create_new` 成功後取得暫存檔清理責任。
- 檔案先替換、索引後更新；若兩者間中斷，下一次開啟的 fingerprint mismatch 會重建索引。維護錯誤有診斷並重新同步快取，不能假裝 cache miss。
- 啟動時只清除符合本 journal stem＋`compact-<UUID>.tmp` 的舊普通檔案；不處理其他名稱、目錄或 symlink。它用來回收上次程序中断留下的 staging file。正式 Broker 先綁定埠再載入 state，仍要求 state directory 單一寫入者。

主 index／temporary SQLite page cache 各設定約 2 MiB；line buffer 上限 512 KiB，沒有將全部 key／原始文字放進 Rust HashMap。這些不是整體程序 RAM 的硬上限。

## 驗證

證據目錄：遊戲目錄 `_localization-work/journal-compaction-20261004/`。

| 檢查 | 結果 |
|---|---|
| 原缺陷 red→green | `red-startup.log` 20,119,743 bytes 未縮減；`green-startup.log` 修補後為 191 bytes，保留最新中文，追加新句、重啟皆可讀回。 |
| 6 項 compaction unit tests | 保留最後有效列與原次序／繁簡；opaque、unknown policy、超長與截斷 bytes；收益不足不替換；替換失敗原檔不變且 temp 清除；source digest 過期拒絕替換；只清理指定 orphan stage。 |
| 替換後索引失敗 | `replacement_before_index_commit_failure_is_recoverable_on_restart` 用 SQLite trigger 阻擋 snapshot commit；journal 已成功縮減，重啟仍可重建並找回有效譯文。 |
| 不重複掃描 | Windows exclusive file handle 阻擋重新開啟 journal；已有相同 maintenance watermark 時維護仍成功返回，驗證略過全掃描。正常啟動的 SHA 驗證仍有 I/O。 |
| 全套 Broker release tests | `broker-final.log`：94 passed、0 failed、7 ignored。跳過四個明確 benchmark、兩個需要指定套件／語料的整合案例，以及一次公開雲端下載。 |
| 最終編譯 | `build-final.log`：Windows x64、static CRT 成功。既有 workspace manifest／provider deprecated atomic API warnings 尚在。 |

最終來源碼的明確 benchmark（`benchmark-final.log`）：

| 項目 | 數值 |
|---|---:|
| 原紀錄列數 | 100,000 |
| 保留有效不同 key | 10,000 |
| 整理前 | 20,377,800 bytes |
| 整理後 | 2,037,780 bytes（減少 90%） |
| 首次開啟，含原始匯入、整理及索引重建 | 1,446.834 ms |
| 整理後重啟 | 7.646 ms |

逐一查詢 10,000 個 key 確認都是最後一版中文；重啟後抽查首尾 key，並確認 journal hash 未再改變。這是合成資料、單次同機測量，不是 FPS 或數小時實機驗收。所有 mutation／故障注入只作用於測試暫存資料，玩家 cache／設定／存檔未被這輪驗證改寫。

## 交付與剩餘工作

沿用短 target path `_localization-work/rust-durable/x86_64-pc-windows-msvc/release/df-local-zh-broker.exe`，`RUSTFLAGS=-C target-feature=+crt-static`。版本仍為 0.5.11，**未打包、未安裝、未上傳**；distribution 與原 repo target 內較舊的 EXE 不代表這輪成果。

A028 僅完成翻譯主紀錄的啟動整理：長時間不重啟時尚不會整理；不同有效 key、opaque rows 的儲存仍會增加，沒有宣稱磁碟固定上限。Runtime request／response／UI cache journals 的輪替與確認協定仍未完成。其他 A026／A027 alias 生命週期、A029 FFI、A030 實體 IME、A034 多模式 soak 及 ≥90% 原版離線覆蓋率獨立驗證仍未結案。

沒有做真實斷電／磁碟硬體損壞測試。不支援與其他程序同時改寫同一 state directory；檢查與 atomic replacement 之間不是跨程序的 compare-and-swap。
