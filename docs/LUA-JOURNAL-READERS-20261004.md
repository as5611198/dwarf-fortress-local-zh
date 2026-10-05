# 遊戲端佇列讀取與解碼修補（2026-10-04）

延續 [Broker 讀取修補](JOURNAL-READERS-20261004.md)，本輪修正 `df-local-zh-runtime.lua` 的 response／failure 讀取、匯入交易邊界與長字串解碼。仍為 0.5.11 候選來源；沒有安裝、打包、啟動遊戲或上傳。

## 確認缺陷與修改

| 風險 | 修補 |
|---|---|
| >256 KiB 完整回覆被當作壞資料，前段被丟棄 | 每次仍讀 256 KiB，使用 chunks 累積完整行，完整記錄上限 8 MiB（與 Broker history reader 對齊）。完整行才 decode。 |
| 超長行的 JSON 形狀尾段被當成新紀錄 | discard 狀態跨 chunk／EOF 持續到實際 newline；超長行只記一次 rejection。 |
| `(.-)\n` 在沒有 newline 的大區塊反覆搜尋，阻塞主執行緒 | 換成 plain `find` 單向搜尋。中止舊碼壓力測試前，該程序已累積約 64.64 秒 user CPU。 |
| DFHack JSON decoder 逐字串接長字串，解析呈平方成本 | 此管道先以 runs 解碼字串，intern 成短 token，再交原 JSON decoder 處理結構／數字／布林／null。最後還原值與鍵。未修改 DFHack／第三方檔案。 |
| JSON 相同鍵使用不同 escaping 時，新 parser 可能改變 last-value 行為 | 相同 decoded string 共用 token，保留原 decoder 的 duplicate-key 語意；測試包含 `text` 與 `te\u0078t`。 |
| 原始 UTF-8 或 escaped lone surrogate 進入字典後形成非法字元 | raw UTF-8 檢查及 surrogate range 拒絕；`\u` 僅接受合法四位 hex、有效 high＋low 配對。`𠮷`、emoji、控制字元及 NUL 的解碼有對照測試。 |
| 開檔／seek／read／close 失敗被忽略、游標誤前進或例外外漏 | 讀取先 stage，成功 close 後才形成批次；所有開啟的 handle 都嘗試關閉，失敗保留原 state，去重記錄診斷。缺檔、縮短則清除 offset 與 partial。 |
| native 匯入失敗時，部分段落先發布、後續尾段可能遺失 | 保留完整 response batch 與 next state，直到字典匯入／逐列驗證通過，才發布一般文字及段落並提交 state。世界／語言切換重設批次。 |
| 同 key 同批次含新舊譯文，驗證舊值導致永久重試 | 每個 key 採最後完成譯文，再匯入與驗證；不再要求一個字典 key 同時等於兩種翻譯。 |
| 同 key 更新後，short alias 仍顯示舊中文 | key 或譯文任一改變，都清除該 identity 的 short-ready／short-staged，依新文字建立 alias。 |
| 不完整傳說 link 欄位在組合 identity 時拋例外 | 驗證 request link type／id／text、數量及 translated link 形狀；壞段落略過並記錄，健康鄰居繼續。 |
| 輸出 CSV write throw 後沒 close，重試累積檔案 handle | `load_rows` 分別保護 write／close；write 失敗仍 close，並保留匯入重試。 |

同檔錯誤訊息去重；rejection 至多每五秒彙整輸出。不把壞行原文寫入診斷。沒有把較大讀取上限當作效能修補：poll read budget 保持 256 KiB，字串只在整行完成時合併一次。

## 驗證

證據：遊戲目錄 `_localization-work/lua-journal-reader-20261004/`。

- 新增 `self-tests/runtime-journal-boundaries.lua`，**18 個案例全部通過**（`boundaries-final.log`）：合法 64-link 大型段落；跨界 `𠮷`＋native 匯入重試；超長行跨 EOF；缺檔再建立；truncation；大 failure＋retry generation；五類 open／seek／read／throw／close 故障；重複 key；malformed link；非法 UTF-8／surrogate；CSV handle 釋放；世界切換；short alias revision；JSON 解碼對照。
- 解碼对照案例包含 100 組巢狀字典／陣列／長字串／布林／數字，以及 escaped duplicate keys、合法 UTF-16 surrogate pair、非法跳脫與控制字元。該案例刻意呼叫原慢 decoder 作為 oracle，約 10.7 秒的整體測試時間不是新 runtime poll 時間。
- **26 項既有 Lua fixtures 全部通過**（`regression-final.log`、`lua-results.json`）：runtime callback／language／poll cost／queue I/O／rich text／reviewed priority、公告、角色頁、顏色、prewarm、既有 response recovery 等。
- 最初沿用 31 項遊戲內 runner 時，10 項因獨立環境缺 API 失敗（`regression-first.log`）。補上 source `findScript` 對應後，其中 5 項可跑；另外 fortress UI、settings UI、status UI、names worker、mixed legacy encoding 的 5 項仍依賴真實 DFHack GUI／`df2utf`，本輪不計為通過。
- `node --check src/broker/prepare-standalone-package.mjs` 與 `git diff --check` 通過。新測試已加到下一次乾淨打包的 self-tests 清單。Lua 使用現有 bundled `lua53.dll`＋DFHack JSON 套件，不需要啟動遊戲。

同機、單次隔離測量（非實機 FPS／P95 保證）：

| 案例 | 修補前 poll CPU | 最終 poll CPU |
|---|---:|---:|
| 單一約 256 KiB 字串，跨四位元組字元，需重試匯入 | 1,506 ms | 12 ms |
| 64 links × 2,000-byte 英文名稱＋每項 1,000 中文字翻譯的合法大段落 | 139 ms | 15 ms |

前值來自已修好 framing、尚未優化 JSON 字串時的 `red-encoding-handles.log`；後值來自 `boundaries-final.log`。不要把兩者誤寫成遊戲幀率改善或所有最大限額紀錄皆能在一幀內處理。8 MiB 上限仍可能帶來一次性的解析／配置負擔。

保留 red 證據：`red.log`／`red-stopped-process.json`（舊碼 I/O 失敗與高 CPU）；`red-additional.log`（重複 key、malformed links）；`red-encoding-handles.log`（非法 surrogate、CSV handle）；`red-display-revision-confirmed.log`（short alias 未失效）。中途 fixture 缺 `async_translate`、write stub 沒保留全部 varargs 的錯誤已修正，不能列為產品缺陷。

## 尚未完成

1. **generation／ack 輪替**：目前只辨識缺檔與縮短；Lua 無法識別同長或更大替換檔，亦未取得 native file ID。所有 request／response／failure／UI journals 的协调輪替仍需單獨實作。這輪不會主動縮減玩家紀錄。
2. **Broker startup replay I/O retry**：已於後續 [啟動歷史恢復](HISTORY-RECOVERY-20261004.md) 修補並驗證暫時檔案鎖恢復；未與 generation／ack 輪替整合。
3. **整體容量**：單行 byte ceiling 與 cache entry ceiling 都不代表整體 RAM／磁碟固定上限；動態 alias、公告引用生命週期與長期 soak 仍未結案。
4. **真機驗收**：此次是隔離 Lua/mock I/O 與 decoder 測试，未驗 native 字典實際熱載、遊戲畫面、FPS、physical IME、存檔往返。需要後續成套編譯／打包與隔離存檔實測。
5. **原版離線覆蓋率 ≥90%** 仍缺獨立驗證。整體 goal 保持進行中。

`verification.json` 保存本輪來源 SHA-256、各層通過數、量測及未發布狀態。既有 distribution／ZIP 不包含本輪修補；不得直接拿舊包上傳。
