# 繁簡整合包發布

公開包使用 `standalone-bilingual` 模式；不以玩家 active mod 或 Workshop `3635900931` 作為組包來源，也不需要另訂 DFI18n `3613958631`。必要環境只有 Windows DF 53.16 與 DFHack 53.16-r1.1；選用 Broker 功能另需 Node.js。

## 重建

在 `src/broker` 執行 `npm ci --ignore-scripts`，在 `src/df-local-zh-native` 執行 `cargo build --release -p df_local_zh_core`。Broker 啟動 DLL 由 `src/broker/launcher.cpp` 建置，或沿用經驗證的 `df-broker-launch.dll`。

從倉庫根目錄執行：

```powershell
node src/broker/prepare-standalone-package.mjs --version=0.3.1
node src/broker/validate-workshop-package.mjs distribution/steam/df-local-zh-complete
cd src/broker
npm test
```

預設只讀取固定授權來源 `vendor/dfi18n-data-zh-hans`、`src/data-patches` 與明確列出的公共靜態資料；檢查來源 SHA256，將繁簡放到各自語言目錄，保留字型與授權。不得以 `--allow-unverified-upstream` 發布本包。CC BY-NC 資料不得混入 CC0 官方雲端包。

## Steam

更新 VDF 的 contentfolder、previewfile、版本與描述；初次建立時 publishedfileid 為 0。上傳成功後以 Steam 回傳的 ID 作後續更新。

Workshop 的 Required Items 不應加入 DFI18n 本體或外部中文資料包。DFHack 是執行環境，玩家仍須安裝它。保留署名、非商用條件、修改說明，不宣稱上游對本專案背書。

必須另外記錄 Steam 上傳成功、乾淨訂閱與遊戲載入結果；validator、Broker 或 Rust 測試通過不能代替實際遊戲驗證。上傳登入應由玩家自己輸入 Steam 密碼與 Steam Guard，工具不得讀取或記錄。
