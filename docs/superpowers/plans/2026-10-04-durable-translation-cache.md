# Durable Translation Cache Implementation Plan

**Goal:** 已成功落盤的有效 AI 譯文不能因 16,384 筆記憶體 cache 淘汰而被重送模型。

**Architecture:** `translations.jsonl` 保留為權威資料，新增可重建 SQLite 索引保存每 key 的最後一筆有效紀錄。Broker 專用 `TranslationCache` 統一序列化 journal、SQLite transaction 與 bounded hot cache。重啟串流 SHA-256 比對 journal；相同時重用索引，異動時串流驗證重建。保留原 validation／policy／name preferred 規則。

**Tech Stack:** Rust、rusqlite bundled SQLite、sha2、serde_json、Windows MSVC 靜態 CRT。

**Spec:** 本檔設計段落及 `docs/PRE-RELEASE-AUDIT-20261003.md` A028。

## Constraints

- 不修改玩家現存 journal／設定／存檔；測試只寫入暫存資料夾。
- 不發布、不安裝、不提升候選版本號；保留既有 dirty worktree。
- 主 agent 執行，不使用 subagents。
- 記憶體 hot cache 仍限 16,384 entries，SQLite page cache 約 2 MiB，禁止全檔 `read_to_string` 與無限制單行配置。
- 靜態／校訂／官方譯文的既有優先序不變；不得放寬 validation。
- cache I/O failure 應回傳可重試錯誤，不假裝 cache miss 而花費 AI 額度。

## Task 1 — Reproduce durable lookup loss

Files: `broker-rust/tests/runtime.rs`.

- [x] 在暫存 journal 寫入第一句有效譯文，後接 16,384 個不同 cache key。
- [x] 關閉 API，以 `App::translate` 查詢第一句，預期返回第一句中文、零 provider calls、journal bytes 不變；重啟 App 再查一次。
- [x] 執行 `cargo test -p df-local-zh-broker --test runtime evicted_translation` 並記錄真正的原行為失敗。

## Task 2 — Persistent derived index and service integration

Create `broker-rust/src/translation_cache.rs`; modify Cargo.toml/lock、lib.rs、service.rs。

Interfaces: `TranslationCache::open(root: &Path) -> Result<Self>`、`get(source, lang, kind) -> Result<Option<String>>`、`save(source, lang, kind, value, preferred) -> Result<()>`、`len() -> usize`。

- [x] 以 journal SHA-256＋length＋POLICY 驗證持久索引；使用 transaction 原子更新有效 row 和 metadata。相同 journal 冷啟動不再逐行 JSON／translation 驗證。
- [x] 超大／壞 JSON／錯 policy／錯 key／英文／壞 placeholder 不得進入索引；串流行 buffer 有上限。最後一筆有效相同 key 勝出，無效後續行不抹掉前筆有效紀錄。
- [x] journal append＋sync 成功後才更新 SQLite；任一步失敗不得發布成功。append 已落盤、SQLite 尚未提交時，下次查詢／重啟可重建恢復。
- [x] journal 被刪除／截短／替换時清空 hot cache 並使索引吻合目前 journal；相同長度修改也要失效。
- [x] SQLite 為衍生資料；可確認的 corrupted／not-a-database 檔案保留隔離備份後重建，其他權限／I/O 錯誤回傳。
- [x] `service.rs` 所有 cached 查詢傳遞 Result，避免故障被當 miss。health/status 仍只報 hot cache 條目數。

## Task 3 — Verification and evidence

Tests live in module and `runtime.rs`; evidence outside repo in `_localization-work/durable-cache-20261004/`。

- [x] 寫入、相同值去重、最新有效值、雙語／kind／name preferred validation、熱 cache 淘汰、重啟索引重用。
- [x] 過長行後的下一行、截斷尾行後續 append、SQLite commit 失敗恢復、損壞索引重建、journal 刪除／同長度替換。
- [x] 量測大量紀錄的首次建立、重啟、舊資料查詢及記憶體上限；不得宣稱遊戲 FPS。
- [x] Broker 全套測試、Windows static CRT release build、diff whitespace check。
- [x] 紀錄來源碼／交付套件尚未同步；A028 journal compaction 與其他 runtime journals 仍另列未結案。
