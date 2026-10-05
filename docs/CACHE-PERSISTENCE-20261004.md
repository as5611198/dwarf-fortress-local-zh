# 翻譯快取持久查詢修補（2026-10-04）

## 問題與變更

A028 原本只將 journal 最後 16,384 筆有效譯文放入記憶體。較早譯文即使仍在 `translations.jsonl`，也無法由 `cached()` 找回；開啟 AI 時可能再次付費翻譯，關閉 AI 時則直接報沒有 provider。

新增 `broker-rust/src/translation_cache.rs`，以 SQLite 作為 **可重建衍生索引**，原 `translations.jsonl` 保持權威資料與既有格式。`service.rs` 的 exact／numeric／entity／name 查詢改為可回報 I/O 錯誤的 `Result<Option<String>>`；磁碟故障不能偽裝成 cache miss 並呼叫 AI。`link`／`phonetic` 舊紀錄仍按既有 policy 與 validation 匯入。

- 記憶體熱快取仍限 16,384 entries；淘汰後可透過磁碟索引找回。
- 第一次建立索引逐行驗證 journal，最後一筆有效相同 key 優先。無效後續行不抹掉先前有效譯文。單行暫存限制 512 KiB，過長行丟棄到下一個換行，避免壞資料造成無上限配置。
- 重啟串流 SHA-256 比對 journal bytes 與 index metadata。完全相同時不重做 JSON／文字驗證；仍有 journal 讀取與 SQLite integrity check 的線性 I/O，不能宣稱 O(1) 啟動。
- 自己新增譯文時先 append＋sync，再以 SQLite transaction 更新 row 與 journal fingerprint。失敗時保留舊觀察狀態；下一次查詢會重新驗證與匯入已落盤內容，避免永久遺失／重複 append。
- 檔案刪除、截短或 metadata 異動時，重新檢查並使索引及 hot cache 對齊來源。冷啟動能偵測長度與 mtime 不变的改寫。
- SQLite 檔案損壞／非資料庫格式：保留 `translations-index-corrupt-<uuid>.sqlite3` 再重建。資料庫可讀但 row JSON／key／譯文不合法：最多重建一次再查詢；原 journal 無有效譯文時才成為真正的 miss。SQL／I/O 錯誤繼續向上回報。
- SQLite page cache 目標 2 MiB、mmap 關閉；這是 page cache 設定，不是整個程序的 RAM 保證。hot cache 仍為條目數上限。
- 新增 `rusqlite 0.40.2`／`libsqlite3-sys 0.38.2`（bundled SQLite 3.53.2）。授權 collector 已更新清單及檔案，另附 SQLite public-domain notice。

所有寫入、刪除、損壞注入與重建測試都使用暫存資料。沒有操作玩家現有 AI cache、設定或存檔。

## 驗證

證據：遊戲目錄 `_localization-work/durable-cache-20261004/`。

| 項目 | 結果／紀錄 |
|---|---|
| 真正的原缺陷 | `red-eviction.log`：16,385 筆紀錄，第一句查詢失敗 `no translation provider configured`。修補後相同 `App::translate` 測試兩次重啟都返回中文，provider calls = 0，journal bytes 不變。 |
| 索引內容失效 | `red-payload.log`：可讀 SQLite 中的壞 row 原會永久返回解析錯誤；最終加入一次重建後通過。 |
| 快取與重啟 | 小容量淘汰後再查、同值不重寫、SQL trigger 確認 journal 沒變時不重匯入；中斷／過長行不阻擋後續有效紀錄。 |
| 資料安全與恢復 | journal 刪除／截短／相同長度與 mtime 修改、corrupt DB 保留備份、append 成功但 index transaction 失敗後復原、journal 無法寫入時不能假成功。 |
| 零額外模型請求 | `damaged_cache_query_is_not_sent_to_provider_and_releases_pending`：cache 查詢 SQL 故障向上返回，provider requests = 0、pending = 0。 |
| 正式編譯全套 | `release-broker-final.log`：85 passed、0 failed、6 ignored。ignored 包括三個明確效能測試、兩個指定離線套件／語料測試及一次公開雲端下載測試。 |
| 大量資料基準 | `release-cache-final.log`：最終來源碼明確啟用 50,000 筆 benchmark，9 項 cache tests 通過（其中 8 項也包含於全套常規測試）。如下表。 |
| 相依套件與建置 | `licenses.log`、`release-build-final.log`、`release-dependents.log`。EXE 僅匯入 Windows 系統 DLL，沒有 sqlite3.dll／MSVC runtime DLL 的額外安裝需求。 |

50,000 個不同有效 key、正式 static CRT 編譯、同機單次量測：

| 測量 | 數值 |
|---|---:|
| 原逐行載入／驗證演算法 | 187.240 ms（只留下最後 16,384 筆） |
| 首次建立索引 | 959.668 ms |
| 重啟驗證並重用索引 | 40.578 ms |
| 1,000 次不同冷查詢 | 110.863 ms |
| 原 journal | 10,077,780 bytes |
| SQLite index | 16,904,192 bytes |
| 查完全部 50,000 筆時的 hot cache | 16,384 entries；第一筆淘汰後仍可找回 |

初次遷移比舊 loader 慢，後續啟動免除逐行解析，並保留全部有效舊譯文。結果只表示合成資料下的持久查詢與效能，不是遊戲 FPS、多模式 soak 或總 AI 翻譯延遲證明。

## 建置與交付狀態

舊的深層 `target` 路徑觸發 MSVC LNK1104，檔案實際存在但路徑太長，記錄於 `release-cache-tests.log`。這次使用較短的獨立 target directory：

```powershell
# 在 src/df-local-zh-native 執行
$env:RUSTFLAGS='-C target-feature=+crt-static'
$env:CARGO_TARGET_DIR='E:\SteamLibrary\steamapps\common\Dwarf Fortress\_localization-work\rust-durable'
cargo test --target x86_64-pc-windows-msvc --release -p df-local-zh-broker
cargo build --target x86_64-pc-windows-msvc --release -p df-local-zh-broker
```

本輪 Broker 位於上述 target directory 的 `x86_64-pc-windows-msvc/release/df-local-zh-broker.exe`。之後組包須將 `--broker-exe` 明確指向這個已驗證產物；原 repo target 下的 EXE 尚未更新到本輪內容。

版本仍為 0.5.11，**未重新打包、未安裝、未上傳**。distribution 0.5.11 不含本輪持久快取及前兩輪搜尋／名冊索引修補。既有 deprecated provider atomic API 與 workspace manifest warnings 尚在。

## 未結案範圍

A028 的 durable indexed lookup／淘汰後重送已處理；journal compaction、runtime request／response／UI cache journals 的輪替仍未完成。SQLite index 隨不同有效 key 成長，journal 仍會 append；未宣稱磁碟空間固定上限。每次重啟仍需串流讀取 journal。

Broker 預設是單一寫入者。執行中透過 metadata 判斷外部改寫；刻意同時維持 length、mtime、creation time 的改寫需重啟才能由 hash 偵測，不能與其他工具同時編輯 journal。沒有做真實斷電、磁碟硬體損壞／磁碟填滿或數小時遊戲 soak。

A026／A027 的動態 alias 及公告恢復資料、A029 FFI 邊界、A030 實體 IME、A034 多模式驗收，以及原版 ≥90% 離線覆蓋率獨立證明仍然未結案。
