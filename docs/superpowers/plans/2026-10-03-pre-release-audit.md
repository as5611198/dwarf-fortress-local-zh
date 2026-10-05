# 漢化與輸入法發布前深層審查執行計畫

**Goal:** 完成所有第一方漢化、Rust broker、原生輸入與 Lua 橋接的風險盤點；修補確認問題並驗證可交付套件。
**Architecture:** 依資料生命週期追查來源收集、佇列、模型、快取、畫面與存檔邊界。每個缺陷先建立可重現證據，再做最小修補、回歸測試與安裝驗證。
**Tech Stack:** Rust/MSVC、C++、DFHack Lua、Windows SDL/IMM/TSF、Node.js 建置與測試工具。
**Spec:** 本對話 2026-10-03 使用者提出的六維度 Comprehensive Pre-release Audit，並納入其他發布風險。

## 全域限制

- 主代理獨立執行；使用者未允許子代理。
- 已獲授權正常保存退出與重啟遊戲；需要偏好時採推薦方案。
- 保留開始前所有未提交工作；基線 patch、狀態與來源雜湊保存在遊戲根目錄 `_localization-work/pre-release-audit-20261003/`。
- 禁止把玩家存檔、私有 API 設定或執行時資料加入發布包。
- 真實遊戲驗證、模擬測試與靜態審查分別列明；不能把未發現缺陷當成不存在缺陷的證明。
- 不推送或發布 Workshop；產出本機可審核套件、修補檔與審查報告。

## 執行順序與驗收

- [x] 1. 基線：清點所有第一方程式、確認來源與安裝包差異，執行 Rust workspace 與 Node 測試並保存輸出。
- [x] 2. 佇列與非同步：逐讀 broker service/provider/settings/common、native cache/tasks/translation、Lua runtime/prefetch/visible；
  用本機假模型測試單句、部分錯誤、逾時、重試、世界／語言切換、取消、舊回覆、檔案截斷與容量限制。
- [x] 3. 熱點：逐讀 hooks/glyph/screen/text 與 Lua 所有 render/timer 路徑；
  對實際模組用探針計數腳本解析、檔案讀寫與每次更新成本，保留 50 FPS 基準。
- [x] 4. 編碼與輸入：逐讀 cp437_string、search_text/input/ime_windows、search-editor/unicode/rename；
  測 UTF-8 補充平面字、錯誤序列、IME UTF-16 游標、ANSI 退路、剪貼簿所有權、退格與長度邊界。
- [x] 5. 資源與存檔：逐讀所有長壽命 cache、紋理、Windows/COM/SDL 資源擁有權與 native pointers；
  重複世界／語言切換與高唯一文字量測試；備份存檔後驗證正常保存、重新載入及原版名稱安全退路。
- [x] 6. 例外與發布：檢查所有捕捉／忽略錯誤的狀態回復與可觀察性、HTTP 邊界、設定原子寫入、程序生命週期與 package validator。
- [x] 7. 對確認缺陷逐一補回歸測試、先記錄失敗再修正；只在新增改動或未解問題需要時重跑相關測試。
- [x] 8. 最終整合：全套測試、release build、乾淨隔離打包、payload 雜湊及私有資料掃描；正常退出後安裝、啟動並載入已備份世界。
- [x] 9. 交付：風險表列嚴重度、觸發方式、檔案、修補、測試與剩餘限制；輸出僅本次增量 patch、可安裝套件及校驗檔。

## 審查紀錄規範

每項 finding 使用 A001 起算的穩定編號，狀態分為 confirmed/fixed/verified/deferred。
驗證記錄使用實際命令、退出碼、必要的測量或断言結果；既有失敗與本次造成的失敗分開。
安全退路不得靠全域關閉功能或吞掉例外維持表面成功。

## 最終狀態

已完成本輪審查、確認缺陷修補及候選版交付流程。完整風險與剩餘發布條件見 [審查報告](../../PRE-RELEASE-AUDIT-20261003.md)。勾選代表本輪流程已執行，不代表所有風險已根除；A026–A030、A034 等項目仍未結案。
