# Swing Signal EA 作成プロンプト

> **使い方**: このプロンプトを EA リポジトリで Claude に投げてください。
> 先に仕様書を作成し、仕様書に基づいて EA を実装します。

---

## 依頼内容

以下の仕様に従い、MetaTrader 5 用の **MQL5 EA** を作成してください。

1. まず仕様書（`SwingSignalEA_spec.md`）を作成
2. 仕様書に基づいて EA コードを実装

ファイル名は `SwingSignalEA.mq5` とします。

---

## 背景・設計思想

GC_DC_SwingNotifier（MT5Tools リポジトリ）と RoleReversalEA の設計検討を経て、以下の方針で新 EA を構築する。

- **M5 EMA クロスをトリガーとし、H1 EMA の位置関係を方向フィルタとする**
- **M5 の Swing フィルタは不要**（H1 フィルタが構造的方向性を担保）
- **Exit はハイブリッド方式**: H1 Swing High/Low を TP + ATR トレーリングストップ
- **H1 レジーム（根拠）消滅時は即撤退**

---

## エントリーロジック

### H1 方向フィルタ（レジーム判定）

H1 の EMA の**位置関係のみ**で方向を決定する。クロスの「発生」を待つ必要はない。

```
ロングレジーム: H1 EMA_Fast[1] > H1 EMA_Slow[1]
ショートレジーム: H1 EMA_Fast[1] < H1 EMA_Slow[1]

※ H1 EMA_Fast[1] == H1 EMA_Slow[1] → どちらのレジームでもない（エントリー不可）
※ [1] = H1 の最新確定足
```

- Swing フィルタ: 不要
- スロープチェック: 不要
- これは「今 H1 がどちら向きか」を見るだけの最もシンプルなフィルタ

### M5 トリガー（EMA クロス）

M5 の EMA クロスでエントリーシグナルを生成する。確定足ベース（リペイント防止）。

```
ゴールデンクロス（GC）:
  M5 shift[2] で EMA_Fast < EMA_Slow
  M5 shift[1] で EMA_Fast > EMA_Slow
  → ロングシグナル

デッドクロス（DC）:
  M5 shift[2] で EMA_Fast > EMA_Slow
  M5 shift[1] で EMA_Fast < EMA_Slow
  → ショートシグナル
```

- `shift[1]` = M5 の最新確定足、`shift[2]` = その1本前
- `shift[0]`（未確定足）は判定対象外

### 方向性フィルター（M5 スロープ）

M5 クロス発生時点で、両 EMA のスロープが同方向であること。ダマシクロスの抑制。

```
GC: M5_SlopeFast > 0 かつ M5_SlopeSlow > 0
DC: M5_SlopeFast < 0 かつ M5_SlopeSlow < 0

SlopeFast = EMA_Fast[1] - EMA_Fast[2]
SlopeSlow = EMA_Slow[1] - EMA_Slow[2]
```

- ゼロちょうどは不成立

### エントリー条件（すべて AND）

```
ロングエントリー:
  1. H1 EMA_Fast[1] > H1 EMA_Slow[1]          （H1 ロングレジーム）
  2. M5 で GC 発生（確定足ベース）               （M5 トリガー）
  3. M5 SlopeFast > 0 かつ SlopeSlow > 0        （方向性フィルター）
  4. 取引時間帯内                                （時間フィルタ）
  5. スプレッド ≦ MaxSpreadPoints               （スプレッドフィルタ）
  6. 同方向ポジション未保有                       （重複防止）

ショートエントリー: 上記の逆条件
```

### エントリー執行

- 成行注文（TRADE_ACTION_DEAL）
- SL/TP は注文時に設定
- ロットサイズ: 固定ロット or リスク%ベース（input で選択）
- Filling モードはシンボルの対応モードを自動判定

---

## イグジットロジック

4 つの Exit 条件があり、**いずれか先に成立した条件**でポジションを決済する。

### Exit 1: TP 到達（H1 Swing High/Low）

エントリー時に、次の H1 Swing High/Low を TP として設定する。

```
ロング TP: エントリー価格より上方の最も近い H1 Swing High
ショート TP: エントリー価格より下方の最も近い H1 Swing Low

Swing の定義（Fractal 方式）:
  Swing High: 中央足の High が左右 H1_SwingStrength 本すべての High より厳密に高い
  Swing Low:  中央足の Low が左右 H1_SwingStrength 本すべての Low より厳密に低い
```

- H1 Swing が見つからない場合: フォールバックとして SL × MinRR を TP に使用
- TP までの距離が SL × MinRR 未満の場合: SL × MinRR を TP に使用（最低 R:R 保証）

### Exit 2: ATR トレーリングストップ

利益方向に進んだ分だけ SL を追従させる。

```
トレーリング距離 = ATR(ATR_Period, PERIOD_M5)[1] × TrailATR_Multi

ロングの場合:
  新SL候補 = 現在の最高値 - トレーリング距離
  IF 新SL候補 > 現在のSL THEN SL を更新

ショートの場合:
  新SL候補 = 現在の最安値 + トレーリング距離
  IF 新SL候補 < 現在のSL THEN SL を更新
```

- 「現在の最高値/最安値」はポジション保有中の M5 確定足ベースで追跡
- SL の引き上げ（引き下げ）のみ。逆方向への変更はしない
- 新しい M5 バー確定時にのみ判定（ティックごとではない）
- ATR 値はトレーリング判定時の最新値を毎回取得する（固定しない）

### Exit 3: 初期 SL

エントリー時に設定する固定ストップロス。

```
ロング SL: M5 確認足（shift[1]）の Low - SL_BufferATR × ATR
ショート SL: M5 確認足（shift[1]）の High + SL_BufferATR × ATR

ATR = ATR(ATR_Period, PERIOD_M5)[1]
```

- SL 幅が MaxSL_ATR × ATR を超える場合 → エントリーしない（リスク過大）

### Exit 4: H1 レジーム終了（根拠消滅 → 即撤退）

H1 の EMA 位置関係が逆転した場合、**無条件で即決済**する。

```
ロング保有中:
  H1 EMA_Fast[1] <= H1 EMA_Slow[1] → 成行決済

ショート保有中:
  H1 EMA_Fast[1] >= H1 EMA_Slow[1] → 成行決済
```

- 含み益・含み損に関わらず実行
- SL/TP より優先（H1 確定足のタイミングで判定し、条件成立なら即決済）
- 判定タイミング: 新しい H1 バーが確定した時（M5 の OnTick 内で H1 バー変化を検出）
- これは SL/TP のように注文に設定するものではなく、EA が能動的に決済する

---

## H1 Swing High/Low の検出

TP 設定に使用する H1 Swing の検出ロジック。

```
検出範囲: H1 の直近 H1_SwingMaxAge 本
SwingStrength: H1_SwingStrength（左右の比較本数）

Swing High:
  bars[i] の High が bars[i-1]...bars[i-SwingStrength] および
  bars[i+1]...bars[i+SwingStrength] のすべての High より厳密に高い

Swing Low:
  bars[i] の Low が bars[i-1]...bars[i-SwingStrength] および
  bars[i+1]...bars[i+SwingStrength] のすべての Low より厳密に低い
```

- エントリー時に検出し、TP として設定
- ポジション保有中に新しい Swing が検出されても TP は変更しない（エントリー時固定）

---

## ポジション管理

- マジックナンバーで自ポジションを識別
- 1 シンボルにつき最大 1 ポジション（同方向の重複エントリー禁止）
- 逆方向ポジション保有時の動作は input で選択:
  - `REVERSE_CLOSE_AND_OPEN`: 既存ポジション決済 → 新規エントリー
  - `REVERSE_IGNORE`: 逆シグナルを無視（既存ポジションを維持）

---

## Input パラメータ一覧

```mql5
// === G1: Operation ===
input bool              EnableTrading          = true;           // Enable Trading
input ENUM_SS_LOT_MODE  LotMode                = SS_LOT_FIXED;  // Lot Mode
input double            FixedLot               = 0.01;          // Fixed Lot
input double            RiskPercent            = 1.0;            // Risk % (of equity)
input double            MinMarginLevel         = 1500;           // Min margin level after entry (%, 0=無効)
input int               MagicNumber            = 20260312;       // Magic Number
input ENUM_REVERSE_MODE ReverseMode            = REVERSE_CLOSE_AND_OPEN; // Reverse Mode
input string            InstanceTag            = "";             // Instance Tag (comment)

// === G2: M5 EMA (Trigger) ===
input int               M5_EMA_Fast            = 13;             // M5 EMA Fast Period
input int               M5_EMA_Slow            = 21;             // M5 EMA Slow Period
input bool              UseEMA                 = true;           // true: EMA / false: SMA

// === G3: H1 EMA (Direction Filter) ===
input int               H1_EMA_Fast            = 13;             // H1 EMA Fast Period
input int               H1_EMA_Slow            = 21;             // H1 EMA Slow Period

// === G4: H1 Swing (TP Target) ===
input int               H1_SwingStrength       = 5;              // H1 Swing Lookback (bars each side)
input int               H1_SwingMaxAge         = 200;            // H1 Swing Max Age (bars)

// === G5: Stop Loss ===
input double            SL_BufferATR           = 0.5;            // SL Buffer (ATR fraction)
input double            MaxSL_ATR              = 2.0;            // Max SL Width (ATR multiple, 超過→エントリー不可)
input double            MinRR                  = 2.0;            // Min Reward:Risk (TP が近すぎる場合のフォールバック)

// === G6: ATR Trailing Stop ===
input int               ATR_Period             = 14;             // ATR Period
input double            TrailATR_Multi         = 2.0;            // Trailing Distance (ATR multiple)

// === G7: Time Filter (Server Time) ===
input int               TradeHourStart         = 8;              // Trading Start Hour
input int               TradeHourEnd           = 21;             // Trading End Hour

// === G8: Spread Filter ===
input int               MaxSpreadPoints        = 0;              // Max Spread (points, 0=無制限)

// === G9: Notification ===
input bool              EnableAlert            = true;           // Alert on entry/exit
input bool              EnablePush             = true;           // Push notification
input bool              EnableEmail            = false;          // Email notification

// === G10: Logging ===
input ENUM_SS_LOG_LEVEL LogLevel               = SS_LOG_NORMAL;  // Log Level
```

---

## ENUM 定義

```mql5
enum ENUM_SS_LOT_MODE
{
   SS_LOT_FIXED        = 0,  // Fixed Lot
   SS_LOT_RISK_PERCENT = 1,  // Risk % of Equity
};

enum ENUM_REVERSE_MODE
{
   REVERSE_CLOSE_AND_OPEN = 0,  // 決済してドテン
   REVERSE_IGNORE         = 1,  // 逆シグナル無視
};

enum ENUM_SS_LOG_LEVEL
{
   SS_LOG_NORMAL  = 0,  // Print() のみ
   SS_LOG_DEBUG   = 1,  // TSV ファイルログ
};
```

---

## OnTick の処理フロー

```
1. M5 新バー判定（前回処理バーと比較）
   → 新バーでなければ return

2. H1 新バー判定
   → 新バーなら:
     a. H1 レジーム判定を更新
     b. ポジション保有中 かつ レジーム終了 → Exit 4 実行（即決済）

3. ポジション保有中の場合:
   → ATR トレーリング SL 更新（Exit 2）
   → TP/SL ヒットは MT5 サーバー側で自動処理（Exit 1, Exit 3）
   → ポジション消滅を検出したら状態リセット

4. ポジション未保有の場合:
   → M5 EMA クロス判定
   → H1 方向フィルタ確認
   → 方向性フィルター確認
   → 時間フィルタ・スプレッドフィルタ
   → H1 Swing 検出 → TP 計算
   → SL 計算 + R:R チェック
   → すべて通過 → エントリー執行
```

---

## 通知メッセージフォーマット

### エントリー時

```
[SS_ENTRY] BUY  2026.03.12 14:05 | XAUUSD | 2700.00 | SL=2695.00 | TP=2730.00 | Lot=0.01
```

### Exit 時

```
[SS_EXIT] BUY  2026.03.12 16:30 | XAUUSD | 2720.00 | Profit=+200points | Reason=ATR_TRAIL
[SS_EXIT] BUY  2026.03.12 17:00 | XAUUSD | 2705.00 | Profit=+50points | Reason=H1_REGIME_END
```

Reason の種別:
- `TP_HIT`: TP 到達（H1 Swing）
- `SL_HIT`: 初期 SL ヒット
- `ATR_TRAIL`: ATR トレーリング SL ヒット
- `H1_REGIME_END`: H1 レジーム終了による即決済
- `REVERSE`: ドテン時の既存ポジション決済
- `EXTERNAL`: 外部決済（手動 or 他 EA）

---

## TSV ログ出力（LogLevel = DEBUG 時）

```
ファイル: MQL5/Files/SwingSignalEA_<YYYYMMDD>_<Symbol>_M<InstanceId>.tsv

カラム:
Time | Symbol | Event | Direction | Price | SL | TP | ATR | H1_Fast | H1_Slow | M5_Fast | M5_Slow | Detail
```

Event 種別: `ENTRY`, `EXIT`, `REJECT`, `TRAIL_UPDATE`, `REGIME_CHANGE`

---

## 実装上の注意点

1. `iMA()` / `iATR()` ハンドルは `OnInit()` でキャッシュし `OnTick()` で再生成しないこと
2. バッファ取得失敗時は安全に `return` すること
3. テスター環境では Push・メール通知を無効化すること
4. 新しい M5 バーが形成されたタイミングでのみシグナル判定を実行すること
5. H1 レジーム判定は新しい H1 バー確定時に実行すること
6. pips → price 変換は `SymbolInfoDouble(_Symbol, SYMBOL_POINT)` と桁数を考慮すること
7. OrderSend 失敗時はリトライせず、エラーログを出力すること
8. `#property strict` を付け、コンパイルが通る完全な MQL5 コードを出力すること
9. 省略なし・全文一括で出力すること
10. ATR トレーリングの SL 修正は `TRADE_ACTION_SLTP` で行うこと
11. H1 レジーム終了時の決済は `TRADE_ACTION_DEAL`（反対売買）で行うこと
12. ロット計算（Risk%モード）は FreeMargin 上限チェックを含めること
13. Filling モードはシンボルの `SYMBOL_FILLING_MODE` から自動判定すること
14. TF 切替時のステート保存は不要（RoleReversalEA のようなステートマシンではないため）

---

## ファイル構成

```
SwingSignalEA.mq5        -- メインファイル（単一ファイル）
```

モジュール分割は不要。単一ファイルで完結させること。
ただしコード量が 1500 行を超える場合は、以下のように分割してよい:

```
SwingSignalEA.mq5
SwingSignalEA/Constants.mqh
SwingSignalEA/H1SwingDetector.mqh
SwingSignalEA/Logger.mqh
```

---

## コード出力後に説明してほしいこと

1. バックテストの推奨設定（期間、モデル、スプレッド）
2. 最適化すべきパラメータの優先順位
3. 注意すべきリスク（過剰最適化、スプレッド感度など）
