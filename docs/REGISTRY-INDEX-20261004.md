# 世界名冊索引與刪除生命週期修補（2026-10-04）

## 範圍與狀態

延續 A028 的名冊逐 entity 掃描問題。原本每句動態文字會對整個世界的所有 aliases 呼叫 `mentions`；人物 ID、傳說連結及人物標題也逐筆找 ID。另確認名冊檔被刪除後，`registry_cache` 仍保留舊名冊。

本次為來源碼修補，版本仍為 0.5.11。已建立新的 Windows 靜態 CRT Broker release executable，但**未重建 distribution、未安裝、未上傳 Steam／GitHub**。既有 distribution 0.5.11 不含本次與上一輪搜尋生命週期修補；不能以版本文字相同推論二進位相同。

## 修改

- 新增 `broker-rust/src/registry.rs`：每份名冊持有一個不可變快照、ID 索引及 Aho-Corasick 姓名候選索引；`service.rs` 的動態文字、pin、傳說名稱／連結與人物標題路徑採用此索引。
- 使用 contiguous NFA，避免建立大型 DFA。候選 alias 再以原 `mentions` 驗證，因此 Unicode 邊界、大小寫、標點及非重疊匹配語意不變。重疊姓名和共用 alias 都保留；返回次序按原名冊排序，保持既有同名覆蓋優先序。重複 ID 保持舊 `.find()` 取第一筆的行為。
- Aho-Corasick 建置回報錯誤時記錄診斷，回退原逐筆掃描，不能漏掉名字。這不表示可以從程序 OOM 恢復。
- 名冊由原 mtime＋length revision 判斷更新，資料與索引一起替換。`Arc` 讓進行中工作保留其快照，cache 不保存歷史版本。外部仍可使用原 `registry() -> Arc<Value>` 介面。
- 明確收到 `NotFound` 時清除 cache。metadata 在 replacement lock 內觀察，避免等待 lock 的呼叫使用較早的刪除觀察，覆蓋另一個呼叫剛載入的資料。
- `aho-corasick` 1.1.4 原已存在 lockfile 的間接相依；本次宣告為 Broker 的直接相依。

## 驗證與實測

所有紀錄位於遊戲目錄 `_localization-work/registry-index-20261004/`。

| 驗證 | 證據與結果 |
|---|---|
| 刪除名冊 regression | `red-removal.log` 原本失敗：刪檔後仍返回 Urist；修補後通過。測試包括快照重用、舊快照釋放、重建新世界與跨世界隔離。 |
| 效能 regression | `red-index.log`：抽出的原掃描演算法在 20,000 筆、90 次查詢下約 1,193 ms，與參照掃描相近，未通過 4 倍改善門檻；索引版通過。基準以 ignored test 明確啟用，不把機器時序門檻放入一般 CI。 |
| 邊界與回退 | Unicode／擴充漢字、標點、重疊、同名優先序、重複 ID、空 alias 與非字串欄位；1,000 組文字對照原演算法；強制無 matcher 時仍由正式 fallback 找到所有姓名。 |
| Broker 整合 | `registry_index_restores_names_and_updates_identity_without_provider_calls`：共用 alias、pin、傳說名稱、同世界名冊替換與新姓名重用句型；舊 native identity 被拒絕；provider calls = 0。 |
| Broker 常規測試 | `broker-tests-final.log`：75 passed、0 failed、5 ignored。跳過兩個明確效能測試、兩個需指定套件／語料的測試及一次明確雲端下載測試。 |
| release 索引驗證 | `release-index.log`：5 passed，包括兩個 explicitly enabled benchmarks。命令為 `cargo test --target x86_64-pc-windows-msvc --release -p df-local-zh-broker --lib registry::tests -- --include-ignored --nocapture`，`RUSTFLAGS=-C target-feature=+crt-static`。 |
| release build | `release-build.log`：`cargo build --target x86_64-pc-windows-msvc --release -p df-local-zh-broker` 成功。既有 workspace manifest 與 provider `fetch_update` deprecated warnings 尚在；未宣稱零警告。 |

正式編譯，同一程序內比較（單次量測，不是統計分布）：

| 資料 | 原掃描 | 索引查詢 | 初次建置 | matcher heap |
|---|---:|---:|---:|---:|
| 合成 20,000 entities，90 次查詢 | 236.245 ms | 0.078 ms | 156.477 ms | 849,260 bytes |
| 本機 128,114 entities，60 個分散抽樣名稱 | 2,415.922 ms | 0.205 ms | 364.966 ms | 20,090,080 bytes |

本機名冊為 16,688,244 bytes；唯讀 JSON 載入另需 176.612 ms，未改寫。60 個結果逐筆對照原演算法。matcher heap 不包括 JSON、alias 字串、owner／ID map 和暫存 builder；不能把它當作完整 RAM 上限。初次建置在 Broker 背景程序中，仍是同步工作，沒有移進遊戲 render hook。測試未進入遊戲／載入存檔，以上不能宣稱 FPS、總翻譯延遲或實機長時間驗收通過。

## 尚待處理

A028 仍未結案：append-only journals 的壓縮、索引式 durable cache、記憶體 cache 淘汰後避免重送模型尚未實作。本次不刪除玩家 cache、設定或存檔。

名冊同步載入／建置仍會短暫佔用 Broker worker；既有 revision 使用 mtime＋length，無法辨識刻意保留兩者不變的外部改寫。檔案存在但解析失敗時沿用舊的 last-good／下次重試行為，診斷與退避仍可改善。A026 動態字典／alias、A027 公告恢復記錄、A029 FFI 邊界、A030 實體 IME 驗收、A034 多模式長時間測試，以及原版 ≥90% 離線覆蓋率的獨立證明仍未完成。
