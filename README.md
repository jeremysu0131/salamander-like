# Project Newt

致敬《沙羅曼蛇》的橫向捲軸射擊遊戲，Godot 4.7 製作。MVP：1 個橫向關卡加 1 個 Boss。

## 遊玩

- **編輯器／開發中**：`godot --path .`
- **已匯出版本**：`build/macos/ProjectNewt.zip`（解壓後開啟 `Project Newt.app`）、`build/windows/ProjectNewt.exe`

macOS 版沒有經過 Apple 公證，第一次開啟時需在 Finder 中按右鍵選「打開」。

| 動作 | 鍵盤 | 手把 |
|---|---|---|
| 移動 | 方向鍵或 WASD | 十字鍵或左類比 |
| 射擊 | Z 或 J | A |
| 暫停 | Esc 或 Enter | Start |
| 全螢幕 | F11 | |

手機（瀏覽器）：按住畫面左半邊拖曳移動，按住右半邊射擊，右上角是暫停鈕。請橫向持握。

## 文件

- `docs/GDD.md`：遊戲設計文件
- `docs/ARCHITECTURE.md`：程式架構、介面約定、測試與截圖方法、開發用參數
- `docs/reference-analysis.md`：原作機制分析與致敬界線

## 開發

```bash
godot --headless --path . -s tests/run_tests.gd        # 全部測試
godot --path . -- --skip-title --start=6300 --god      # 直接跳到 Boss 戰（無敵）
godot --headless --path . --export-release "macOS" build/macos/ProjectNewt.zip
```

素材由 `tools/` 下的 Python 腳本產生（只用標準函式庫），改完後執行 `godot --headless --path . --import`。
