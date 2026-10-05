# 單句停留在「收集文字」：一般請求過濾與校訂索引遺漏

2026-10-03，玩家在人物個性／價值觀頁觀察到只剩一行英文卻遲遲未送模型。
玩家確認後來翻好的正是含 `leisure time`、`He dreams of raising` 的畫面片段。
本次對安裝基底 0.5.21 套用本機修正；沒有發布版本或重新啟動遊戲。

## 證據與根因

1. Lua 寫入的要塞一般文字請求只有 world、language、text、priority，沒有 visibilityId。
   當時 runtime-visible.json 的 ids 為空，請求檔有目前世界的 232 種文字，
   broker runtime attempted/published/failed 卻全部是 0。
   Rust run_background 在讀入與保留工作時，對所有請求強制要求 visibilityId 位於可見集合，
   因此一般文字被靜默丟棄。原 Node 佇列僅對視窗綁定的請求執行此限制。
2. 更新 broker 後，實際呼叫遊戲 runtime.translation 驗證，發現另一個可重現例外：
   安裝包缺少 broker/data/reviewed-text-keys.json，而 reviewed-text Lua reader 用 assert 開啟檔案。
   人工校訂查詢位於一般譯文快取查詢之前，因此即使完整段落已翻好，也可能在讀取時先拋錯。
   已有的 buildArenaCorrections 會產生索引，但 standalone 打包入口沒有呼叫它。

玩家確認的片段在 2026-10-02T16:35:21.553Z（台北 00:35）透過原生 DLL 的獨立翻譯路徑完成；
這與 Lua 整句佇列 attempted=0 可以同時發生。原生快取另有 20 秒 miss 抑制視窗，
但缺乏該片段第一次出現到送出的完整時間線，不能把它此次的等待秒數全部歸因於此設定。
模型批次器沒有最低句數限制；有一筆即可派送，排程 tick 為 20 ms。

## 修正

- Rust 共用 runtime_request_current 檢查：一般文字保留世界邊界；只有具有視窗／Legends 身分的請求要求可見性。
  同時套用於新請求讀入與既有工作保留，避免下一輪再被刪除。
- reviewed-text reader 對缺檔／無效 JSON 回傳無人工校訂結果，繼續使用既有翻譯路徑；
  空索引也只讀一次，避免逐幀重新探測檔案。有效的繁簡校訂仍優先。
- standalone 打包呼叫既有 buildArenaCorrections，產生索引與相符的繁簡字典，再建立 manifest。

## 驗證

- Rust 實際背景工作者＋暫存 JSONL＋本機模擬 HTTP 模型：各只有一筆前景／背景文字，
  可見集合為空。修正前兩測試均因 2 秒內沒有輸出而失敗；修正後約 147–148 ms 完成，
  各恰好呼叫模型一次。這是模擬模型往返，不是真實模型生成延遲。
- Rust 全套 27 個測試通過，1 個需要雲端下載的測試依原設計忽略；MSVC 靜態 CRT release 建置成功。
- 新 Lua 測試 runtime-reviewed-fallback.lua 在修正前重現缺檔 assert；
  修正後驗證缺檔、損壞 JSON 均可讀取模型譯文，有效索引仍提供繁簡人工校訂，且重複查詢只讀一次檔案。
- standalone 新增索引與繁簡原生字典一致性測試；舊安裝包因缺索引失敗。
  隔離建立 0.5.21-local-runtime-fix 套件後，4 個 standalone 測試全部通過，838 個檔案通過套件驗證。
- 本機部署只替換 broker、reviewed-text Lua 並補上索引；保留先前 names-worker 效能修正。
  安裝 manifest 的 832 個 payload 雜湊全部相符，設定與私有 API 檔、active-context 雜湊不變。
- broker PID 4508 停止後，第一次覆寫遇到短暫 Windows image lock；確認程序與監聽埠均已消失後重試成功。
  新 PID 14332 監聽 127.0.0.1:19753，health engine=rust。
- 00:55:49 快照：目前世界 232 種請求，228 筆完成；累計 241 次嘗試、13 次失敗（包含重試），
  剩 4 種未完成。遊戲端直接查詢 5 段含 leisure time 的完整價值觀文字均可取得譯文。
  遊戲 PID 38992 保持運行且暫停，取樣 FPS 49–50。

尚未完成的 4 種文字為三種 `{... Remains}` 與一種 `{DWARF_NAME} likes ...` 模板，
各已嘗試 3 次。錯誤記錄只有 translation failed，尚未隔離其模型／驗證失敗原因；
不把它們列為本次已修復，也不把伺服器完成等同於全部畫面的視覺驗收。

## 本機產物

備份、部署紀錄、隔離測試套件與即時驗證 JSON：
`_localization-work/runtime-queue-fix-20261003/`（遊戲根目錄下，非公開套件資料）。

安裝 broker SHA256：`57a255f247016df5fe1c7f402227c1d7c0c670f483081e02d7cdddf69fbf2049`。
安裝 reviewed-text Lua SHA256：`5075bd5846aa8a0c0a47963144a1bf69fa22b9b4adade5bbb5a96926f1435762`。
安裝 reviewed-text 索引 SHA256：`65dbd3fb79c7779dc37c2d626a1e8a668179c6461300c3b1d6e3df6d8391fb25`。
