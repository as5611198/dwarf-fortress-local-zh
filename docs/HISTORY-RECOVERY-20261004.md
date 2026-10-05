# Broker 啟動歷史恢復（2026-10-04）

延續 [佇列讀取修補](JOURNAL-READERS-20261004.md)／[遊戲端讀取修補](LUA-JOURNAL-READERS-20261004.md)，處理原先明確保留的 startup I/O retry 缺口。版本仍為 0.5.11 候選來源，未安裝、打包或發布。

## 問題與修補

舊版在 `runtime-responses.jsonl` 或 `runtime-failures.jsonl` 暫時被鎖定時，記錄錯誤後直接進入 dispatch。未讀回的完成紀錄與重試額度被當成不存在，可能重做已完成／已達終止重試的工作。

新增 `broker-rust/src/runtime_history.rs`：

- 用一個受監管的 async task 讀取兩種歷史，沿用 64 KiB chunk、8 MiB record framing；兩個快照全部成功後，才發布 bounded completed／failure maps。中途失敗不提交部分歷史。
- 歷史未恢復期間，只暫存 runtime journal 待辦，不啟動這些翻譯工作。主 loop 繼續處理設定信箱、狀態發布及既有服務；此 gate 不涵蓋獨立 HTTP API 路徑。
- I/O 錯誤及 task panic／取消都進入退避重試：1、2、4、8、16 秒，之後最多每 30 秒一次。錯誤原因相同時不重複刷 log，狀態包含 attempts、bytesRead、error 與 retryAt。
- 每讀完 chunk 回報進度；只有 **30 秒沒有進展**才要求取消，不因大歷史的總讀取時間較長就反覆重頭開始。取消完成前不建立第二個 reader。Recovery 被 drop 時會 abort 所有自己持有的讀取任務。
- 成功恢復後，重新讀取 request journal，並依當下 world／language／retry generation 過濾。等待期間變更範圍不會讓旧世界工作在恢復後執行。
- 現有狀態面板顯示「恢復翻譯紀錄」或「紀錄讀取重試中」。沿用原列與座標，不增加一排而擠到按鈕；失敗不再顯示成一般收集文字。

## 驗證與證據

證據目錄：遊戲目錄 `_localization-work/history-recovery-20261004/`。

| 驗證 | 結果 |
|---|---|
| Windows 真實 sharing violation | `red-lock-confirmed.log` 舊碼在 response 檔被 exclusive handle 鎖住時仍 attempted=2；新碼在鎖住 response／failure 兩種檔案時 attempted=0。設定 save 成功回覆、retrying 狀態可見，解鎖後不需要新請求即恢復，只派送新 Wounds。原 Health 的 completed 或 terminal failure 保留。 |
| 世界／語言切換 | 用目錄取代 response path 造成真實開檔失敗；等待時從 old／zh-Hant 切到 new／zh-Hans，修復檔案後只新增 new 世界「伤口」回覆，attempted=1，舊世界不重送。 |
| 監管／資源生命週期 | 四項 unit tests：退避上限與溢位、進度延長 watchdog／真正停滯取消、drop 釋放任務資源、panic 經退避後重新成功而不永久 Pending。 |
| 全套 Broker release tests | `broker-final.log`：**114 passed、0 failed、7 ignored**（79 unit、3 equipment、7 Tail integration、25 runtime）。未執行四個明確 benchmark、兩個指定套件／語料案例與 live cloud download。 |
| 狀態 UI | `status-red.log` 舊碼缺少恢復狀態；`status-green.log` 新 loading／retrying／ready，以及原繁簡 label、snapshot 快取、14／16 列 bounds、release／test overlay 案例通過。使用 bundled Lua 與 mock GUI，非實機截圖。 |
| 最終編譯 | `build-final.log`：Windows x64 release、static CRT 成功；既有 workspace manifest／provider deprecated atomic API warnings 保留。 |
| 差異檢查 | `git diff --check` 通過；hash 與測試摘要見 `verification.json`。 |

兩項新 runtime 故障驗證均以暫存 state、AI 關閉下的固定字典執行，provider requests=0；它們證明 journal dispatch 行為，沒有宣稱真實遠端 API 或遊戲畫面驗收。本輪沒有修改玩家設定／cache／save。

保留中途 fixture 錯誤：第一版 active-context 缺 version、settings 使用不存在的 snapshot action，以及在每 500 ms 狀態刷新前就斷言 retrying。修正為有效 context／save 操作，並等待可觀測狀態；沒有靠延長產品 timeout 或移除斷言讓測試通過。panic 測試 log 中的預期 panic 已被 supervisor 處理，對應 test result 為 pass。

## 範圍與未完成項目

- 這是啟動歷史恢復，不是 request／response／failure／UI journal 的 generation／ack 輪替。檔案仍可能長期增加，Lua 對同長／更大替換檔的辨識仍待協定支援。
- 真正持續無法讀取歷史時，runtime journal dispatch 會保持等待，顯示重試狀態；不會以清空歷史來繞過錯誤。需要作業系統恢復存取權限／鎖定後才會前進。
- 任務取消為協作式。watchdog 不保證能在 30 秒強制中斷卡在 kernel 的同步磁碟 read；會等該 reader 結束，避免不斷產生第二個 reader。單次正常 read 有 byte budget，沒有本輪真實硬體 I/O 永久阻塞測試。
- 沿用單一 Broker writer 假設；兩個 history 檔案間沒有跨程序交易。外部程序同時改寫、輪替或刪除仍需後續 generation 協定。
- bounded maps 仍是 completed 32,768／failure 4,096 條，非整體 RAM 固定上限。A026／A027 動態 alias／公告引用、FFI、實體 IME、多模式長期 soak、存檔與 ≥90% 離線覆蓋率仍未全部結案。

新 Broker 產物仍在 `_localization-work/rust-durable/x86_64-pc-windows-msvc/release/df-local-zh-broker.exe`；舊 distribution／ZIP 不含此修補。後續交付須成套重建、打包及遊戲驗收。
