# 部分指値決済EA (PartialLimitClose) 仕様書

## 概要

MT5用EA。指定したポジションに対して、最大3段階の指値レベルで部分決済を自動実行する。
MT5には「指値で部分決済」という注文タイプが存在しないため、EAがティックごとに価格を監視し、指定価格に到達した時点で `OrderSend` による成行決済を行う。

## 入力パラメータ

| パラメータ | 型 | デフォルト | 説明 |
|---|---|---|---|
| Ticket | long | 0 | 対象ポジションのチケット番号 |
| CloseType | ENUM_CLOSE_TYPE | CLOSE_TP | TP方向 or SL方向（混在禁止） |
| Level1_Price | double | 0.0 | レベル1の指値価格（0=無効） |
| Level1_LotPercent | double | 0.0 | 元ロットに対する割合%（0=残全部） |
| Level2_Price | double | 0.0 | レベル2の指値価格（0=無効） |
| Level2_LotPercent | double | 0.0 | 元ロットに対する割合%（0=残全部） |
| Level3_Price | double | 0.0 | レベル3の指値価格（0=無効） |
| Level3_LotPercent | double | 0.0 | 元ロットに対する割合%（0=残全部） |
| Slippage | int | 10 | スリッページ許容（ポイント） |
| UseAlert | bool | true | アラート通知 |
| UsePush | bool | true | プッシュ通知 |
| UseMail | bool | true | メール通知 |
| UseLog | bool | true | CSVファイルログ出力 |

## ENUM定義

```
ENUM_CLOSE_TYPE { CLOSE_TP=0, CLOSE_SL=1 }
```

- **CLOSE_TP**: 利確方向（Buy→価格が上昇して到達、Sell→価格が下降して到達）
- **CLOSE_SL**: 損切方向（Buy→価格が下降して到達、Sell→価格が上昇して到達）

## 動作仕様

### OnInit（起動時）

1. `PositionSelectByTicket(Ticket)` でポジション検索
2. 存在しない場合 → 警告メッセージ → `INIT_FAILED` で停止
3. 存在する場合、以下を取得・保存:
   - PositionID (`POSITION_IDENTIFIER`) — 以降の追跡に使用
   - ポジション方向 (`POSITION_TYPE`) — Buy/Sell
   - 元ロット (`POSITION_VOLUME`) — ロット計算の基準
   - シンボル (`POSITION_SYMBOL`)
4. レベル設定を解析（Price=0のレベルはスキップ）
5. **価格方向チェック**:
   - Buy + TP → 各レベル価格 > 現在価格
   - Buy + SL → 各レベル価格 < 現在価格
   - Sell + TP → 各レベル価格 < 現在価格
   - Sell + SL → 各レベル価格 > 現在価格
   - 不整合 → 警告メッセージ → `INIT_FAILED`
6. チャートに決済予定ラインを描画
7. ログファイルオープン（UseLog=true時）

### OnTick（ティック処理）

1. PositionIDでポジション存在確認
   - 存在しない場合（外部で決済された） → 通知 → EA自身を除去 (`ExpertRemove()`)
2. 現在価格取得: Buy → Bid、Sell → Ask
3. 未決済レベルを順にチェック:
   - TP方向: Buy → 現在価格 >= レベル価格、Sell → 現在価格 <= レベル価格
   - SL方向: Buy → 現在価格 <= レベル価格、Sell → 現在価格 >= レベル価格
4. 条件成立 → 部分決済実行
5. 全レベル決済完了 → 通知 → EA除去

### OnDeinit（終了時）

1. チャートラインを削除
2. ログファイルクローズ

## ロット計算

- **基準**: 元の総ロット（起動時に取得した値）
- **計算**: `元ロット × LotPercent / 100`
- **端数処理**: 最小ロット単位に切り上げ (`MathCeil`)
- **LotPercent=0**: 「残全部」＝現在のポジションロットをそのまま決済
- **「残全部」以降のレベル**: 無視（処理しない）

## 部分決済の実行

- `MqlTradeRequest.action = TRADE_ACTION_DEAL`
- `type`: Buy → `ORDER_TYPE_SELL`、Sell → `ORDER_TYPE_BUY`
- `position`: PositionID で指定
- `volume`: 計算されたロット
- `deviation`: Slippage パラメータ値

## チャートライン

- 各有効レベルの価格に水平ライン (`OBJ_HLINE`) を描画
- TP方向: 緑系 (`clrLime`)
- SL方向: 赤系 (`clrRed`)
- ラインにはレベル番号とロット情報をツールチップ表示
- 決済完了したレベルのラインは削除

## 通知

決済実行時に以下を送信（各input設定に従う）:
- Alert（画面ポップアップ）
- Push通知
- メール通知

通知メッセージにはシンボル、レベル番号、決済ロット、決済価格を含む。

## ログ

- ファイルパス: `MQL5/Files/PartialLimitClose_log.csv`
- フォーマット: CSV
- 記録項目: 日時, シンボル, チケット, レベル番号, 方向, 決済ロット, 決済価格
- ヘッダー行あり（ファイル新規作成時のみ）

## 制約・前提

- 1チャートにつき1ポジションのみ管理
- CloseType（TP/SL）は混在禁止（混在させたい場合は別チャートで起動）
- EA再起動時の設定復元はしない
- マジックナンバーフィルタは不要（チケット直接指定のため）
