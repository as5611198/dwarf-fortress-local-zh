# 佇列紀錄讀取修補（2026-10-04）

延續 A006／A028／A031，修補 Broker 的 request tail 與啟動 response／failure replay。這是 0.5.11 候選來源修補，尚未打包、安裝或發布。

## 確認的缺陷與修改

| 缺陷 | 修補 |
|---|---|
| request 檔案換成更大的新檔時，舊 byte offset 跳過新請求 | 使用開啟 handle 的 file identity；Windows volume serial＋file index、Unix device＋inode。換檔清除 offset、partial 及 discard 狀態。 |
| 超長壞行跨讀取區塊後，其 JSON 形狀尾段被當成新請求 | 保留 discard 狀態直到真正的 newline；跨 EOF 仍保留。下一個完整實體行才重新解析。 |
| 舊 32 KiB 限制丟棄合法的長篇傳說請求 | request 完整記錄限額改為 1 MiB；每次仍只讀 64 KiB。64 links × 2,000 source bytes 加本文及 JSON escaping 需要更大完整行限額。 |
| 開檔失敗被當成「沒有新文字」，而且沒有診斷 | NotFound 明確重設；其他錯誤上傳、第一次失敗記錄診斷；read／metadata 成功前不提交游標。下次輪詢能重新讀取。 |
| response／failure 啟動時使用無界 `BufRead::lines()`，一行無效 UTF-8 便停止整個 replay | 共用 bounded byte framing，單行損壞不影響後續健康行；啟動完整行限額 8 MiB，容納 requestLinks 及翻譯結果。 |
| 整個歷史 replay 無讓出執行時間，持續追加時結束點不固定 | 固定一個 handle 與開啟時的長度，每 64 KiB 後 async yield；追加留給後續程序，不延長本次啟動快照。 |

request malformed／oversized 計數最多每五秒記錄一次，避免把原文或每行錯誤刷入 log。啟動 replay 回報 rejected 總數，I/O 失敗明確標示 incomplete。末尾無 newline 的非空資料不作為完成記錄。

## 驗證與證據

證據目錄：遊戲目錄 `_localization-work/journal-reader-20261004/`；最終雜湊與測試統計見 `verification.json`。

- `red-reader.log`：修補前實際重現更大替換檔漏讀、超長尾段誤認新行、開檔錯誤被吞掉。
- `red-large-request.log`：舊 reader 使合法 64-link 請求逾時；修補後真實 App pipeline 在 AI 關閉下完成，64 個 link 全部取得預設中文，provider requests = 0。
- `red-startup.log`：損壞 UTF-8 位於已完成 Health 前方，舊 replay 將 Health 與新 Wounds 都派送，attempted = 2；修補後只派送 Wounds，attempted = 1、provider requests = 0。
- 7 個 Tail integration tests：較大換檔、超長實體行、缺檔／錯誤差異、消失再建立、四位元組 `𠮷` 跨 64 KiB 邊界、discard 跨 EOF／換檔、Windows sharing violation 後 partial 恢復。
- 5 個 snapshot unit tests：壞 UTF-8／超長／未提交尾行隔離及 >1 MiB 健康列；固定快照長度；換檔不混世代；開檔與中途截斷錯誤；單次 poll 在下一個 chunk 前必須 yield。
- `broker-with-replay.log`：**108 passed、0 failed、7 ignored**（75 unit、3 equipment、7 journal、23 runtime）。四個明確 benchmark、兩個需指定套件／語料的測試與 live cloud download 本輪未執行。
- `build-final.log`：Windows x64 release、static CRT 編譯成功。既有 workspace manifest／provider deprecated atomic API warnings 保留。
- `git diff --check` 通過；沒有遊戲內 FPS、實體輸入或存檔驗收宣稱。本輪測試使用 temporary state，未改寫玩家 state。

保留中途測試失敗：`boundaries.log` 的 UTF-8 fixture 最初 prefix 長度少算一 byte，已修正；`snapshot-tests.log` 最初假設 Windows 在讀取 handle 開啟時必能替換，實際被拒絕。最終測試接受 OS 的 access/sharing 拒絕並確認原資料完整、handle 釋放後可以替換；若 OS 允許替換，仍須完整讀出舊快照，不能混入新檔。

## 限制與後續

- 尚未實作 request／response／failure／UI journal 的 generation／ack 輪替；檔案大小仍可能隨時間增加。先前 translations.jsonl 的啟動整理仍是獨立機制。
- request Tail 無法可靠識別任意同 inode／file ID 的原地改寫再增長超過舊游標；需要明確 generation 協定，不可把此修補當成所有改寫都安全。
- 本輪 64-link 整合案例的回覆低於 Lua 舊 262,144-byte 邊界，不代表所有大型回覆都能顯示。後續 [遊戲端讀取修補](LUA-JOURNAL-READERS-20261004.md) 已處理跨 poll 重組及解碼；真機大型回覆驗收與 generation 輪替仍待完成。
- snapshot 限額限制單行緩衝，不是整體 Broker RAM 的 byte 上限；JSON 解析、cache／jobs／failures 的條目及 retained payload 仍需額外容量驗收。
- 本輪原先保留的 startup I/O 錯誤自動重播缺口，已於後續 [啟動歷史恢復](HISTORY-RECOVERY-20261004.md) 修補；完整歷史成功前暫緩 runtime journal dispatch。request 輪詢 retry 仍是不同機制。
- 每區塊 yield 不代表磁碟 read 變成非阻塞，也不代表首次接收翻譯不需等待歷史掃描。尚未驗收多 GB 歷史或數小時 soak。
- 仍未證明原版 ≥90% 離線覆蓋率。A026／A027 的引用生命週期、A029 FFI、A030 實體 IME 及 A034 多模式測試繼續保留。

最終 Broker 產物位於 `_localization-work/rust-durable/x86_64-pc-windows-msvc/release/df-local-zh-broker.exe`。distribution 及原長路徑 target 的 EXE 仍可能過時；後續打包必須明確指定此新產物並重新驗證。
