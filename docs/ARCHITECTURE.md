# 架構與開發約定

給所有參與開發的人（包含 AI agent）。設計內容以 `docs/GDD.md` 為準，這份文件只講程式怎麼組織。

## 執行與驗證

```bash
# 測試（headless）
godot --headless --path . -s tests/run_tests.gd            # 全部
godot --headless --path . -s tests/run_tests.gd -- player  # 只跑檔名含 player 的

# 檢查有沒有腳本錯誤（新增或改過 .gd／.tscn 後必跑）
godot --headless --path . --quit 2>&1 | grep -A2 "SCRIPT ERROR"

# 新增或改過 PNG／WAV 後，重新匯入
godot --headless --path . --import

# 截圖：開視窗執行，在遊戲時間第 1、3 秒截圖，第 3.2 秒結束。截圖是 384×216 原始解析度
godot --path . -- --skip-title --start=1800 --god --shot=1,3 --shotdir=/tmp/shots --quit=3.2
```

開發用參數的完整列表在 `scripts/autoload/debug.gd` 開頭。截圖可以直接用圖片檢視工具讀取來確認畫面。

**GDScript 注意：** 本專案的 Godot 4.7 會把「從 Variant 推斷型別」當成錯誤。從 Array、Dictionary 或沒有型別的函式取值時要明確寫型別，例如 `var t: float = arr.pop_front()`。

## 座標系統

- 基準解析度 384×216。攝影機不動，**畫面座標 = global_position**。
- HUD 佔畫面最上方 12 px，玩家可活動範圍是 `Game.PLAYFIELD`（y 12–216）。
- 關卡捲動由 `Stage` 把 `stage.world` 往左移（30 px/s）。固定在地形上的東西（壁砲、增生壁、觸手）是 `stage.world` 的子節點，用世界座標擺放，會跟著捲動；它們的 `global_position` 仍然是畫面座標。
- 自由飛行的東西（雜兵、子彈、道具、玩家）放在 GameWorld 的容器裡，直接用畫面座標。
- 所有遊戲邏輯寫在 `_physics_process`（固定 60 Hz）。

## 節點結構

```
Main (scripts/main.gd)                 畫面流程：標題 → 遊戲 → 結果 → 標題
└── GameWorld (scripts/game/game_world.gd，Game.world 指向它)
    ├── Stage          背景、world（Terrain 與固定在地形上的敵人）、生成事件
    ├── Pickups        道具、散落的僚機
    ├── Enemies        自由飛行的敵人、Boss
    ├── PlayerBullets
    ├── Players
    ├── EnemyBullets
    ├── Effects        爆炸
    ├── UI (CanvasLayer)  HUD、暫停畫面
    └── PauseHandler
```

## 全域物件（autoload）

| 名稱 | 檔案 | 用途 |
|---|---|---|
| `Game` | `scripts/autoload/game.gd` | 分數、殘機、最高分、輸入動作、`Game.world`、`Game.difficulty` |
| `Sfx` | `scripts/autoload/sfx.gd` | `Sfx.play(&"shoot")`、`Sfx.play(&"pickup")` |
| `Debug` | `scripts/autoload/debug.gd` | 開發用參數：`Debug.god`、`Debug.powered`、`Debug.weapon`、`Debug.autopilot` |

## GameWorld 提供的函式

| 函式 | 用途 |
|---|---|
| `terrain() -> Terrain` | 地形查詢 |
| `spawn_pickup(type, pos)` | 生成道具 |
| `spawn_enemy_bullet(pos, velocity)` | 生成敵彈，velocity 要先乘上 `Game.difficulty` |
| `aimed_velocity(from, target, speed := 100.0)` | 瞄準彈的速度向量（已乘上倍率） |
| `spawn_explosion(pos, big := false)` | 爆炸特效 |
| `get_target_player(from) -> Node2D` | 瞄準目標。敵人不可直接引用唯一的玩家節點 |

## 地形（`scripts/stage/terrain.gd`）

地形碰撞**不走物理引擎**，一律用格子查詢，參數是畫面座標：

- `is_solid_at(pos) -> bool`、`is_solid_rect(rect) -> bool`：玩家、飛彈用來判斷碰撞
- `hit(pos, damage) -> bool`：子彈每幀呼叫；回傳 true 表示撞到地形，子彈應消失。可破壞的地形在這裡扣血
- `passage_at(x) -> Vector2(上緣 y, 下緣 y)`：該欄的通道範圍，用來把壁砲、觸手貼齊地形
- `add_provider(node)`：會變化的地形（增生壁）註冊進來，需實作 `is_solid_at(pos)` 與 `hit(pos, damage)`

## 碰撞層

| 層 | 名稱 | 誰在這層 | mask（偵測誰） |
|---|---|---|---|
| 1 | terrain | 保留不用（地形用格子查詢） | |
| 2 | player | 玩家判定框 | 4、5、6、8 |
| 3 | player_bullet | 玩家子彈 | 4 |
| 4 | enemy | 可被打的敵人、觸手根部、Boss 核心 | – |
| 5 | enemy_bullet | 敵彈 | – |
| 6 | pickup | 道具、散落的僚機 | – |
| 7 | shield | 玩家護盾 | 4、5 |
| 8 | hazard | 碰到就死、打不壞的東西：觸手本體、Boss 外殼 | – |

偵測一律由玩家方（玩家、玩家子彈、護盾）的 Area2D 發起，用 `area_entered`。

## 物件介面約定

**敵人（含 Boss 的可受傷部位）**
- 是 `enemy` 層的 `Area2D`，本身實作 `take_damage(amount: int, player_id: int) -> void`。玩家子彈直接對碰到的 Area2D 呼叫它。
- 生成事件的參數透過 `setup(params: Dictionary)` 在加入場景樹前傳入。通用參數：`red: bool`（紅色變體）、`drop: StringName`（被擊破時掉落的道具，空字串表示不掉）。
- 擊破時：`Game.add_score(player_id, 分數)`、`Game.world.spawn_explosion(...)`、有 drop 則 `Game.world.spawn_pickup(drop, global_position)`。
- 受擊白閃用 `assets/shaders/flash.gdshader`。
- 離開畫面左側 32 px 後 `queue_free()`。

**敵彈**（`scenes/enemies/enemy_bullet.tscn`）：`enemy_bullet` 層的 `Area2D`，有 `var velocity: Vector2`。碰到地形或離開畫面就消失。

**玩家**（`scenes/player/player.tscn`，`class_name Player`）
- `var player_id: int`、`signal out_of_lives`、`func is_alive() -> bool`
- `func get_powerup_state() -> Dictionary`，HUD 讀這個：
  `{speed: int (0–5), missile: bool, weapon: StringName (&"basic"/&"ring"/&"beam"), drones: int (0–4), shield: int (0–3)}`
- `signal powerup_changed`：強化狀態有變時發出
- 讀取輸入時動作名稱加上 `"p%d_" % (player_id + 1)` 前綴

**道具**（`scenes/pickups/pickup.tscn`）：`pickup` 層的 `Area2D`，有 `var type: StringName`，值為 `&"speed"`、`&"missile"`、`&"ring"`、`&"beam"`、`&"drone"`、`&"shield"`。

**Boss**（`scenes/boss/boss.tscn`）：根節點有 `var hp: int` 與 `signal finished(defeated: bool)`。GameWorld 在捲動結束時把它加進 `Enemies`。

**UI 場景**：見 `scripts/main.gd` 與 `scripts/game/game_world.gd` 開頭的說明。`title.tscn` 發出 `start_requested`；`result.tscn` 有 `setup(result, score, bonus)`，看完發出 `closed`；`hud.tscn`、`pause.tscn` 由 GameWorld 加進 UI 層。

## 生成事件

關卡資料（`scripts/stage/stage1_data.gd`）的 `spawns` 是依 x 排序的字典陣列：`{x, y, type, ...參數}`。`type` 對應到 `scripts/stage/spawn_registry.gd` 的 `ENTRIES`，其中 `attached` 決定敵人是固定在地形上（世界座標）還是自由飛行（畫面座標）。

## 素材清單

精靈圖放在 `assets/sprites/`。所有圖都是橫排幀（hframes），需要紅色變體的敵人在第 2 列（vframes = 2）。
目前的檔案是 `tools/make_placeholders.py` 產生的色塊，正式美術以**相同檔名、相同尺寸**覆蓋。

| 檔案 | 每幀尺寸 | 幀數（橫×縱） | 內容 |
|---|---|---|---|
| player.png | 24×12 | 3×1 | 平飛、上傾、下傾 |
| drone.png | 10×8 | 2×1 | 僚機動畫 |
| shield.png | 8×20 | 1×1 | 機體前方的護盾 |
| explosion.png | 16×16 | 5×1 | 爆炸 |
| bullet.png | 8×3 | 1×1 | 基本彈 |
| missile.png | 6×4 | 2×1 | 飛彈 |
| ring.png | 6×40 | 3×1 | 環波，小（高 8）、中（高 24）、大（高 40），置中繪製 |
| beam.png | 8×4 | 1×1 | 光束，可水平重複拼接 |
| pickup.png | 12×12 | 2×6 | 每列一種道具：speed、missile、ring、beam、drone、shield；2 幀閃爍 |
| enemy_worm.png | 12×12 | 2×2 | 游蟲；第 2 列紅色變體 |
| enemy_spore.png | 12×12 | 2×2 | 孢子 |
| enemy_turret.png | 16×16 | 2×2 | 壁砲，朝上（裝在地面）；裝在天花板時垂直翻轉。第 1 幀待機、第 2 幀開火 |
| enemy_charger.png | 16×12 | 2×2 | 衝鋒體，朝左 |
| enemy_bullet.png | 4×4 | 2×1 | 敵彈，兩幀交替閃爍 |
| tiles.png | 8×8 | 8×1 | 圖塊，順序同 `Terrain.Tile`：岩石填充、岩石天花板邊、岩石地面邊、肉壁填充、肉壁天花板邊、肉壁地面邊、增生壁、增生壁芽體 |
| tentacle.png | 8×8 | 2×1 | 觸手的節、尖端 |
| tentacle_root.png | 12×12 | 1×1 | 觸手根部節點 |
| boss_body.png | 96×120 | 1×1 | Boss 本體 |
| boss_core.png | 16×16 | 2×1 | Boss 核心，脈動 |
| boss_valve.png | 24×24 | 3×1 | 三片瓣膜：上、前、下 |
| bg_rock.png | 384×216 | 1×1 | 岩石區背景，可水平循環 |
| bg_flesh.png | 384×216 | 1×1 | 肉壁區背景，可水平循環 |
| hud_icons.png | 8×8 | 7×1 | speed、missile、ring、beam、drone、shield、殘機 |
| logo.png | 192×40 | 1×1 | 標題 Logo |

字型：`assets/fonts/pixel.fnt`（BMFont 文字格式）與 `pixel.png`。音效：`assets/audio/shoot.wav`、`assets/audio/pickup.wav`。

## 檔案歸屬

| 目錄 | 內容 |
|---|---|
| `scripts/autoload/`、`scripts/game/`、`scripts/stage/`（除了 stage1_data.gd） | 核心框架 |
| `scenes/player/`、`scripts/player/`、`scenes/pickups/`、`scripts/pickups/`、`scenes/weapons/`、`scripts/weapons/` | 玩家、武器、道具 |
| `scenes/enemies/`、`scripts/enemies/`、`scenes/terrain/`、`scripts/terrain/` | 敵人、敵彈、地形機關 |
| `scripts/stage/stage1_data.gd` | 第 1 關內容 |
| `scenes/boss/`、`scripts/boss/` | Boss |
| `scenes/ui/`、`scripts/ui/` | UI |
| `assets/`、`tools/` | 素材與產生素材的工具 |
| `tests/` | 測試，每個模組自己的 `test_<模組>.gd` |
