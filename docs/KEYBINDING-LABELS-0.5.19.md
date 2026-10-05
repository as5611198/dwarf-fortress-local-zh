# 0.5.19 按鍵綁定鍵名原文保護

設定的 Keybindings 頁原先會把 Enter／Numpad Enter 等鍵名翻成回車。
已確認上游簡體固定譯庫也含鍵名譯文，不能只刪除 AI 快取解決。

Lua 每個 frame 唯讀公開 DFHack `main_interface.settings` 結構，只收集目前類別
`keybinding_binding_name` 的 std::string 地址、原文與長度。
Rust 使用独立暫存 literal namespace，在 addst／addst_flag／top_addst 以地址加原文
精確匹配，直接繪製原文且旁路譯庫、補譯快取與 developer-mode 翻譯請求。
只有使用者主動啟用的 trace 仍可記錄這些繪製事件。

批次上限 2048，僅接受非空可列印 ASCII、原文等於顯示文字、寬度等於原文長度；
原本中文 display rows 的 256 筆與中文內容驗證維持不變。
兩個 namespace 獨立；literal 沒有座標 fallback，受世界／語系／5 秒 TTL 約束。
切換類別替換批次，離開頁面或停止 adapter 清除批次，世界切換後重新排程。
沒有改綁定、原生字串或全域 Home／End 翻譯，也沒有使用私有 SDL 位址或外部原創碼。

## 驗證

- Rust 新增兩個測試，先在原 display-row stub 失敗，再於獨立 literal 實作通過。
- 核心測試：62 passed、0 failed、5 ignored（原有需要外部環境的整合測試）。
- Lua fixture：341 筆類別、自訂鍵、換類別、控制字元拒絕、其他頁籤／關閉清除、重排程、唯讀欄位通過。
- 真實遊戲：繁／簡各四個類別，341／103／100／91 筆，八組皆有 native draw hits。
- 八組測試前後所有按鍵名稱相同。切至 Audio，literal_rows=0；回到 Keybindings，literal_rows=341。
- 動作說明繼續使用原翻譯流程；Select 讀回「選擇」。部分未命中說明保留既有行為。
- 安裝版 SEARCH_LITERAL_RENDER 回歸測試通過。
- 未截圖；玩家畫面觀感與實際改綁定操作仍待玩家確認。

## 成品與部署

靜態 CRT release 已重新編譯。建置、ZIP 與 831 payload 驗證完成後才關閉遊戲。
使用者確認無未儲存進度，停止遊戲與該安裝樹 broker，部署後重新啟動。
部署 changed=7、verified=831、protected=5243；私人設定、快取、名稱與存檔 hash 未變。
首次停機後部署 guard 仍看到退出中的遊戲，拒絕寫入；確認進程已結束後再次部署成功。
新進程確認載入 AppData 安裝樹的新 DLL，最終保留原語系與 Keybindings 一般類別頁供驗收。

- DLL SHA256：`5C8E9019148692936FE5AEBC4AA4B83268FC8311A3F6865B1BE53988DFAC0C74`
- ZIP SHA256：`2A13E8BC8F8A4CEF487E99E5BF30B32FEE6DF51132A04AFB4BE094604DD31559`
- ZIP：`_localization-work/ime-validation/candidate-fix19-package/df-local-zh-complete-0.5.19-windows.zip`
- Live 結果：`_localization-work/ime-validation/keybindings-fix19-live.json`
- 部署紀錄：`_localization-work/ime-validation/backup-candidate-fix19-before-deploy-20261002/deployment.json`
