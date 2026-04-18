# BookGet GUI（圖形界面版）

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-informational)
![arch: arm64](https://img.shields.io/badge/arch-arm64-lightgrey)

BookGet 的 macOS 圖形界面封裝，基於 SwiftUI，雙欄單窗口佈局。內置任務隊列、多網址批量、實時日誌、登錄/驗證碼彈窗，並在原版 [bookget](https://github.com/deweizhu/bookget) 基礎上**擴展了更多圖書館的支持**。

> 本項目只提供 GUI 前端、登錄助手、命令行包裝器與構建腳本。核心下載引擎 `bookget-core` 與 IIIF 拼圖工具 `dezoomify-rs` 是獨立的開源項目，構建時需要從其官方 Release 下載二進制放入 `Resources/bin/`。

---

## 功能亮點

- **雙欄單窗口**：粘貼網址 → 選擇目錄 → 開始下載，全流程不再反復彈窗。
- **多網址批量**：一次粘貼多行網址，按順序執行；中途異常自動重試 1 次再跳過。
- **任務隊列與統計**：等待 / 下載中 / 重試中 / 已暫停 / 已終止 / 成功 / 失敗，累積可回看。
- **實時日誌 + 導出**：UI 只保留最近片段，完整日誌落盤到臨時目錄，可一鍵導出到保存目錄。
- **登錄/驗證碼彈窗**：內置 WebKit 臨時瀏覽器，完成登錄後自動把登錄態交給下載引擎，並能跟隨驗證後跳轉的新網址繼續下載。
- **國圖（臺北）rbook 專用模式**：對 `rbook.ncl.edu.tw` 的 `SearchDetail` 類入口自動改用 WebView 抓圖下載。
- **NPM 臺北 IIIF 模式**：`digitalarchive.npm.gov.tw` Collection/Detail 自動轉 IIIF manifest；同時支持 `qingarchives.npm.edu.tw`。
- **歷史記錄與一鍵還原**：最近網址 / 最近目錄 下拉記憶，`恢復初始設置` 一鍵清空回到出廠。
- **支持網站清單**：頂部 `支持網站信息` 按鈕打開可搜索彈窗。

詳細用法見 [docs/BookGetGUIHelp.md](docs/BookGetGUIHelp.md) 與 [docs/使用说明-GUI增强版.md](docs/使用说明-GUI增强版.md)。

---

## 系統要求

- macOS 14.0 或更高
- Apple Silicon（arm64）
- Xcode Command Line Tools（提供 `swiftc` 與 `codesign`）

---

## 構建

1. **克隆倉庫**

   ```zsh
   git clone https://github.com/<your-account>/bookget-gui.git
   cd bookget-gui
   ```

2. **準備外部二進制**（不在本倉庫，需自行下載到 `app-template/Contents/Resources/bin/`）

   | 文件 | 來源 | 說明 |
   |---|---|---|
   | `bookget-core` | [deweizhu/bookget](https://github.com/deweizhu/bookget) Release（arm64 macOS） | 下載引擎 |
   | `dezoomify-rs` | [lovasoa/dezoomify-rs](https://github.com/lovasoa/dezoomify-rs) Release（arm64 macOS） | IIIF 分塊拼圖 |

   下載後記得 `chmod +x`，並根據需要用 `xattr -dr com.apple.quarantine <binary>` 去除下載隔離屬性。

3. **複製 wrapper 腳本**

   ```zsh
   cp src/bookget-wrapper/bookget app-template/Contents/Resources/bin/bookget
   chmod +x app-template/Contents/Resources/bin/bookget
   ```

4. **把 `app-template/` 改名成 `BookGet GUI.app` 放到倉庫根目錄**（構建腳本會在根目錄找 `BookGet GUI*.app`）

   ```zsh
   cp -R app-template "BookGet GUI（v1.6-25.0417）.app"
   ```

5. **編譯 GUI 與登錄助手**

   ```zsh
   ./scripts/rebuild_app.sh
   ```

   腳本會：
   - `swiftc` 編譯 `src/BookGetGUILauncher/bookget_gui_app.swift` → `Contents/MacOS/BookGetGUILauncher`
   - `swiftc` 編譯 `src/bookget-web-login/main.swift` → `Contents/Resources/bin/bookget-web-login`
   - `codesign --force --deep --sign -` 做 ad-hoc 簽名
   - 自動備份當前二進制為 `*.bak.YYYYmmdd_HHMMSS`

---

## 目錄結構

```
bookget-gui/
├── LICENSE                                 # AGPL-3.0
├── README.md
├── .gitignore
├── src/
│   ├── BookGetGUILauncher/
│   │   └── bookget_gui_app.swift           # 主程序（SwiftUI，單文件）
│   ├── bookget-web-login/
│   │   └── main.swift                      # 登錄/驗證碼 WebKit 助手
│   └── bookget-wrapper/
│       └── bookget                         # zsh 包裝器，供 GUI 調用 bookget-core
├── docs/
│   ├── BookGetGUIHelp.md                   # 內置幫助（會被拷貝進 .app/Resources）
│   └── 使用说明-GUI增强版.md
├── scripts/
│   └── rebuild_app.sh                      # swiftc + codesign 一鍵構建
└── app-template/                           # .app 骨架（Info.plist/icns/config.ini）
    └── Contents/...
```

---

## 致謝 / 上游依賴

- [deweizhu/bookget](https://github.com/deweizhu/bookget)（Go）—— 核心下載引擎；支持站點清單來源。
- [lovasoa/dezoomify-rs](https://github.com/lovasoa/dezoomify-rs)（Rust，GPL-3.0）—— IIIF 分塊拼圖。

本項目作為獨立 GUI 前端，通過子進程調用上述工具；不包含、不修改它們的源代碼。

---

## 許可證

本項目以 **AGPL-3.0** 發布（見 [LICENSE](LICENSE)），與上游 `bookget` 保持兼容。

- GUI 前端本身的所有源代碼、腳本、文檔按 AGPL-3.0 提供。
- 通過 Release 附帶分發的 `bookget-core` / `dezoomify-rs` 二進制遵循其各自的上游許可證。

---

## 隱私聲明

- 登錄/驗證碼窗口使用臨時（非持久化）瀏覽器會話，任務結束後清理。
- 登錄態僅本機使用，絕不上傳任何服務器。
- 倉庫已在 `.gitignore` 中屏蔽 `cookie.txt` / `localStorage.txt` / `urls.txt` 等可能含個人數據的文件——請在提交前再次確認。

---

## 反饋

遇到問題請優先從 GUI 的「導出任務日誌」按鈕導出日誌，連同失敗網址與是否勾選了「登錄彈窗」一併貼到 Issue。
