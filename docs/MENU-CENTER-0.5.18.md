# 主選單副標與存檔目的地選單：0.5.18

日期：2026-10-02。此輪僅補固定譯文與置中資料；原生輸入橋、搜尋繪製及 IME 操作沒有修改。

## 根因與譯文來源

玩家畫面的副標實際原文是 `Histories of Jealousy and Perseverance`，不是先前代理猜測的 Greed。DF 會組合不同的副標詞彙。既有 `local-reviewed.csv` 已涵蓋五種第一詞與十一種第二詞，卻漏掉 Perseverance。舊編譯器有此組合，但目前 standalone 打包直接讀來源 CSV，因此成品實際缺少五句。

私人 `translations.jsonl` 有 `嫉妒與毅力史`，原生快取對同一句的 alignment 是 left。翻譯紀錄未保留生成模型欄位，shared journal 中也沒有此句的模型證據，不能判定由 Gemini 或 DeepSeek 產生。

遊戲內存檔目的地選单的原文是 `Save to this timeline`、`Save to new timeline`、`Save to new folder (same timeline)`，不是原本已有 CENTER 的 `Save and return to title menu` 等選項。三句及兩句說明都漏固定譯庫，因此快取用 left 排版。玩家於 0.5.17 確認三個主選項已置中，再回報 `Recommended!` 仍偏移；這句也是獨立的 left 快取，0.5.18 一併補上。

## 變更

- 在來源 `src/data-patches/simple/zh-Hant/local-reviewed.csv` 補十一句 `[ALIGNMENT:CENTER][REVIEWED:1]`：五個 Perseverance 副標、三個存檔目的地、兩句說明、`Recommended!`。
- 副標改為「嫉妒與堅毅的歷史」等完整語句；存檔選項統一使用「時間線」。推薦標記保留「推薦！」。
- 舊 `compile-data.mjs` 的 Perseverance 用詞也同步為「堅毅」，避免另一條打包路徑使用不同譯文。
- standalone 既有繁轉簡流程產生簡體对应的十一句；兩種語言的 CENTER／REVIEWED 標記逐項核對。沒有修改固定的上游 vendor 快照。
- Rust 只新增 `#[cfg(test)]` 內的來源譯庫與錯誤快取優先級回歸；production Rust 程式未改。

## 驗證

- 副標測試在修正前失敗於缺少 Perseverance 固定條目，修正後通過。
- 存檔目的地測試在修正前失敗於缺少固定條目；玩家發現推薦偏移後，擴充同一測試，先確認 Recommended 條目缺失失敗，再補資料。
- 核心最終 60 passed、0 failed、5 ignored。Windows 靜態 CRT release build 成功。
- 真實遊戲在玩家開好的存檔目的地畫面，以公開既有 trace API 讀取原文座標：this timeline (80,30)、new timeline (80,33)、new folder (73,36)、Recommended (84,31)。沒有截圖，也未觸發任何存檔操作。
- 部署後實際遊戲 `MENU_TEXT_ACCEPTANCE passed 11 translations and width bounds`；所有新譯文可優先讀回，且 glyph 欄寬不超過原英文的區域。
- 0.5.17 三個主選項已獲玩家視覺驗收。0.5.18 推薦標記的視覺驗收與回到主選單查看副標仍待玩家確認；不能把資料／alignment 回歸等同完整 UI 畫面驗收。

## 成品與資料保留

- 最終 ZIP：遊戲目錄 `_localization-work/ime-validation/candidate-fix18-package/df-local-zh-complete-0.5.18-windows.zip`。
- 套件與 ZIP 的 829 payload SHA-256 逐項符合 manifest，且 ZIP 沒有額外檔案。
- ZIP SHA-256：`7BBB94575380EE5E25EFA846BCA439E268CFA46AAEE84C18FE154E4358DD6271`。
- 此轮 production Rust 沒有變更，成品沿用已驗證的 0.5.16 原生 DLL／broker。重新 release 編譯的 DLL 是獨立建置結果，未拿來替換執行中的 DLL；不宣稱其位元組相同。
- 成品及實際載入 DLL SHA-256：`940C309A3586B72FA4A8D1455239253B7F0EFE7DCDB7B2925BA549F1469F2BD9`。
- `Deploy-PreparedData.ps1` 先驗證全部檔案，只准兩份 local-reviewed CSV 與版本 metadata 變更，任何 binary／script 不符都拒絕。0.5.17、0.5.18 各 changed=4、verified=829、protected=5243、runtimeUpdates=0、binaries_replaced=0。
- 部署後用既有 `load_simple_dict` 在當前遊戲載入繁體、簡體資料，玩家的世界仍保持開啟；沒有關閉／重啟或存檔，不替換任何 DLL／EXE。
- 備份：`backup-candidate-fix17-before-deploy-20261002` 與 `backup-candidate-fix18-before-deploy-20261002`，位於 `_localization-work/ime-validation`。保留私人設定、API、存檔、草稿、名稱及翻譯快取；沒有清除錯誤舊快取，固定譯庫優先覆蓋其顯示。
- 未 commit／push，未更新 `distribution/steam`。

## 設定頁為何可能補譯

程式先查固定譯庫與本地規則，再查快取／補譯，並非整個設定頁都交給 AI。固定上游快照有 Settings、Audio、Keyboard cursor enabled、Compressed saves 等條目。私人補譯紀錄目前查到的設定片段例子 `Autosave` 與 `Display water and magma ` 在上游 CSV 沒有精確條目；上游另有 `Autosave frequency`。這提供字串不相同的實例，但仍須依玩家指的設定頁及實際繪製文字逐項核對，不能只由快取中有舊紀錄推論當前仍在调用 AI。
