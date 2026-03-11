//+------------------------------------------------------------------+
//|                                         GC_DC_SwingNotifier.mq5  |
//|         Golden Cross / Dead Cross with Swing Filter Notifier     |
//|                                                                  |
//|  EMA13/21のクロスを M5/M15/H1/H4 で並行監視し、                  |
//|  方向性フィルター＋Swing高安値フィルターを通過した場合のみ通知    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

// --- Plot 0: Fast EMA ---
#property indicator_label1  "EMA Fast"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

// --- Plot 1: Slow EMA ---
#property indicator_label2  "EMA Slow"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//--- MA 設定 ---
input int    EMA_Fast           = 13;         // Fast EMA 期間
input int    EMA_Slow           = 21;         // Slow EMA 期間
input bool   UseEMA             = true;       // true: EMA / false: SMA

//--- Swing 設定 ---
input int    SwingStrength      = 5;          // Swing 判定の左右本数（推奨: 3〜7）
input int    SwingWindow_M5     = 5;          // M5:  Swing からクロスまでの許容本数
input int    SwingWindow_M15    = 6;          // M15: Swing からクロスまでの許容本数
input int    SwingWindow_H1     = 8;          // H1:  Swing からクロスまでの許容本数
input int    SwingWindow_H4     = 10;         // H4:  Swing からクロスまでの許容本数

//--- 監視時間足 ON/OFF ---
input bool   Use_M5             = true;
input bool   Use_M15            = true;
input bool   Use_H1             = true;
input bool   Use_H4             = true;

//--- 通知設定 ---
input bool   EnablePopupAlert   = true;       // MT5 画面アラート
input bool   EnablePush         = true;       // Push 通知（MT5 モバイル）
input bool   EnableEmail        = false;      // メール通知
input bool   EnableSound        = false;      // サウンド通知
input string SoundFile          = "alert.wav";

//--- チャート表示 ---
input bool   ShowArrows         = true;       // シグナル矢印表示

//--- チャート描画用バッファ ---
double BufFastEMA[];
double BufSlowEMA[];

//--- チャート時間足用 MA ハンドル ---
int hChartFast = INVALID_HANDLE;
int hChartSlow = INVALID_HANDLE;

//--- 4TF 監視用 ---
ENUM_TIMEFRAMES tfList[] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
#define TF_COUNT 4

int  hFast[TF_COUNT];          // 各TFの Fast MA ハンドル
int  hSlow[TF_COUNT];          // 各TFの Slow MA ハンドル

//--- 重複通知防止用（各TF × GC/DC）: [tfIdx][0=DC, 1=GC] ---
datetime lastAlertTime[TF_COUNT][2];

//--- 矢印オブジェクトのプレフィックス ---
const string arrowPrefix = "GCDC_Arrow_";

//+------------------------------------------------------------------+
//| TFインデックスから使用フラグを取得                               |
//+------------------------------------------------------------------+
bool IsTFEnabled(int idx)
{
   switch(idx)
   {
      case 0: return Use_M5;
      case 1: return Use_M15;
      case 2: return Use_H1;
      case 3: return Use_H4;
   }
   return false;
}

//+------------------------------------------------------------------+
//| TFインデックスから SwingWindow を取得                            |
//+------------------------------------------------------------------+
int GetSwingWindow(int idx)
{
   switch(idx)
   {
      case 0: return SwingWindow_M5;
      case 1: return SwingWindow_M15;
      case 2: return SwingWindow_H1;
      case 3: return SwingWindow_H4;
   }
   return 5;
}

//+------------------------------------------------------------------+
//| 重複防止用の datetime を取得/設定                                |
//+------------------------------------------------------------------+
datetime GetLastAlertTime(int tfIdx, bool isGC)
{
   return lastAlertTime[tfIdx][isGC ? 1 : 0];
}

void SetLastAlertTime(int tfIdx, bool isGC, datetime dt)
{
   lastAlertTime[tfIdx][isGC ? 1 : 0] = dt;
}

//+------------------------------------------------------------------+
//| ENUM_TIMEFRAMES を短縮文字列に変換                               |
//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
   }
   return EnumToString(tf);
}

//+------------------------------------------------------------------+
//| 通知送信（全手段を一括処理）                                     |
//|                                                                  |
//| 注意: SendNotification() を使用するには MT5 の                   |
//|       ツール→オプション→通知 でMetaQuotes IDの登録が必要です     |
//| 注意: SendMail() を使用するには MT5 の                           |
//|       ツール→オプション→Eメール でSMTPサーバーの設定が必要です   |
//+------------------------------------------------------------------+
void SendSignalNotification(string message)
{
   // テスター環境では Push・メール通知を無効化
   bool isTester = (bool)MQLInfoInteger(MQL_TESTER);

   if(EnablePopupAlert)
      Alert(message);

   if(EnablePush && !isTester)
      SendNotification(message);

   if(EnableEmail && !isTester)
      SendMail("GC/DC Alert", message);

   if(EnableSound)
      PlaySound(SoundFile);
}

//+------------------------------------------------------------------+
//| 通知メッセージを組み立てる                                       |
//+------------------------------------------------------------------+
string BuildMessage(bool isGC, datetime barTime, double closePrice, ENUM_TIMEFRAMES tf)
{
   string type = isGC ? "GC" : "DC";
   string timeStr = TimeToString(barTime, TIME_DATE | TIME_MINUTES);
   string rateStr = DoubleToString(closePrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   string tfStr   = TFToString(tf);

   return "[" + type + "] " + timeStr + " | " + _Symbol + " | " + rateStr + " | " + tfStr;
}

//+------------------------------------------------------------------+
//| Swing High を検出: 指定バー(center)が左右strength本のHighより高い |
//| high[] は [0]=最新 の降順を想定                                  |
//+------------------------------------------------------------------+
bool IsSwingHigh(const double &high[], int center, int strength, int totalBars)
{
   if(center - strength < 0 || center + strength >= totalBars)
      return false;

   double centerHigh = high[center];
   for(int i = 1; i <= strength; i++)
   {
      if(high[center - i] >= centerHigh) return false;
      if(high[center + i] >= centerHigh) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Swing Low を検出: 指定バー(center)が左右strength本のLowより低い  |
//+------------------------------------------------------------------+
bool IsSwingLow(const double &low[], int center, int strength, int totalBars)
{
   if(center - strength < 0 || center + strength >= totalBars)
      return false;

   double centerLow = low[center];
   for(int i = 1; i <= strength; i++)
   {
      if(low[center - i] <= centerLow) return false;
      if(low[center + i] <= centerLow) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| 矢印オブジェクトの作成                                          |
//+------------------------------------------------------------------+
void CreateArrow(bool isGC, datetime time, double price, ENUM_TIMEFRAMES tf)
{
   if(!ShowArrows) return;

   string name = arrowPrefix + TFToString(tf) + "_" + (isGC ? "GC" : "DC") + "_" + IntegerToString((long)time);

   if(ObjectFind(0, name) != -1) return;

   if(isGC)
   {
      if(!ObjectCreate(0, name, OBJ_ARROW_UP, 0, time, price)) return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   }
   else
   {
      if(!ObjectCreate(0, name, OBJ_ARROW_DOWN, 0, time, price)) return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_TOP);
   }
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| 特定時間足のクロス判定・フィルター・通知を実行                   |
//+------------------------------------------------------------------+
void CheckTimeframe(int tfIdx)
{
   if(!IsTFEnabled(tfIdx)) return;

   ENUM_TIMEFRAMES tf = tfList[tfIdx];
   int swWindow = GetSwingWindow(tfIdx);

   // CopyBuffer に必要な本数（仕様: SwingStrength*2 + SwingWindow_H4 + 5 以上）
   // +2: クロス判定に必要な shift[1],shift[2]
   // +3: IsSwingLow/High が center+strength まで参照するための余裕
   int minWindow = (swWindow > SwingWindow_H4) ? swWindow : SwingWindow_H4;
   int needBars = SwingStrength * 2 + minWindow + 5;

   // --- MA値取得 ---
   double fastMA[];
   double slowMA[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);

   if(CopyBuffer(hFast[tfIdx], 0, 0, needBars, fastMA) < needBars) return;
   if(CopyBuffer(hSlow[tfIdx], 0, 0, needBars, slowMA) < needBars) return;

   // --- 価格データ取得（Swing判定用） ---
   double high[];
   double low[];
   double close[];
   datetime time[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);

   if(CopyHigh(_Symbol, tf, 0, needBars, high)   < needBars) return;
   if(CopyLow(_Symbol, tf, 0, needBars, low)     < needBars) return;
   if(CopyClose(_Symbol, tf, 0, needBars, close)  < needBars) return;
   if(CopyTime(_Symbol, tf, 0, needBars, time)    < needBars) return;

   // --- クロス判定（確定足ベース: shift[1] = 最新確定足, shift[2] = その1本前） ---
   // shift[0] は未確定足なので判定対象外
   bool crossGC = (fastMA[2] < slowMA[2]) && (fastMA[1] > slowMA[1]);
   bool crossDC = (fastMA[2] > slowMA[2]) && (fastMA[1] < slowMA[1]);

   if(!crossGC && !crossDC) return;

   // --- 方向性フィルター ---
   // 将来的に最小傾き閾値（input）を追加可能な設計:
   // double minSlope = 0.0; として比較を > minSlope に変更すればよい
   double slopeFast = fastMA[1] - fastMA[2];
   double slopeSlow = slowMA[1] - slowMA[2];

   if(crossGC)
   {
      if(slopeFast <= 0.0 || slopeSlow <= 0.0) return;  // 両MAが上向きでなければ不成立
   }
   if(crossDC)
   {
      if(slopeFast >= 0.0 || slopeSlow >= 0.0) return;  // 両MAが下向きでなければ不成立
   }

   // --- Swing 近辺フィルター ---
   // GC: 直近の Swing Low から swWindow 本以内にクロス発生
   // DC: 直近の Swing High から swWindow 本以内にクロス発生
   bool swingFound = false;

   if(crossGC)
   {
      // shift[1]（クロス発生バー）から遡って swWindow 本以内に Swing Low があるか
      // center は SwingStrength 以上でないと左右の比較ができないため、そこから開始
      for(int s = SwingStrength; s <= swWindow; s++)
      {
         if(IsSwingLow(low, s, SwingStrength, needBars))
         {
            swingFound = true;
            break;
         }
      }
   }
   else // crossDC
   {
      for(int s = SwingStrength; s <= swWindow; s++)
      {
         if(IsSwingHigh(high, s, SwingStrength, needBars))
         {
            swingFound = true;
            break;
         }
      }
   }

   if(!swingFound) return;

   // --- 重複通知チェック ---
   datetime barTime = time[1];  // クロス発生バーの時刻
   bool isGC = crossGC;

   if(GetLastAlertTime(tfIdx, isGC) == barTime) return;  // 同一バーでは通知済み

   // --- 通知実行 ---
   SetLastAlertTime(tfIdx, isGC, barTime);

   double closePrice = close[1];
   string message = BuildMessage(isGC, barTime, closePrice, tf);
   SendSignalNotification(message);

   // --- 矢印表示（チャート時間足と一致する場合のみ） ---
   if(tf == (ENUM_TIMEFRAMES)ChartPeriod(0))
   {
      CreateArrow(isGC, barTime, isGC ? low[1] : high[1], tf);
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- 入力値バリデーション ---
   if(EMA_Fast >= EMA_Slow)
   {
      Print("Error: EMA_Fast は EMA_Slow より小さい値を指定してください");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(SwingStrength < 1)
   {
      Print("Error: SwingStrength は 1 以上を指定してください");
      return INIT_PARAMETERS_INCORRECT;
   }

   // --- 重複通知防止用配列を初期化 ---
   ArrayInitialize(lastAlertTime, 0);

   // --- チャート描画用バッファ設定 ---
   SetIndexBuffer(0, BufFastEMA, INDICATOR_DATA);
   SetIndexBuffer(1, BufSlowEMA, INDICATOR_DATA);

   ENUM_MA_METHOD maMethod = UseEMA ? MODE_EMA : MODE_SMA;
   ENUM_TIMEFRAMES chartTF = (ENUM_TIMEFRAMES)ChartPeriod(0);

   // チャート時間足用 MA ハンドル
   hChartFast = iMA(_Symbol, chartTF, EMA_Fast, 0, maMethod, PRICE_CLOSE);
   hChartSlow = iMA(_Symbol, chartTF, EMA_Slow, 0, maMethod, PRICE_CLOSE);

   if(hChartFast == INVALID_HANDLE || hChartSlow == INVALID_HANDLE)
   {
      Print("Error: チャート用MAハンドルの作成に失敗しました");
      return INIT_FAILED;
   }

   // --- 4TF 監視用 MA ハンドルをキャッシュ ---
   for(int i = 0; i < TF_COUNT; i++)
   {
      if(IsTFEnabled(i))
      {
         hFast[i] = iMA(_Symbol, tfList[i], EMA_Fast, 0, maMethod, PRICE_CLOSE);
         hSlow[i] = iMA(_Symbol, tfList[i], EMA_Slow, 0, maMethod, PRICE_CLOSE);

         if(hFast[i] == INVALID_HANDLE || hSlow[i] == INVALID_HANDLE)
         {
            PrintFormat("Error: TF=%s のMAハンドル作成に失敗しました", TFToString(tfList[i]));
            return INIT_FAILED;
         }
      }
      else
      {
         hFast[i] = INVALID_HANDLE;
         hSlow[i] = INVALID_HANDLE;
      }
   }

   // --- インジケーター名設定 ---
   string shortName = "GC/DC Swing(" + IntegerToString(EMA_Fast) + "/" + IntegerToString(EMA_Slow) + ")";
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   // --- チャート時間足の EMA をバッファに描画 ---
   int toCopy = rates_total - prev_calculated;
   if(prev_calculated == 0) toCopy = rates_total;
   if(toCopy <= 0) toCopy = 1;

   double tmpFast[];
   double tmpSlow[];

   if(CopyBuffer(hChartFast, 0, 0, toCopy, tmpFast) <= 0) return prev_calculated;
   if(CopyBuffer(hChartSlow, 0, 0, toCopy, tmpSlow) <= 0) return prev_calculated;

   // tmpFast/tmpSlow は時系列降順ではない（古い→新しい）
   int startIdx = rates_total - toCopy;
   for(int i = 0; i < toCopy; i++)
   {
      BufFastEMA[startIdx + i] = tmpFast[i];
      BufSlowEMA[startIdx + i] = tmpSlow[i];
   }

   // --- 各時間足のクロス判定（確定足ベース） ---
   for(int tf = 0; tf < TF_COUNT; tf++)
   {
      CheckTimeframe(tf);
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // チャート用ハンドル解放
   if(hChartFast != INVALID_HANDLE) IndicatorRelease(hChartFast);
   if(hChartSlow != INVALID_HANDLE) IndicatorRelease(hChartSlow);

   // 4TF用ハンドル解放
   for(int i = 0; i < TF_COUNT; i++)
   {
      if(hFast[i] != INVALID_HANDLE) IndicatorRelease(hFast[i]);
      if(hSlow[i] != INVALID_HANDLE) IndicatorRelease(hSlow[i]);
   }

   // 矢印オブジェクト削除
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, arrowPrefix) == 0)
         ObjectDelete(0, name);
   }
}
//+------------------------------------------------------------------+
