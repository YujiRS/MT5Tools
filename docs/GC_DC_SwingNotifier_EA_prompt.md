# GC/DC Swing EA 作成プロンプト

> **使い方**: このプロンプトを EA リポジトリで Claude に投げてください。
> インジケーター試運転の結果や、改善案の実装状況に応じて「採用する改善案」セクションを編集してから使ってください。

---

## 依頼内容

以下の仕様に従い、MetaTrader 5 用の **MQL5 EA** を作成してください。
ファイル名は `GC_DC_SwingEA.mq5` とします。

---

## 背景

インジケーター版 `GC_DC_SwingNotifier.mq5`（MT5Tools リポジトリ）の試運転を経て、EA 化するものです。
インジケーター版のシグナルロジック（クロス判定・方向性フィルター・Swing 近辺フィルター）をベースに、エントリー/イグジット/ポジション管理を追加します。

---

## シグナルロジック（インジケーター版から継承）

### MA 設定

| パラメータ | デフォルト |
|---|---|
| MA 種別 | EMA（input で SMA 切替可） |
| Fast 期間 | 13 |
| Slow 期間 | 21 |
| 適用価格 | Close |

### クロス判定（確定足ベース）

```
ゴールデンクロス（GC）:
  shift[2] で Fast < Slow
  shift[1] で Fast > Slow → ロング方向シグナル

デッドクロス（DC）:
  shift[2] で Fast > Slow
  shift[1] で Fast < Slow → ショート方向シグナル
```

- `shift[1]` = 最新確定足、`shift[2]` = その1本前
- `shift[0]`（未確定足）は判定対象外

### 方向性フィルター

クロス発生時点で両 EMA のスロープが同方向であること。

```
GC: Fast[1]-Fast[2] > 0 かつ Slow[1]-Slow[2] > 0
DC: Fast[1]-Fast[2] < 0 かつ Slow[1]-Slow[2] < 0
```

- ゼロちょうどは不成立

### Swing 高安値フィルター（Fractal 方式）

```
Swing High: 中央足の High が左右 SwingStrength 本すべての High より厳密に高い
Swing Low:  中央足の Low が左右 SwingStrength 本すべての Low より厳密に低い
```

```
GC: クロス発生バーから SwingWindow 本以内に Swing Low が存在
DC: クロス発生バーから SwingWindow 本以内に Swing High が存在
```

- SwingStrength デフォルト: 5
- SwingWindow は時間足別に個別設定（後述）

### 監視時間足

```
PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4
```

各時間足ごとに独立して判定。各 TF の ON/OFF は input で切替可能。

---

## EA 固有の仕様

### エントリー

- GC シグナル成立 → **買いエントリー**（成行）
- DC シグナル成立 → **売りエントリー**（成行）
- 同一シンボルで既に同方向のポジションを保有している場合はエントリーしない
- 逆方向ポジション保有時の動作は input で選択:
  - `REVERSE_CLOSE_AND_OPEN`: 既存ポジション決済 → 新規エントリー
  - `REVERSE_IGNORE`: 逆シグナルを無視

### イグジット

- **TP/SL**: input で pips 指定（0 = 無効）
- **トレーリングストップ**: input で ON/OFF、開始 pips、ステップ pips
- **逆シグナル決済**: 上記 `REVERSE_CLOSE_AND_OPEN` 時のドテン

### ポジション管理

- マジックナンバーで自ポジションを識別
- 1シンボルにつき最大1ポジション（同方向の重複エントリー禁止）
- ロットは固定ロット（input）

### リスク管理

- 最大スプレッドフィルター: 現在スプレッドが指定値を超える場合はエントリーしない
- 取引時間フィルター: 開始時刻・終了時刻を input で指定（0:00〜0:00 = フィルター無効）

---

## Input パラメータ一覧

```mql5
// --- MA 設定 ---
input int    EMA_Fast           = 13;
input int    EMA_Slow           = 21;
input bool   UseEMA             = true;       // true: EMA / false: SMA

// --- Swing 設定 ---
input int    SwingStrength      = 5;
input int    SwingWindow_M5     = 5;
input int    SwingWindow_M15    = 6;
input int    SwingWindow_H1     = 8;
input int    SwingWindow_H4     = 10;

// --- 監視時間足 ---
input bool   Use_M5             = true;
input bool   Use_M15            = true;
input bool   Use_H1             = true;
input bool   Use_H4             = true;

// --- エントリー ---
input double LotSize            = 0.01;       // 固定ロット
input int    MagicNumber        = 20260311;
input ENUM_REVERSE_MODE ReverseMode = REVERSE_CLOSE_AND_OPEN;

// --- TP/SL（pips, 0=無効） ---
input double TakeProfit_Pips    = 0.0;
input double StopLoss_Pips      = 0.0;

// --- トレーリングストップ ---
input bool   UseTrailing        = false;
input double TrailingStart_Pips = 30.0;       // 含み益がこの値を超えたら開始
input double TrailingStep_Pips  = 10.0;       // ステップ幅

// --- フィルター ---
input int    MaxSpreadPoints    = 0;          // 最大スプレッド（0=無制限）
input string TradeStartTime     = "00:00";    // 取引開始時刻
input string TradeEndTime       = "00:00";    // 取引終了時刻（00:00-00:00=無効）

// --- 通知 ---
input bool   EnablePopupAlert   = true;
input bool   EnablePush         = true;
input bool   EnableEmail        = false;

// ===== 改善案（試運転結果に応じて有効化） =====

// --- ATR 価格距離フィルター ---
// input bool   UseATRFilter       = false;
// input int    ATR_Period         = 14;
// input double ATR_Multiplier    = 1.0;      // Swing からの価格距離が ATR×倍率以内

// --- 最小傾き閾値 ---
// input double MinSlopeThreshold = 0.0;      // MA スロープの最小値（0=従来通り符号判定のみ）

// --- 上位足トレンド一致フィルター ---
// input bool   UseHigherTFFilter  = false;   // M5→M15, M15→H1, H1→H4, H4→D1 の EMA 方向一致

// --- SwingStrength 時間足別個別設定 ---
// input int    SwingStrength_M5   = 5;
// input int    SwingStrength_M15  = 5;
// input int    SwingStrength_H1   = 5;
// input int    SwingStrength_H4   = 5;
```

---

## ENUM 定義

```mql5
enum ENUM_REVERSE_MODE
{
   REVERSE_CLOSE_AND_OPEN = 0,  // 決済してドテン
   REVERSE_IGNORE         = 1   // 逆シグナル無視
};
```

---

## 通知メッセージフォーマット

### エントリー時

```
[ENTRY] BUY  2026.03.11 14:05 | USDJPY | 148.320 | M15 | Lot=0.01
[ENTRY] SELL 2026.03.11 09:00 | XAUUSD | 2318.50 | H1  | Lot=0.01
```

### 決済時

```
[EXIT]  BUY  2026.03.11 15:30 | USDJPY | 148.520 | Profit=+20.0pips
```

---

## 実装上の注意点

1. `iMA()` ハンドルは `OnInit()` でキャッシュし `OnTick()` で再生成しないこと
2. `CopyBuffer()` のコピー数は `SwingStrength * 2 + SwingWindow_H4 + 5` 本以上
3. バッファ取得失敗時は安全に `return` すること
4. テスター環境では Push・メール通知を無効化すること
5. 確定足ベース判定のため、新しいバーが形成されたタイミングでのみシグナル判定を実行すること（ティックごとの無駄な判定を避ける）
6. pips → price 変換は `SymbolInfoDouble(_Symbol, SYMBOL_POINT)` と桁数を考慮すること
7. OrderSend 失敗時はリトライせず、エラーログを出力すること
8. `#property strict` を付け、コンパイルが通る完全な MQL5 コードを出力すること
9. 省略なし・全文一括で出力すること

---

## 採用する改善案

> **試運転の結果に応じて、以下のチェックボックスを編集してからプロンプトを投げてください。**
> チェックを入れた改善案のみ EA に組み込みます。
> インジケーター側で先に実装・検証済みの場合はその旨を記載してください。

- [ ] **ATR 価格距離フィルター**: Swing 近辺の判定を「本数」に加え、ATR 倍率ベースの価格距離でも判定可能にする
- [ ] **最小傾き閾値**: `MinSlopeThreshold` を追加し、方向性フィルターの感度を調整可能にする
- [ ] **上位足トレンド一致フィルター**: エントリーTFの上位足で EMA 方向が一致していることを追加条件にする（M5→M15, M15→H1, H1→H4, H4→D1）
- [ ] **SwingStrength の時間足別個別設定**: 時間足ごとに異なる SwingStrength を設定可能にする

### 改善案の詳細仕様

#### ATR 価格距離フィルター

```
追加条件:
  GC: |close[1] - SwingLow価格| <= iATR(ATR_Period)[1] × ATR_Multiplier
  DC: |close[1] - SwingHigh価格| <= iATR(ATR_Period)[1] × ATR_Multiplier

UseATRFilter = false のときは本数ベースのみ（従来動作）
```

#### 最小傾き閾値

```
既存の方向性フィルターを拡張:
  GC: slopeFast > MinSlopeThreshold かつ slopeSlow > MinSlopeThreshold
  DC: slopeFast < -MinSlopeThreshold かつ slopeSlow < -MinSlopeThreshold

MinSlopeThreshold = 0.0 のときは従来通り符号判定のみ
```

#### 上位足トレンド一致フィルター

```
エントリーTFに対応する上位TFの EMA 方向を確認:
  M5  → M15 の EMA Fast が上向き(GC)/下向き(DC)
  M15 → H1  の EMA Fast が上向き(GC)/下向き(DC)
  H1  → H4  の EMA Fast が上向き(GC)/下向き(DC)
  H4  → D1  の EMA Fast が上向き(GC)/下向き(DC)

上位足の方向 = EMA_Fast[1] - EMA_Fast[2] の符号
```

#### SwingStrength 時間足別個別設定

```
SwingStrength を時間足ごとに個別指定:
  SwingStrength_M5, SwingStrength_M15, SwingStrength_H1, SwingStrength_H4

共通の SwingStrength input は廃止し、4つの個別 input に置換
```

---

## 出力物

- `GC_DC_SwingEA.mq5`（単一ファイル、コメント付き、完全版）

---

## コード出力後に説明してほしいこと

1. バックテストの推奨設定（期間、モデル、スプレッド）
2. 最適化すべきパラメータの優先順位
3. 注意すべきリスク（過剰最適化、スプレッド感度など）
