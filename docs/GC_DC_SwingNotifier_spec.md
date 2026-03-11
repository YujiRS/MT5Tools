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

### ログ設定

| パラメータ | 型 | デフォルト | 説明 |
|---|---|---|---|
| EnableTsvLog | bool | true | TSVログ出力 ON/OFF |

## 動作仕様

### OnInit（起動時）

1. 入力値バリデーション
   - `EMA_Fast >= EMA_Slow` → `INIT_PARAMETERS_INCORRECT`
   - `SwingStrength < 1` → `INIT_PARAMETERS_INCORRECT`
2. 同方向クロス抑制用配列を初期化
3. チャート描画用バッファ設定（EMA Fast / EMA Slow の2本）
4. チャート時間足用の MA ハンドルを作成
5. 4TF 監視用の MA ハンドルを `iMA()` で作成しキャッシュ
   - 無効化されたTFのハンドルは `INVALID_HANDLE` のまま
6. 4TF 監視用の ATR ハンドルを `iATR()` で作成しキャッシュ（期間: 14）
7. `EnableTsvLog = true` の場合、TSVログファイルを開く
   - ファイル: `MQL5/Files/GC_DC_SwingNotifier_<Symbol>.tsv`
   - 既存ファイルは追記モード、新規は作成してヘッダ行を出力

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
5. **Swing 近辺フィルター**（Swing のバーインデックスと価格を記録）
6. **同方向クロス抑制チェック**
7. **通知実行**
8. **TSVログ出力**（`EnableTsvLog = true` の場合）
9. **矢印表示**（チャート時間足と一致する場合のみ）

### OnDeinit（終了時）

1. TSVログファイルを閉じる
2. チャート用 MA ハンドル解放
3. 4TF 用 MA ハンドルおよび ATR ハンドル解放
4. 矢印オブジェクト削除

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

## 同方向クロス抑制

`lastCrossDir[TF_COUNT]` 配列で各TFの最後に通知したクロス方向を管理（`0`=なし, `1`=GC, `-1`=DC）。

- 同じTFで同方向のクロスが連続した場合、逆方向のクロスが発生するまで通知を抑制する
- 異なるTF間は独立して管理（M5でDC→M15でDCは両方通知される）
- 全フィルター通過後のクロスのみ方向を記録する（フィルター不通過のクロスでは方向はリセットされない）

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

## TSVログ出力

### 概要

クロス判定が通知される際、判定に使用した元データを含むTSVファイルを出力する。EA化の判断材料や仕様検討に利用する。

- ファイル: `MQL5/Files/GC_DC_SwingNotifier_<Symbol>.tsv`
- 出力タイミング: 通知と同じタイミング（通知が抑制された場合はログも出力しない）
- 追記モード: インジケーター再起動時は既存ファイルに追記

### TSVカラム

| # | カラム名 | 説明 |
|---|---|---|
| 1 | LogTime | ログ出力時刻（サーバー時刻, `YYYY.MM.DD HH:MM:SS`） |
| 2 | Symbol | 通貨ペア |
| 3 | Signal | `GC` or `DC` |
| 4 | Timeframe | 検出TF（`M5` / `M15` / `H1` / `H4`） |
| 5 | BarTime | クロス確定足(shift[1])の時刻 |
| 6 | Close | 確定足の Close |
| 7 | High | 確定足の High |
| 8 | Low | 確定足の Low |
| 9 | FastMA1 | fastMA[1]（確定足） |
| 10 | FastMA2 | fastMA[2]（1本前） |
| 11 | SlowMA1 | slowMA[1]（確定足） |
| 12 | SlowMA2 | slowMA[2]（1本前） |
| 13 | MaDiff | fastMA[1] - slowMA[1]（クロス直後の乖離幅） |
| 14 | SlopeFast | fastMA[1] - fastMA[2] |
| 15 | SlopeSlow | slowMA[1] - slowMA[2] |
| 16 | SlopeFastAvg5 | Fast MA 直近5本の平均傾き: (fastMA[1] - fastMA[6]) / 5 |
| 17 | SlopeSlowAvg5 | Slow MA 直近5本の平均傾き: (slowMA[1] - slowMA[6]) / 5 |
| 18 | SwingBarIndex | Swing 検出位置（shift値） |
| 19 | SwingPrice | Swing High/Low の価格 |
| 20 | SwingToCrossBars | Swing からクロスまでのバー数（SwingBarIndex - 1） |
| 21 | SwingToCrossDistance | Swing 価格から Close[1] までの距離（絶対値） |
| 22 | ATR | ATR(14) の値（シグナルTFの shift[1]） |
| 23 | Spread | シグナル時のスプレッド（point） |
| 24-28 | M5_FastMA, M5_SlowMA, M5_MaDiff, M5_SlopeFast, M5_SlopeSlow | M5 の MA 状態スナップショット |
| 29-33 | M15_FastMA, M15_SlowMA, M15_MaDiff, M15_SlopeFast, M15_SlopeSlow | M15 の MA 状態スナップショット |
| 34-38 | H1_FastMA, H1_SlowMA, H1_MaDiff, H1_SlopeFast, H1_SlopeSlow | H1 の MA 状態スナップショット |
| 39-43 | H4_FastMA, H4_SlowMA, H4_MaDiff, H4_SlopeFast, H4_SlopeSlow | H4 の MA 状態スナップショット |

- 他TFの MA 状態は最新バー（shift[0]）の値を使用
- 無効化されたTFや取得失敗時は空文字を出力
- 価格・MA値の小数桁数は `_Digits`（シンボル依存）

## チャート表示

- チャートウィンドウに EMA Fast（青）/ EMA Slow（赤）の2本を描画
- `ShowArrows = true` かつチャート時間足が監視対象TFと一致するとき:
  - GC: 上向き矢印（緑, `OBJ_ARROW_UP`）を Swing Low 価格に配置
  - DC: 下向き矢印（赤, `OBJ_ARROW_DOWN`）を Swing High 価格に配置

## 制約・前提

- チャートの時間足に関わらず M5/M15/H1/H4 を `iMA` で並行計算する
- `iMA()` / `iATR()` ハンドルは `OnInit()` でキャッシュし `OnCalculate()` で再生成しない
- 矢印はチャート時間足と監視TFが一致する場合のみ表示
- `SendNotification` / `SendMail` は MT5 側の設定（MetaQuotes ID / SMTP）が必要
