# 漢化與輸入法：2026-10-03 發布前深層審查

## 發布判定

2026-10-04 後續進度：[搜尋快取生命週期修補](SEARCH-LIFECYCLE-20261004.md)
已修復預載搜尋資料只追加及空世界 memo 累積；A026 僅部分改善，A027 仍未結案。
另見 [世界名冊索引與刪除生命週期修補](REGISTRY-INDEX-20261004.md)：姓名／ID 索引與刪檔失效已修補；A028 的 journal／durable cache 部分仍未結案。
後續 [翻譯快取持久查詢修補](CACHE-PERSISTENCE-20261004.md) 已處理 A028 的磁碟索引及淘汰後重送模型；journal compaction／輪替仍未結案。
再續 [翻譯主紀錄啟動整理](JOURNAL-COMPACTION-20261004.md)：已保留有效譯文並整理 superseded rows；執行中整理與 request／response／UI journals 輪替仍未結案。
再續 [佇列紀錄讀取修補](JOURNAL-READERS-20261004.md)：修補 request 換檔漏讀、超長行錯誤分段、合法長請求被丟棄及 startup replay 的 UTF-8 中止；108 項 Broker 測試通過。generation／ack 輪替與 Lua 大型回覆讀取仍未結案。
最新 [遊戲端佇列讀取與解碼修補](LUA-JOURNAL-READERS-20261004.md)：大型回覆重組、線性換行／長字串解碼、Unicode 與 I/O 邊界、重複譯文及 short alias 更新已修補；18 個新案例及 26 項既有 Lua fixtures 通過。跨程序 generation／ack 輪替、startup I/O retry 與真機驗收仍未結案。
續見 [Broker 啟動歷史恢復](HISTORY-RECOVERY-20261004.md)：startup I/O retry／進度監管／完整快照後派送及可見 UI 狀態已修補；114 項 Broker 測試與狀態 UI fixture 通過。協調輪替、整體容量與真機验收繼續保留。
以下版本、數據為原審查歷史紀錄，不能替代目前候選版的驗收。

**交付版本為 `0.5.22-audit.2` 審查候選版，尚不建議標示為已完成全部正式發布驗收。**

本次已直接修補佇列、重試、主執行緒負擔、編碼、記憶體與資源生命週期等確認缺陷，完成 release build、乾淨打包及本機安裝。仍有長期動態字典／歷史紀錄成長、實體快捷鍵與剪貼簿延遲、完整多模式與長時間測試等未結案項目。通過下列測試不能證明所有輸入、第三方模組與遊戲版本都沒有缺陷。

基準環境：Windows x64、Dwarf Fortress **53.16**、DFHack **53.16-r1.1**；Rust/MSVC `x86_64-pc-windows-msvc`、靜態 CRT。Git HEAD 為 `4aea2031a9beb90cd35cf3824fa47278d658fb9b`，但審查起點包含大量先前未提交修改，**不能把本次補丁直接當成相對該 HEAD 的完整功能分支**。

## 範圍及可追溯性

- 起點清點 318 個第一方程式來源檔，涵蓋 Rust native／broker、C++／SDL／Lua 橋接、Lua 功能模組、Node 建置與測試工具。另檢查發布規則資料、套件 manifest 與實際掛載內容。
- 優先追查 `broker-rust/{service,provider,common,settings}`、`dfi18n/{hooks,native_cache,search*,glyph,text,markup,translator}`、SDL/C++ wrappers，以及 Lua runtime、reports、names-worker、prefetch、search-editor、rename、unicode 的資料生命週期。
- 第三方引擎、作業系統 IME／SDL 實作、完整上游字典及遠端服務不等於已逐行認證；此報告不宣稱形式化驗證或完整安全認證。
- 全程由主代理完成；未使用子代理、未 commit/push、未發布 Workshop。原有 dirty distribution、資產與先前修改保留。
- 原始證據、失敗紀錄及備份位於遊戲目錄 `_localization-work/pre-release-audit-20261003/`。該目錄包含私有設定與存檔，**不得整個壓縮上傳**。可交付檔案僅取 `deliverables/`。

下表中「已修補／驗證」表示對指定觸發情境有修補和對應證據；「既有修正驗證」表示問題在本次審查開始前已修改，本次沿用並補充驗證；「未結案」表示仍需工作。P1 為可能卡死、崩潰、資料或長期穩定性問題；P2 為效能、功能退化或驗收缺口；P3 為較低影響缺漏。

## 風險清單與修補

### 任務佇列、非同步及狀態機

| 編號／等級 | 觸發及影響 | 位置 | 處理與證據 |
|---|---|---|---|
| A001 P1 | 一般模式單句被傳說模式 visibility 條件排除，看似永久收集中 | `broker-rust/src/service.rs`、`tests/runtime.rs` | **既有修正驗證**。前景與背景單句不依賴 Legends visibility；兩個 single sentence 整合測試通過。前序使用者確認的個性／價值觀句子已完成翻譯。 |
| A002 P1 | worker 取消、逾時或 panic 後 pending／active 不釋放，阻擋後續工作 | `broker-rust/src/{service,provider}.rs` | **已修補／驗證**。PendingGuard／ActiveGuard 自動釋放；deadline 包括 semaphore 等待；runtime 監看 JoinError／timeout 並回送失敗、釋放 inflight。取消計數與後續工作測試通過。 |
| A003 P1 | 記錄 retryAt 後沒有重新排入工作，除非 UI 再次提交才會重試 | `broker-rust/src/service.rs` | **已修補／驗證**。未達重試上限的失敗重新入列、依退避時間執行；`runtime_failed_sentence_is_retried_without_another_journal_request` 通過。 |
| A004 P1 | 世界、語言或 visibility 切換後 journal 游標已越過工作，永久漏譯；舊工作污染新範圍 | 同上、`dfi18n/src/broker_client.rs` | **已修補／驗證**。捕捉提交時世界／語言；切換重讀 journal、清理不符範圍工作；完成時再次核對兩者。語言與 visibility 切換測試通過。 |
| A005 P2 | 名冊還沒輸出完成就達終止重試，名冊稍後到達也不恢復 | `service.rs` retry generation | **已修補／驗證**。設定、profile 與名冊 revision（mtime nanos、length）共同控制重試世代；新名冊允許重新使用有限重試額度。`completed_name_registry_retries_terminal_prose_once` 先失敗後通過，測試 provider 合計恰好呼叫兩次。 |
| A006 P1 | response journal 寫失敗仍視為完成，或 Lua 匯入失敗卻前進 offset，結果永久遺失 | `service.rs`、Lua `df-local-zh-runtime.lua` | **已修補／驗證**。成功寫入後才 completed；寫入失敗走重試；native 匯入未通過時保留未消費資料。`runtime-response-recovery.lua` 等通過。 |
| A007 P1 | 設定 request 先 ack 後 reply，reply 寫失敗後 UI 永遠等待，重送又可能重做非冪等操作 | `service.rs` settings task／reply | **已修補／驗證**。先保存待交付 reply，再 durable write，最後 ack；交付失敗只重送同一結果。故障注入測試通過。程序在操作完成與 reply 持久化間崩潰的 exactly-once 保證不在本次證明範圍。 |
| A008 P2 | 慢設定請求與 prewarm 阻擋背景 dispatch；cooldown profile 阻塞其他健康 profile | `service.rs`、`provider.rs` | **已修補／驗證**。設定與 prewarm 分離任務，設定有總 timeout；冷卻 profile 不佔用其他 profile 的可用通道。provider fallback／cooldown 測試通過。 |
| A009 P1 | 大量缺字累積 jobs、completed、failures 和等待呼叫；硬丟棄又造成漏譯 | `service.rs`、`provider.rs`、`bounded.rs` | **已修補／驗證**。provider 等待 128、jobs 1024、completed 32768、failures 4096；滿載延後工作以 journal 重播，前景可優先。這些為條目上限，非整體 RAM 位元組保證。 |
| A010 P2 | UI 把 active 和 queued 混為一談，失敗仍顯示收集中 | `service.rs` runtime snapshot、Lua runtime | **已修補／驗證**。按當前世界／語言回報前景／背景 queued、active、unresolved 與 retry generation。paused backlog 測試確認有積壓但不呼叫 provider。 |
| A011 P1 | 公告離線長時間累積 callback，關聯狀態被淘汰卻沒取消訂閱 | Lua `df-local-zh-reports.lua`、`df-local-zh-runtime.lua` | **已修補／驗證**。公告 pending 128，淘汰立即 cancel；seen 8192、顯示翻譯 4096、scan cursor 2048；backfill 可重新發現舊公告。300 條離線公告測試先紅後綠，包含取消與 revisit。 |

### 主執行緒與渲染熱點

| 編號／等級 | 觸發及影響 | 位置 | 處理與證據 |
|---|---|---|---|
| A012 P1 | 每個歷史人物呼叫 reqscript，載入存檔連暫停都只有 2–4 FPS | Lua `df-local-zh-names-worker.lua` | **既有修正驗證＋新增匯出修補**。unicode module 初始化時解析一次；fixture 130 人、5 批只需一次 module lookup。玩家已確認 50 FPS，本次載入也觀察到 50 FPS。 |
| A013 P1 | 名冊最後一次巨大 JSON encode 阻塞約 3.8 秒 | 同上、`df-local-zh-core/native.lua`、`dfi18n/src/lib.rs` | **已修補／驗證**。逐幀 64 rows 串流寫入 temp，完成後 native MoveFileExW atomic commit；錯誤、卸載、重設關閉 handles。實際匯出 16,688,235 bytes。DLL 和 Lua 必須成套更新。 |
| A014 P2 | 重繪多次翻譯相同 TextBlock、重複文字度量；每 tick 查找 Lua module | `dfi18n/src/{text,search}.rs`、Lua search／prefetch／reports／prewarm | **已修補／驗證**。一次 TextBlock 更新共用譯文；search_columns memo 512；熱路徑 script 物件快取。search memo／names performance fixture 通過。沒有把所有 timer 或磁碟輪詢宣稱為零成本。 |
| A015 P2 | 每句 parse 約 20 MB 世界名冊；一次讀過大 journal | `service.rs`、Lua runtime | **已修補／驗證**。名冊依 mtime／length 保存 Arc cache；broker tail 每輪 64 KB，Lua response poll 256 KB。registry 的 entity mention 掃描仍存在，見 A028。 |
| A016 P2 | render callback 讀取／解碼 logo，壞圖片每幀重试；display journal 整檔載入 | `dfi18n/src/logo.rs`、Lua runtime | **已修補／驗證**。logo 啟動預解碼，重繪只使用資源；display journal 改逐行讀取。全螢幕→視窗→全螢幕真機切換後 logo／中文正常、50 FPS。 |

### 編碼、剪貼簿及輸入

| 編號／等級 | 觸發及影響 | 位置 | 處理與證據 |
|---|---|---|---|
| A017 P1 | cursor 落在 UTF-8 中間、四位元組字退格或截斷，產生半字符 | Lua `df-local-zh-search-editor.lua`、native search input | **已修補／驗證**。cursor 邊界 clamp；以完整碼位刪除／截斷；composition 長度限制。`editor-boundaries.lua`、IME editor 與 `𠮷` 測試通過。碼位安全不等於完整 emoji grapheme-cluster 編輯支援。 |
| A018 P1 | Windows clipboard 無 NUL、奇數長度、孤立 surrogate 或超大內容導致越界／無界配置 | `dfi18n/src/search_input.rs` | **已修補／驗證**。只走 CF_UNICODETEXT，先 GlobalSize 驗證 2..65538 bytes 且偶數；strict UTF-16、必須 NUL，轉 UTF-8 後最多 32768 bytes；正常關閉／unlock。Windows 不再用無界 SDL read fallback；寫入保留 SDL UTF-8 setter。拒絕 malformed clipboard 單元測試通過。 |
| A019 P1 | 輸入法連續 composition 填滿 queue，commit 或最後 clear 丟失；IMM 候選長度异常、TSF 初始化中途失敗 | `search_input.rs`、`search_ime_windows.rs` | **已修補／驗證**。coalesce composition snapshot、保留 commit 與最後清空；IMM 1 MB 上限及複製長度檢查；TSF setup failure deactivate。4096 次 composition churn 與候選邊界測試通過。 |
| A020 P1 | UTF-8 中文暱稱與 CP437 重音姓氏拼接後，整串被視為 CP437，中文亂碼 | `crates/cp437_string/src/lib.rs`、`dfi18n/src/hooks.rs`、Lua `df-local-zh-unicode.lua` | **已修補／真機驗證**。保留完整 CJK UTF-8 序列，其餘 legacy 段轉 CP437；色彩依原 byte offset；native CP437 表 OnceLock，避免逐字 FFI 配置。`'測試𠮷A1' Nosîmilral` 原失敗→Rust／Lua 通過→真機人物列表正確。截斷四位元組序列不 panic。 |
| A021 P2 | 有效 Unicode clipboard 被當 CP437 重新解碼；舊 DF 字串直接交給 UTF-8 editor | clipboard／unicode／rename 管道 | **已修補／驗證**。legacy 來源先 decode，Unicode clipboard 維持 UTF-8。實際 Windows clipboard 注入 copy／cut／paste 後字串完整；延遲與實體快捷鍵仍見 A030。 |

CP950／CP936 不再被當作已知 UTF-8 內容的猜測性 fallback。Windows 系統可按 clipboard locale 將 ANSI 格式合成 CF_UNICODETEXT，但本次未實測所有「僅提供 CF_TEXT」的第三方程式。CP437 與 UTF-8 本質存在 byte 碰撞；mixed decoder 的啟用範圍是 CJK，不能宣稱任意 emoji 與任意 legacy byte 混合都無歧義。

### 記憶體、資源、存檔與錯誤处理

| 編號／等級 | 觸發及影響 | 位置 | 處理與證據 |
|---|---|---|---|
| A022 P1 | 高唯一文字量讓 native／Lua／glyph cache 無限成長 | `bounded.rs`、native_cache、text、markup、search、glyph、logging、Lua runtime 等 | **部分修補／容量測試通過**。native ready 4096／negative 2048、TextBlock 1024、markup 256／MTB 2048、search completed 4096、每語言 glyph surface／texture 4096、curses 2048、broker 16384、developer visited 8192；Lua 大部分快取 4096、display_saved 16384、prefetch seen 8192。尚有不能安全直接 FIFO 淘汰的資料，見 A026–A027。 |
| A023 P1 | from_raw 每次 Box::leak，或 borrowed wrapper 釋放遊戲擁有指標；surface null／pixel 長度错误 | `crates/{cpp,sdl2-sys}` | **已修補／驗證**。Arc wrapper 明確 owned／borrowed；borrowed drop 不釋放外部資源；null／lock failure／pixel length 檢查。CppVector、Surface、Renderer、Window ownership 測試通過。 |
| A024 P1 | renderer 被銷毀後 glyph／logo 仍持 texture 指標，use-after-free 或 double free | `sdl2-sys/src/{texture,renderer}.rs`、`dfi18n/src/{hooks,glyph,logo}.rs` | **已修補／驗證**。texture 持 renderer wrapper；Weak registry＋共享 AtomicPtr，destroy renderer 前 invalidate／swap null，一次銷毀，cache 遇到失效 texture 重建。真 SDL software renderer 持有 clone→invalidate→destroy→drop 測試通過；真機模式切換 smoke 通過。未做長時間反覆 renderer 重建／GPU device lost 壓力測試。 |
| A025 P1 | 中文暱稱寫入後移除模組，原版 loader 或名稱介面是否崩潰 | Lua rename、unicode、DF 原生 save loader | **指定案例真機通過**。隔離存檔 unit 16280 使用真正 rename accept 寫入 `測試𠮷A1`（12 bytes）→正常保存→完整移出漢化及停用 init→重啟載入→原版再次保存→恢復漢化再載入；資料 byte 完整。原版顯示 CP437 符號，未崩潰；恢復後中文正常。DFHack 仍在，不能称「完全無 DFHack 原版」。原使用者 region3 未加入測試暱稱。 |
| A026 P1 | static dictionary 與 runtime alias 共用 HashMap；search literals／trie 會隨 session 持續增加 | `dfi18n/src/translator/simple.rs`、`search.rs` | **未結案**。直接 FIFO 會讓畫面仍引用的 alias 露 token，拒絕匯入又會卡 response_offset。需分離靜態／世界動態資料，追蹤 active alias leases，先恢復 UI 再回收及清理 world generation。本次沒有以破壞顯示的方式硬加上限。 |
| A027 P2 | 公告 display_records 保存原文及 alias 恢復資訊，長存檔中可能累積 | Lua `df-local-zh-reports.lua` | **未結案**。世界／語言切換與 stop 會恢復並清空，但同世界無硬上限。後續需做 widget lifecycle／完整掃描的 live-set 回收；不能僅刪記錄而遺失原文恢復能力。 |
| A028 P2 | append-only journal 磁碟持續增加、重啟掃歷史；broker cache 淘汰老資料後可能重送模型；名冊逐 entity 掃描 | `service.rs`、native journal、Lua runtime | **部分緩解，未結案**。本次限制單輪讀取與記憶體 cache，仍需 journal compaction＋durable indexed cache＋mention 索引。驗收應包括冷啟動耗時、I/O、重複 provider 呼叫數，不能只看 RAM。 |
| A029 P1 | 大量 FFI extern C、unsafe ABI／raw pointer 仍依賴固定遊戲布局；poison／allocation panic 可能跨邊界終止 | native hooks、FFI bridge | **未結案／相容邊界**。本次修補已確認指標所有權、長度與 cancellation 問題；未全面重構全部 FFI panic containment，僅驗 DF53.16／DFHack53.16-r1.1。不同版本必須重新檢查 hook address、struct ABI 與 fail-closed 行為。 |
| A030 P2 | 真 Windows clipboard 完整性通過但一段調度耗時約 10 秒；工具 Ctrl+V 未進入 SDL keydown hook | clipboard／真機測試路徑 | **未結案**。條件 runner 成功資料為 10078 ms；先判成功後判 deadline，不能稱為 2 秒內通過。OS 合成鍵路徑可疑，連部分原版鍵也無效，不能直接歸因模組，也不能代替實體鍵盤驗收。 |
| A031 P2 | 捕捉錯誤卻吞掉關鍵失敗，持續 Pending；超大 placeholder index panic、物品品質大括號被誤判占位符 | `service.rs`、`common.rs`、Lua runtime／names-worker | **已修補指定路徑／驗證**。記錄 bounded reason，失敗回到可重試／terminal；匯出失敗清狀態及 handle；placeholder parsing 不 unwrap，品質物品與命名 token 區分。`quality_item_templates_translate_the_inner_prose`、malformed token 及失敗恢复測試通過。對可選欄位的 pcall 探測仍保留，不以逐幀 error spam 代替容错。 |
| A032 P3 | 實際繁體規則缺少 `five Notable Kills`／單數，忽略的整合測試未跑就看不到 | `src/data-patches/rulesets/zh-Hant/visual_ui.toml` | **已修補／驗證**。加入 no／one…twenty、數字複數及單數規則，產生繁簡套件；five／27／one 三種驗證通過。 |
| A033 P2 | build 成功但安裝包仍是舊 Lua／DLL；私有 API／存檔誤打包；整份 git diff 混入舊改動 | `src/broker/prepare-standalone-package.mjs`、交付工具 | **已處理／套件驗證**。隔離產生候選套件、manifest 全檔雜湊、排除私有 runtime，成套安裝；從審查前 source snapshot＋原 dirty patch 重建基線後產生本次增量，隔離 apply check 及實際套用比對。詳見交付驗證 JSON。 |
| A034 P2 | 少數真模型輸出 validator 拒絕後仍未翻譯；測試覆蓋不足被誤寫成全功能通過 | 模型輸出與驗收流程 | **未結案**。曾見 `{DWARF_NAME} likes cobaltite...` 及出發公告 residual English；名冊完成重試已補，但未逐條做新真模型驗收。validator 保留，不能為消除英文而放過壞占位符／人名。Adventure／Legends 完整操作、數小時 soak、實體鍵盤與其他 IME 尚待驗。 |

## 已執行驗證及結果

| 驗證層 | 實際結果 | 證據檔（位於本機審查目錄） |
|---|---|---|
| Rust workspace | **118 passed、8 ignored、0 failed**；之後另執行其中 7 個資料／本機 broker 整合測試並通過，因此 **125 個不同 Rust 測試通過**；仍有 1 個 live cloud download 未執行 | `rust-final5.log`、`rust-integrations-final.log`、`rules-integrations-green.log` |
| Release build | workspace MSVC release 成功；既有 unused dependency 等 warning 仍存在 | `build-release5.log` |
| Lua source fixtures | **31/31 PASS**；含 offline reports、UTF-8 邊界、runtime response recovery、names worker 與 mixed Unicode | `lua-final6.log`、`lua-results.json` |
| 安裝版 Lua fixtures | **4/4 PASS**：IME editor、search literal render、keybinding labels、extended adapters | `installed-fixtures-final.log`、`installed-fixtures.json` |
| Node／package tests | **201 passed、1 skipped、0 failed**，指定候選包為 package root | `node-final3.log` |
| 乾淨 package validator | **842 個 payload files 通過**（manifest 自身另計） | `package-validation-final.log` |
| 名冊／原生 prewarm | 10931 rows，10918 ready，13 rejected；cold load 139.76 ms，repeat imported 0，worker submissions added 0 | `native-prewarm-bench-final.json` |
| 暫停要塞性能 | 57.938 秒樣本，gfps **50**；names-worker 4027 calls／5827 ms total／32 ms max；runtime 1250／424／78；reports 250／574／16 | `perf-timers-live.json` |
| 短期記憶體樣本 | broker 約 228.4→228.0 MB，game 4993.1→4995.8 MB；不足以判定無 leak | `memory-live-first.json`、`memory-live-second.json` |
| 系統注音 | 實際注音組字、9 候選、Down 選字、Enter 提交、Escape 取消；第一次用 Right 與垂直候選不符的失敗保留 | `os-ime.log` |
| 剪貼簿 | 實際 Windows clipboard＋SDL 注入，`好郝𠮷gjsok184` copy／cut／paste bytes 完整；約 10 秒延遲仍未結案 | `clipboard-conditional.json`、`clipboard-real-key-diagnostics.log` |
| 存檔往返 | 模組移除、原版載入／保存、恢復後載入；nickname 12 bytes 完整，混合 surname decode 及畫面正確 | `vanilla-save-load.log`、`vanilla-process.json`、`restored-save-load.log`、`unicode-roundtrip-verified2.log` |
| 顯示切換 smoke | 主選單全螢幕 2560×1440→視窗→原全螢幕，中文／logo 正常，恢復 50 FPS；未反覆拖曳 resize／device lost 壓力測試 | 本對話真機工具截圖、`final-game-state.log` |

保留失敗證據，避免只留下綠色結果：`reports-red.log`、`registry-red.log`、`mixed-encoding-red.log`、`unicode-lua-red.log` 等。`rust-integrations-final.log` 曾因擊殺數規則缺漏失敗，後續 `rules-integrations-green.log` 修正通過。`node-final2.log` 誤用原 dirty distribution，缺 reviewed-text-keys 而失敗，改以候選包為根的 `node-final3.log` 通過。`unicode-roundtrip-final.log`／`verified.log` 包含 CLI 非 ASCII 期待值及錯誤 fps 欄位的測試命令失敗；改 ASCII 構造期待值後 `verified2.log` 通過，未修改 decoder 來迎合錯誤命令。

## 重跑方式

在 `src/df-local-zh-native` 執行，先讓 PATH 含遊戲、DFHack 及 `DFHack/hack`，並設定：

```powershell
$env:RUSTFLAGS='-C target-feature=+crt-static'
cargo test --workspace --target x86_64-pc-windows-msvc
cargo build --workspace --release --target x86_64-pc-windows-msvc
```

實際資料測試需設 `DF_LOCAL_PACKAGE` 為候選 package、`DF_LOCAL_RULESETS` 為該包 `dfi18n-data/rulesets/zh-Hant`、`DF_LOCAL_PREWARM` 為本機有效 prewarm manifest、`DF_LOCAL_BENCH_OUTPUT` 為暫存輸出；執行 core／rule crate 的 `-- --ignored` 前須有本機 broker。live cloud test 是不同測試，不在此命令的驗收承諾內。

在 `src/broker` 執行：

```powershell
$env:DF_LOCAL_ZH_PACKAGE_TEST_ROOT='<候選包完整路徑>'
node --test test/*.test.mjs
node validate-workshop-package.mjs $env:DF_LOCAL_ZH_PACKAGE_TEST_ROOT
```

DFHack Lua fixtures 透過本機 `run-lua-fixtures.lua` 將 loadfile remap 到審查來源，避免測到舊掛載碼。**dfhack-run exit 0 不代表 Lua 斷言成功**，必須同時檢查 `AUDIT_LUA_RESULT passed=31 failed=0` 與 JSON。GUI、存檔、剪貼簿測試應只在備份或隔離存檔上執行。

## 正式發布前仍需完成的驗收

1. **長期容量／生命週期（A026–A028）**：分離 static／dynamic alias，實作 active 引用回收、公告 live-set 清理與 journal 壓縮。至少 100000 唯一句、3 個世界往返 20 次，確認活動畫面不露 token、舊結果不污染新世界、記憶體進入平台期；重啟後老翻譯不增加 provider 呼叫。
2. **實體輸入（A030）**：注音／拼音／英文鍵盤逐項 Ctrl+A/C/X/V、左右／Home／End／Delete／Backspace、候選取消、焦點切換；clipboard 外部持鎖、超長 UTF-16、CF_TEXT-only CP950／CP936 來源。记录輸入事件、取剪貼簿、Lua poll、顯示各階段時間，釐清約 10 秒停頓；條件 runner 必須先判 deadline，禁止自動重送掩蓋問題。
3. **模擬與多模式（A029、A034）**：連續 4–8 小時未暫停要塞、Adventure／Legends 完整導覽、保存重載／語言切換、窗口反覆變更與 IME 一起測；記錄 working set、private bytes、handles、queue age、frame-time P95/P99。50 FPS 的短暫停樣本不能替代。
4. **存檔及卸載**：在另一個備份世界驗中文 entity／nickname 的新建、修改、刪除、存讀；完整停用 DFHack 的原版測試再做一次，驗證沒有依賴 DFHack repair 才能讀回。原版中文無字型支援時允許符號顯示，但不應崩潰或改壞 bytes。
5. **故障注入**：斷網、429／500／timeout、單句 malformed JSON、disk full／唯讀、程序於寫檔中止；同時放入健康句確認能前進，每個失敗有可見原因、有限重試及可恢復狀態。繼續檢查未全面重構的 FFI panic 邊界。

## 安裝、回復與補丁

- 候選 ZIP 僅包含 `df-local-zh-complete/` 乾淨 payload；個人 API、執行時 journal、存檔及暫時 counters 不在包內。安裝需關閉遊戲並成套替換同名模組，不能只複製 Lua 或 DLL。
- 本機現有 private state 保留；審查前模組備份為 `mod-before-install/`。回復時關閉遊戲後還原整個模組；不要用舊 state 備份覆蓋較新的設定或翻譯，除非另有回復需求。
- 原使用者世界正常保存後備份為 `save-region3-after-normal-save/`；測試暱稱僅在 `audit-compat-20261003` 副本。測試副本移出遊戲 save 清單保存為本機證據。
- `df-local-zh-pre-release-audit-only.patch` 比較「本次開始的 dirty tree」與完成的來源，排除前序未提交修改和編譯產物；**不是 clean HEAD 可直接套用的獨立 release patch**。應在相同起點副本先 `git apply --check`，再套用並重建。`PATCH-VERIFICATION.json` 列出逐檔 LF-normalized 前後 SHA-256 與實際套用比對結果。
- 最終安裝比對、ZIP 檢查、私有資料掃描及 SHA-256 清單隨交付附上。交付沒有代表 Workshop 已發布。

最終本機狀態：遊戲與 broker 已正常退出；安裝版與候選包 **843 個檔案（含 manifest）全部雜湊一致**。原 `region3` **1741 個檔案**與正常保存後備份逐檔一致；DFHack init 精確還原；測試副本已移至 `save-audit-compat-final/`。ZIP 解壓内容雜湊／CRC、已知本機金鑰掃描與禁止 runtime 路徑檢查通過。ZIP 為 39,602,744 bytes，SHA-256 為 `58c266fda026f9e67a7c57ffaf05be2c087f7a55ae6f4b9ca56306c6c1ce71bd`。
