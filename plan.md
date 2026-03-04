# 部分指値決済EA 実装計画

## ファイル構成
- **新規作成**: `src/Experts/PartialLimitClose.mq5` （1ファイル完結、既存コードの規約に準拠）
- **新規作成**: `docs/PartialLimitClose_spec.md` （仕様書）

## 実装ステップ

### Step 1: 仕様書作成
`docs/PartialLimitClose_spec.md` にチャットで合意した全仕様を記録。

### Step 2: EA本体の実装 (`src/Experts/PartialLimitClose.mq5`)

ファイル内構成（既存コードの規約に合わせる）:

```
//+------------------------------------------------------------------+
// ヘッダー
//+------------------------------------------------------------------+

//===== ENUM =====
enum ENUM_CLOSE_TYPE { CLOSE_TP=0, CLOSE_SL=1 };

//===== INPUTS =====
// Ticket, CloseType, Level1-3 (Price, LotPercent), Slippage
// 通知系 (Alert, Push, Mail), ログ

//===== GLOBALS =====
// gPositionID, gOriginalLots, gSymbol, gPositionType
// gLevel構造体配列, gLinesCreated, etc.

//===== OnInit =====
// 1. チケットでポジション検索（PositionSelectByTicket）
// 2. 存在しなければ警告→INIT_FAILED
// 3. PositionID, 方向, 元ロット, シンボル取得
// 4. レベル設定の解析・検証
//    - Price=0のレベルはスキップ
//    - LotPercent=0は「残全部」→以降のレベル無視
//    - 合計ロット割合が100%超えないかチェック
// 5. 価格方向チェック（CloseType × PositionType）
//    - Buy+TP: 全Price > エントリー価格
//    - Buy+SL: 全Price < エントリー価格
//    - Sell+TP: 全Price < エントリー価格
//    - Sell+SL: 全Price > エントリー価格
//    - 不整合→Alert警告→INIT_FAILED
// 6. チャートラインを描画
// 7. ログファイルオープン

//===== OnTick =====
// 1. PositionIDでポジション存在確認
//    - 消滅していたら通知→EA除去（ExpertRemove）
// 2. 現在価格取得（Buy→Bid, Sell→Ask）
// 3. 未決済の各レベルを順にチェック
//    - TP方向: Buy=Bid>=Price / Sell=Ask<=Price
//    - SL方向: Buy=Bid<=Price / Sell=Ask>=Price
// 4. 条件成立→部分決済実行
//    a. ロット計算（元ロット×割合%、端数切り上げ）
//    b. 「残全部」の場合は現在の残ロットを使用
//    c. 残ロットより多い場合は残ロットに調整
//    d. OrderSendで決済（MQL5: 反対売買）
//    e. 成功→レベルを「済」にマーク、ライン削除、通知、ログ
//    f. 失敗→エラーログ（次ティックでリトライ）
// 5. 全レベル決済完了→通知→EA除去

//===== OnDeinit =====
// 1. チャートライン削除
// 2. ログファイルクローズ

//===== ユーティリティ関数 =====
// - ExecutePartialClose(): 部分決済OrderSend
// - CalcLots(): ロット計算（切り上げ）
// - DrawLine() / RemoveLine(): ライン管理
// - Notify(): Alert/Push/Mail統合通知
// - WriteLog(): CSV書き込み
// - ValidateLevels(): 入力値検証
```

### Step 3: 動作確認ポイント（手動テスト項目）
- 存在しないチケットで起動→警告停止
- 価格方向不整合で起動→警告停止
- TP/SL各方向で正常決済
- 「残全部」指定の動作
- 外部決済時のEA自動停止
- ライン表示・削除
- ログCSV出力
- 通知送信
