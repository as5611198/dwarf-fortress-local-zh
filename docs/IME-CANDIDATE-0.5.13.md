# 剪貼簿 UTF-8 修正：0.5.13

日期：2026-10-02。

## 根因

Ctrl+V 的文字已經是有效 UTF-8，但 DFHack 的 `dfhack_addstr_flag` Lua 邊界固定呼叫 CP437 解碼器。`郝` 的 UTF-8 位元組 `E9 83 9D` 因而被逐位元組解成 `Θâ¥`。

## 修正

`crates/lua53-sys/src/lib.rs` 新增共用 `decode_cp437_or_utf8`：整段資料驗證為含中日韓／注音 Unicode 的 UTF-8 時原樣保留；其餘維持既有 CP437 解碼。`check_cp437_string` 使用同一邊界，避免只修搜尋欄而影響其他 DFHack 文字。

## 驗證

- `cargo test -p lua53-sys --lib -- --test-threads=1`：2 通過。
- `cargo test -p df_local_zh_core --lib -- --test-threads=1`（含 DFHack/Lua/SDL runtime PATH）：56 通過、0 失敗、5 忽略。
- Windows static CRT release build：成功。
- 0.5.13 套件：827 個 payload，manifest SHA-256 全部符合。
- DLL SHA-256：`51C2D4E8C62469923664D672F301F27B63C5ED5EC8666F9C1B8E1F54E3DD8675`。
- ZIP SHA-256：`68D0A2EF78DD722960E88BD57495942C97BED0C508CBFCD4F4FCD97CA5B4DF59`。
- 部署後保護檔案：5243/5243 未變；遊戲停止後才替換 DLL。
- 實際 DFHack 遊戲程序已載入上述 DLL，TSF/SDL 焦點正常；未讀取或輸出使用者剪貼簿內容。
