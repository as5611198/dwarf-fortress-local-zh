# 繁簡整合包發布

公開包使用 `standalone-bilingual` 模式；不以玩家 active mod 或 Workshop `3635900931` 作為組包來源，也不需要另訂 DFI18n `3613958631`。玩家必要環境只有 Windows DF 53.16 與 DFHack 53.16-r1.1。Rust 背景服務隨包附帶，玩家無需 Node.js。

## 重建

以下是開發者流程：在 `src/broker` 執行 `npm ci --ignore-scripts`。在 `src/df-local-zh-native` 設定 `$env:RUSTFLAGS='-C target-feature=+crt-static'`，執行 `cargo build --target x86_64-pc-windows-msvc --release -p df-local-zh-broker -p df_local_zh_core`，使所有相依套件採一致的靜態 CRT。Broker 啟動 DLL 由 `src/broker/launcher.cpp` 使用 MSVC `/std:c++17 /LD /MT /EHsc` 建置。確認 EXE/DLL 的系統依賴，再組包；不可沿用舊 Node 啟動器。

從倉庫根目錄執行：

```powershell
node src/broker/prepare-standalone-package.mjs --version=0.5.0 --native-dll=src/df-local-zh-native/target/x86_64-pc-windows-msvc/release/df_local_zh_core.dll --broker-exe=src/df-local-zh-native/target/x86_64-pc-windows-msvc/release/df-local-zh-broker.exe
node src/broker/validate-workshop-package.mjs distribution/steam/df-local-zh-complete
cd src/broker
npm test
```

預設只讀取固定授權來源 `vendor/dfi18n-data-zh-hans`、`src/data-patches` 與明確列出的公共靜態資料；檢查來源 SHA256，將繁簡放到各自語言目錄，保留字型與授權。不得以 `--allow-unverified-upstream` 發布本包。CC BY-NC 資料不得混入 CC0 官方雲端包。

## Steam

已發布的項目：[3811313433](https://steamcommunity.com/sharedfiles/filedetails/?id=3811313433)。後續更新必須使用這個 publishedfileid，避免重複建立項目。

更新 VDF 的 contentfolder、previewfile、版本與描述；初次建立時 publishedfileid 為 0。上傳成功後以 Steam 回傳的 ID 作後續更新。

SteamCMD VDF 使用官方文件列出的純量鍵值欄位：appid、publishedfileid、contentfolder、previewfile、visibility、title、description、changenote。不可把只含值的 tags 陣列直接寫成 KeyValues 區塊；該格式會在區塊結尾發生解析錯誤。模組 info.txt 的 STEAM_TAG 與 SteamCMD VDF 是不同介面。

Workshop 的 Required Items 不應加入 DFI18n 本體或外部中文資料包。DFHack 是執行環境，玩家仍須安裝它。保留署名、非商用條件、修改說明，不宣稱上游對本專案背書。

必須另外記錄 Steam 上傳成功、乾淨訂閱與遊戲載入結果；validator、Broker 或 Rust 測試通過不能代替實際遊戲驗證。上傳登入應由玩家自己輸入 Steam 密碼與 Steam Guard，工具不得讀取或記錄。

2026-10-01：SteamCMD 上傳 0.3.1 成功，並在獨立 SteamCMD 目錄重新下載（56,383,177 bytes）。下載包 validator 驗證 743 檔，manifest 及全部列出檔案 SHA256 與發布包一致；繁簡離線重載／使用者修正及缺 DLL 拒收測試 3/3 通過。公開頁面沒有外部 Required Items。尚未完成 Steam 客戶端訂閱後的遊戲畫面實測。
