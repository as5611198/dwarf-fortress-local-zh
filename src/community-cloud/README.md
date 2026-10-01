# Dwarf Fortress 共識與 AI 語意審核

專用正式服務：`https://df-zh-consensus.g402111111.workers.dev`。
發行入口：`https://df-zh-official-library.g402111111.workers.dev/manifest.json`。
只使用本專案 `wrangler.jsonc` 中的 DF 專用 D1／R2，不使用 RimWorld 資源。

玩家在「共享投稿」頁套用啟用後，Broker 才分享之後成功產生且通過保守過濾的通用 AI 譯文。啟用表示同意 CC0-1.0；不掃描舊快取。隨機裝置識別與網段 HMAC 是節流／來源分散訊號，不是經驗證的真人身分。網段採 IPv4 /24、IPv6 /64，原始 IP 不入 D1；停用預設 invocation logs，應用程式只記固定診斷碼。

三個裝置＋三個網段提供完全相同中文後進入候選審核。Worker 每十五分鐘最多審兩筆，每日最多二十次，失敗最多三次並退避；共識冲突阻擋。Workers AI 的 `@cf/openai/gpt-oss-120b` 檢查意思、遊戲語境、術語、繁簡、隱私、模板及惡意文字，必須全部通過且 confidence ≥ 0.95。信心是模型自述，並非校準過的正確率。譯文標記 `ai-reviewed`，不冒充人工校正；模型不會另造替代譯文。共識與 AI 仍可能被操縱／誤判，NAT 使用者也可能達不到門檻。

每小時至多發布一次；保留原始自有 CC0 基底、分繁簡包、不可變發布、單調 sequence、Ed25519 簽章與 R2 ETag 條件切換。使用新獨立自動簽章鍵，第一階段私鑰未送雲端。舊客戶端沒有新公鑰時會安全拒收；更新 Broker 後才接受自動版。玩家停用上報或下載仍能使用已下載官方譯庫。遊戲中只暫存新版，到關閉遊戲並重啟 Broker 才啟用。

## 維護命令

在本目錄使用 `node node_modules/wrangler/bin/wrangler.js`，不要套用其他專案的 CLI 設定。

```powershell
node node_modules/wrangler/bin/wrangler.js whoami
node node_modules/wrangler/bin/wrangler.js d1 migrations apply df-zh-consensus --remote
node node_modules/wrangler/bin/wrangler.js deploy
node operator.mjs production run
node operator.mjs production withdraw <candidate-id> "具體撤回原因至少八字元"
```

operator 在記憶體讀取工作區外 `C:\Users\g1061\.df-zh-publisher\consensus-production-secrets.json`，不列印秘密。私鑰檔限制為本人與 SYSTEM；禁止把該資料夾放入 ZIP／原始碼／日誌。首次建立鍵使用 prepare-keys，但**現有部署不可重跑**，以免輪換鍵及覆寫已啟用配置。

撤回將候選停用，發新簽章版本、撤回所有已記錄包含該候選的版本。既有原始條目保留。失敗時舊入口保留，修復 R2／D1／AI／金鑰問題後重試；健康檢查不揭露候選或私人資料。緊急停用請將 vars 的 `COLLECTION_ENABLED`、`REVIEW_ENABLED`、`PUBLISH_ENABLED` 設為 `false` 並部署；已安裝包仍離線可用。不要把 R2 manifest 直接倒退到低 sequence；以更高簽章版本修復或撤回。

## 測試與限制

```powershell
node --test test/*.test.mjs
node verify-upload.mjs
```

`seed-staging.mjs` 只產生 staging SQL，必須明確對 `df-zh-consensus-staging --env staging` 執行；合成 supports 不代表三名玩家。獨立 staging 金鑰不在玩家信任庫。`verify-staging.mjs` 使用乾淨 Temp 状態下載含一筆 AI 核准樣本的版本；撤回後它不再適用，須在另一輪 staging 發布後執行。`verify-withdrawal.mjs` 從保留的已簽章歷史包重建隔離 fixture，驗證延後啟用與撤回。測試不修改玩家設定／存檔。

四筆真 AI 實測不代表廣泛語意准确率，尚未經真實多玩家、多網段或存檔畫面驗收。所有模型声明均為不可信客戶端資料；來源可再散布權限仍依自有來源及玩家 CC0 同意，不能自動判定他人的著作權。
