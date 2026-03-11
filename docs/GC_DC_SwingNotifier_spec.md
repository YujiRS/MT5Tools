# GC/DC Swing Notifier インジケーター 仕様書

## 概要

MT5用カスタムインジケーター。EMA 13 と EMA 21 のクロスを M5/M15/H1/H4 の4時間足で並行監視し、以下の3条件をすべて満たした場合のみ通知する。

1. 確定足ベースのクロス判定（リペイント防止）
2. 両EMAの方向一致フィルター
3. 構造的 Swing 高値/安値の近辺フィルター

ファイル: `src/Indicators/GC_DC_SwingNotifier.mq5`

## 入力パラメータ

### MA 設定

| パラメータ | 型 | デフォルト | 説明 |
|---|---|---|---|
| EMA_Fast | int | 13 | Fast EMA 期間 |
| EMA_Slow | int | 21 | Slow EMA 期間 |
| UseEMA | bool | true | true: EMA / false: SMA |

### Swing 設定

| パラメータ | 型 | デフォルト | 説明 |
|---|---|---|---|
| SwingStrength | int | 5 | Swing 判定の左右本数（推奨: 3〜7） |
| SwingWindow_M5 | int | 5 | M5: Swing からクロスまでの許容本数（約25分） |
| SwingWindow_M15 | int | 6 | M15: Swing からクロスまでの許容本数（約90分） |
| SwingWindow_H1 | int | 8 | H1: Swing からクロスまでの許容本数（約8時間） |
| SwingWindow_H4 | int | 10 | H4: Swing からクロスまでの許容本数（約40時間） |

### 監視時間足 ON/OFF

| パラメータ | 型 | デフォルト | 説明 |
|---|---|---|---|
| Use_M5 | bool | true | M5 の監視 |
| Use_M15 | bool | true | M15 の監視 |
| Use_H1 | bool | true | H1 の監視 |
| Use_H4 | bool | true | H4 の監視 |

### 通知設定

| パラメータ | 型 | デフォルト | 説明 |
|---|---|---|---|
| EnablePopupAlert | bool | true | MT5 画面アラート |
| EnablePush | bool | true | Push 通知（MT5 モバイル） |
| EnableEmail | bool | false | メール通知 |
| EnableSound | bool | false | サウンド通知 |
| SoundFile | string | "alert.wav" | サウンドファイル名 |

### チャート表示

| パラメータ | 型 | デフォルト | 説明 |
|---|---|---|---|
| ShowArrows | bool | true | シグナル矢印表示 |

## 動作仕様

### OnInit（起動時）

1. 入力値バリデーション
   - `EMA_Fast >= EMA_Slow` → `INIT_PARAMETERS_INCORRECT`
   - `SwingStrength < 1` → `INIT_PARAMETERS_INCORRECT`
2. 重複通知防止用配列を初期化
3. チャート描画用バッファ設定（EMA Fast / EMA Slow の2本）
4. チャート時間足用の MA ハンドルを作成
5. 4TF 監視用の MA ハンドルを `iMA()` で作成しキャッシュ
   - 無効化されたTFのハンドルは `INVALID_HANDLE` のまま

### OnCalculate（ティック処理）

1. チャート時間足の EMA をバッファに描画
   - `CopyBuffer` 失敗時は `prev_calculated` を返し、全再計算を防止
2. 各有効時間足について `CheckTimeframe()` を実行

### CheckTimeframe（各TFのクロス判定）

以下の処理を各時間足ごとに独立して実行:

1. **バッファ確保**: `SwingStrength * 2 + max(swWindow, SwingWindow_H4) + 5` 本
2. **MA値・価格データ取得**: `CopyBuffer` / `CopyHigh` / `CopyLow` / `CopyClose` / `CopyTime`
   - いずれかが必要本数に満たない場合は安全に `return`
3. **クロス判定**（確定足ベース）
4. **方向性フィルター**
5. **Swing 近辺フィルター**
6. **重複通知チェック**
7. **通知実行**
8. **矢印表示**（チャート時間足と一致する場合のみ）

### OnDeinit（終了時）

1. チャート用 MA ハンドル解放
2. 4TF 用 MA ハンドル解放
3. 矢印オブジェクト削除

## クロス判定ロジック

確定足ベースで判定（リペイント防止）。`shift[0]`（未確定足）は判定対象外。

```
ゴールデンクロス（GC）:
  shift[2] で EMA_Fast < EMA_Slow
  shift[1] で EMA_Fast > EMA_Slow

デッドクロス（DC）:
  shift[2] で EMA_Fast > EMA_Slow
  shift[1] で EMA_Fast < EMA_Slow
```

- `shift[1]` = 最新確定足、`shift[2]` = その1本前の確定足

## 方向性フィルター

クロス発生時点で、両 EMA のスロープ（`[1] - [2]`）が同方向であること。

```
GC 条件: slopeFast > 0 かつ slopeSlow > 0
DC 条件: slopeFast < 0 かつ slopeSlow < 0
```

- ゼロちょうどは不成立
- 将来的に最小傾き閾値（input）を追加可能な設計

## Swing 高安値フィルター

### Swing の定義（Fractal 方式）

```
Swing High: 中央足の High が、左右 SwingStrength 本すべての High より高い（等値は不成立）
Swing Low:  中央足の Low が、左右 SwingStrength 本すべての Low より低い（等値は不成立）
```

### フィルター条件

クロス発生バーから遡って SwingWindow 本以内に対応する Swing が存在すること。

```
GC 通知条件: shift[SwingStrength] 〜 shift[SwingWindow] 内に Swing Low がある
DC 通知条件: shift[SwingStrength] 〜 shift[SwingWindow] 内に Swing High がある
```

- 検索開始は `shift[SwingStrength]`（それより手前では左右比較が成立しないため）

## 重複通知防止

`lastAlertTime[TF_COUNT][2]` 配列（`[tfIdx][0=DC, 1=GC]`）でバー時刻を管理。同一バー時刻での再通知はスキップ。

## 通知メッセージフォーマット

```
[{GC|DC}] {YYYY.MM.DD HH:MM} | {Symbol} | {Rate} | {TF}
```

- `Rate`: クロス判定確定足（`shift[1]`）の Close
- `TF`: `M5` / `M15` / `H1` / `H4`

### 通知手段

| 手段 | MQL5 関数 | テスター環境 |
|---|---|---|
| Alert | `Alert(message)` | 有効 |
| Push | `SendNotification(message)` | 無効化 |
| メール | `SendMail("GC/DC Alert", message)` | 無効化 |
| サウンド | `PlaySound(SoundFile)` | 有効 |

## チャート表示

- チャートウィンドウに EMA Fast（青）/ EMA Slow（赤）の2本を描画
- `ShowArrows = true` かつチャート時間足が監視対象TFと一致するとき:
  - GC: 上向き矢印（緑, `OBJ_ARROW_UP`）を Swing Low 価格に配置
  - DC: 下向き矢印（赤, `OBJ_ARROW_DOWN`）を Swing High 価格に配置

## 制約・前提

- チャートの時間足に関わらず M5/M15/H1/H4 を `iMA` で並行計算する
- `iMA()` ハンドルは `OnInit()` でキャッシュし `OnCalculate()` で再生成しない
- 矢印はチャート時間足と監視TFが一致する場合のみ表示
- `SendNotification` / `SendMail` は MT5 側の設定（MetaQuotes ID / SMTP）が必要
