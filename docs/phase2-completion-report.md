# 第二階段實作與部署報告

2026-10-01，Windows／PowerShell，全程主代理執行。

已完成玩家明確啟用的通用譯文分享、共識候選池、Workers AI 遊戲語意審核、自動簽章發布、撤回與本機設定介面。沒有帳號、OAuth、投票或人工審核網站。設定仍預設關閉，本次未啟用玩家投稿、未傳真實快取或存檔。

## 實作行為

Broker 只捕捉啟用後新產生且成功驗證的模型結果，安全模板的名稱仍留在本機。有限 outbox 原子持久化、去重、逾時、退避；停用不發新請求，已開始傳出的請求無法保證撤回。清除待送資料不動模型快取或官方庫。Lua 新增「共享投稿」第五頁、CC0 同意、開關、狀態、數量、錯誤與清除，保留 API／提示詞草稿、全域／存檔套用與取消、64／80 欄尺寸。

相同身分＋相同中文須至少三個裝置與三個不同網段 HMAC 訊號，才進審核。這是粗略來源分散判斷，不能證明三名獨立真人。每十五分鐘最多審兩笔、每日最多二十次，失敗退避最多三次；衝突候選阻擋。`@cf/openai/gpt-oss-120b` 檢查原意、Dwarf Fortress 語境、術語、繁簡、隱私、模板與惡意文字；七項全通過、approve、信心 ≥ 0.95 才核准。信心不是經量測的正確率，不確定或格式錯誤不收錄。

社群條目明確標記 `ai-reviewed`。保留內建／使用者修正优先，繁簡分包、JSON schema 1／rules df-zh-3、獨立官方層；不把官方資料混成模型快取。新版遊戲中待啟用，到關閉遊戲並重啟 Broker 才使用；Rust DLL 的現有批次格式可直接讀新條目，不需換 DLL。

新增独立 Ed25519 自動發布鍵與可信公鑰。私鑰只在工作區外受 ACL 保護的資料夾及專用 Worker secret；第一階段私鑰未上傳。每小時至多一版，有内容變更才發布。不可變对象＋雜湊＋簽章＋單調 sequence；先登記 D1 來源，再以原始 R2 ETag 條件切換入口，避免 D1 失敗後啟用無撤回追蹤的版本。修正待啟用版本在重啟時重新保留已撤回舊版的問題；損壞新版不能恢復已撤回版本。

## 譯庫來源與筆數

正式下載庫仍為 `2026.10.01.1`，繁中 502、簡中 502。來源是第一階段專案自有 CC0 文字與安全模板；簡中保留 OpenCC 轉換来源與未校正術語標記。生產 D1 的候選、支持均為零，正式 manifest SHA256 未改：

`0490074c251405c56a13259106b599e1d6e526766a8908bdc3dbd88c1c1df151`

Staging 四個合成共識案例：正確的社交需求譯文核准；否定反轉、把骨骼復位譯成「設定」、把角色主詞換成「肥碩頭盔」均拒絕。曾發布 `2026.10.01.auto-5`（繁中 503、簡中 502，含一筆 AI 核准），随后真的撤回該合成樣本，發布 `2026.10.01.auto-6`（各 502）。另有一筆隔離真 HTTPS outbox 投稿，只提供一個來源，未晉升。這些支持訊號全部是合成測試，不代表真三名玩家。

## 測試與量測

| 驗證 | 實際結果 |
| --- | --- |
| Broker 完整回歸 | 217/217 通過，約 6.59 秒 |
| 雲端 SQLite／共識／AI gate／發布故障 | 15/15 通過，約 0.15 秒 |
| Rust，包含隔離整包載入與既有整合項目 | 51/51 通過，无忽略項 |
| 真 DFHack Lua fixtures | 27/27 通過，含套用／取消／草稿／64／80 欄 |
| 安裝版標題設定介面 | 五頁正常，投稿關閉，開啟／關閉不套用 |
| 真 Workers AI 四筆審核 | 3.880、9.780、6.678、6.333 秒；1 核准、3 拒絕 |
| staging 真自動發版 | 切換整個管線約 7.24 秒 |
| staging 乾淨狀態真下載 | 繁中約 0.791 秒、簡中 0.997 秒；離線重載約 14.4 毫秒 |
| 正式服務乾淨狀態真下載 | 繁中約 0.870 秒、簡中 0.680 秒；離線重載約 14.4 毫秒 |
| staging 真 outbox 上報與收據 | 約 0.945 秒，待送從 1 清為 0 |
| 隔離 DLL 直接讀含 AI 核准資料 | 繁中 503、簡中 502 全命中，模型提交為零；全筆查詢約 1.07／0.86 毫秒 |
| 遊戲標題原生查詢 | 各 502 全命中，各測 50 筆色彩前綴，模型提交為零；內建优先保留 |
| 原生整包 prewarm fixture | 498 筆、82,416 bytes，讀取／驗證／發布約 10.72 毫秒，重複匯入零筆 |
| Worker 建置 | Wrangler dry-run、最新生成 binding types 與型別契約檢查通過 |

另驗證偽造簽章、錯誤雜湊、不相容／損壞內容拒收，斷網／中斷串流／磁碟失敗保留版本，同步去重、繁簡隔離、修正優先、私人名稱拒收、晚到模型不覆蓋、撤回不能當 fallback。結構驗證與四筆 AI 样本都不構成全部語意正確的證明。

## 部署及套件

- 正式 Worker：`https://df-zh-consensus.g402111111.workers.dev`，版 ID `3156e4df-c000-418f-8232-5dff4b9c761a`；審核／自動發布已啟用，15 分鐘 cron。
- 正式 D1：`df-zh-consensus`（`58f7a85b-4bf3-4f1a-bc67-7c742e8e20f8`）。
- 正式 R2：`df-zh-official-library`；下載入口 `https://df-zh-official-library.g402111111.workers.dev/manifest.json`。
- 獨立 staging Worker／D1／R2：`df-zh-consensus-staging`；staging 公鑰不在玩家信任庫。未使用 RimWorld 資源。
- 安裝位置：`C:\Users\g1061\AppData\Roaming\Bay 12 Games\Dwarf Fortress\mods\df-local-zh-complete`；部署改 16 個檔案，驗證 1,093 個檔案雜湊。僅在佇列清空後重啟正確 Broker，現場健康為無 API、待送 0、投稿停用、官方 502 可用。
- ZIP：`_localization-work/standalone/df-local-zh-complete-consensus-ai-phase2-20261001.zip`，44,095,177 bytes；1,094 個 ZIP 項目含 manifest，全部 SHA256／CRC 驗證，無私人狀態／私鑰／玩家 API Key。
- ZIP SHA256：`354b42b4a95de84abf9bbf4925b9340fadb8587da87c3f844574ed30efdbc824`。
- 最終秘密掃描逐檔比對八個已知私人秘密值（不列印值），1,093 個檔案均無匹配，亦無私鑰或私人狀態檔。
- 此完整模組 ZIP 仍僅供本機使用；既有上游中文資料的公開再散布許可未解決，不能把它當公開官方譯庫包上傳。R2 上傳的官方譯庫只含可分享來源。

DLL 全程未替換，SHA256 保持：`a49cfe97c843c68523a2d1c268ffb64ca29b7459d56fe12afec99ef698996234`。遊戲測試只在標題畫面，未載入或修改存檔。

## 私人資料、備份與回復

部署前 163 個使用者狀態／快取檔案基準：157 個保持相同，4 個正常生成檔更新（公開設定快照、狀態、顯示別名匯入 CSV、譯庫狀態），2 個程序鎖定的 stdout／stderr 日誌基準無法取得雜湊，不宣稱通過。API 私人設定、settings.json、名稱註冊、模型 journal 的雜湊均保持相同；原始快取其餘檔案亦匹配。沒有刪除測試使用真實 API 設定。

來源備份：`_localization-work/backup-20261001-consensus-ai-source`。
部署變更備份：`_localization-work/backup-20261001073349151-native-prewarm-deployment`，內有 `deployment.json` 及部署前 manifest。需要回復時先確認 DF Broker 已閒置，停止該服務，按清單把備份檔及舊 manifest 還原到安裝套件，再由 `broker/Start-Broker.ps1` 啟動。不要回復／刪除 `dfhack-config` 的私人設定或快取，也不要動其他 Node。新增兩個 shared 模組可保留為未引用檔；若清理，只針對該部署清單的新檔。

雲端維護与撤回命令見 `community-cloud/README.md` 及 `operator.mjs`。緊急停收／停審／停發布可關相應 Worker vars 後部署；錯誤譯文用帶理由的 withdraw 發更高 sequence 修復版，不能直接倒退 manifest。自動簽章鍵輪換時要先配送新公鑰；舊 Broker 不認新鍵會拒收並保留舊包。

## 尚未實際驗證

尚未進行真實三名玩家、不同實際網段的長期共識測試，亦未測所有角色／健康／裝備畫面與存檔重開的視覺效果。沒有廣泛量測 AI 語意准确率、惡意群體操縱抵抗率或翻譯覆蓋率；不承諾 99%。NAT 可能阻擋共識、裝置 ID／VPN 可以偽造來源分散，AI 仍可能錯誤核准。候選與發行成長到大规模时仍需容量與效能量測。

主要證據：`phase2-broker-tests.log`、`phase2-cloud-tests.log`、`phase2-rust-tests.log`、`phase2-lua-tests.log`、`phase2-staging-ai-results.json`、`phase2-staging-download.json`、`phase2-staging-withdrawal.json`、`phase2-production-verification.json`、`phase2-private-hashes.json`、`phase2-ai-row-dll.json`、`phase2-zip.json`。

## 2026-10-01 授權紀錄更新

使用者確認自己是上游維護者 `anln666`，並明確允許修改、繁簡轉換，以及在免費模組與雲端譯庫中再散布
`https://github.com/DFI18n/dfi18n-data-zh-hans` 的資料。現已固定記錄 commit
`2ed0ac42a43375ce1d3d3fcd1403f825be58b3e6`、CC BY-NC 4.0、中文維基翻譯組／WAN1694／anln666 署名、變更標示與非商業條件。

這項授權只針對 GitHub 資料來源；Steam Workshop 頁面的來源紀錄仍維持未授權狀態。正式 R2 `2026.10.01.1` 沒有因此重建，仍是繁中 502、簡中 502 的自有 CC0 包，避免把來源錯標或把未重新整理的資料混入正式庫。

本輪重新組裝 standalone 包並部署到本機安裝目錄：1,097 個檔案驗證；授權檔同步修正後最後一次部署實際改 4 個檔案，DLL 雜湊仍為
`a49cfe97c843c68523a2d1c268ffb64ca29b7459d56fe12afec99ef698996234`。授權重新整理 ZIP 為
`standalone/df-local-zh-complete-license-refresh-20261001.zip`，SHA256
`7dd8ff7c3fd1c639045a8e092981501b7bf796fc36d49f21859b7c757533aa53`，大小 43,991,624 bytes，1,098 個 ZIP 項目（含 manifest），逐項雜湊無誤。
API 私人設定與 `settings.json` 雜湊在部署前後一致；官方 R2 沒有重新發布或改版。
