//+------------------------------------------------------------------+
//| PartialLimitClose.mq5                                            |
//| 部分指値決済EA                                                    |
//| ティック監視で指定価格到達時に部分決済を実行                       |
//+------------------------------------------------------------------+
#property copyright "YujiRS"
#property version   "1.00"
#property strict

//================ ENUM =================
enum ENUM_CLOSE_TYPE
{
   CLOSE_TP = 0, // TP方向（利確）
   CLOSE_SL = 1  // SL方向（損切）
};

//================ INPUTS =================
input long            Ticket          = 0;        // 対象ポジションのチケット番号
input ENUM_CLOSE_TYPE CloseType       = CLOSE_TP; // 決済方向

input double Level1_Price      = 0.0; // レベル1 指値価格（0=無効）
input double Level1_LotPercent = 0.0; // レベル1 ロット割合%（0=残全部）
input double Level2_Price      = 0.0; // レベル2 指値価格（0=無効）
input double Level2_LotPercent = 0.0; // レベル2 ロット割合%（0=残全部）
input double Level3_Price      = 0.0; // レベル3 指値価格（0=無効）
input double Level3_LotPercent = 0.0; // レベル3 ロット割合%（0=残全部）

input int  Slippage = 10;   // スリッページ許容（ポイント）

input bool UseAlert = true;  // アラート通知
input bool UsePush  = true;  // プッシュ通知
input bool UseMail  = true;  // メール通知
input bool UseLog   = true;  // CSVファイルログ

//================ LEVEL STRUCT =================
struct LevelInfo
{
   double price;
   double lotPercent;
   bool   done;
   string lineName;
};

//================ GLOBALS =================
long           gPositionID   = 0;
ENUM_POSITION_TYPE gPosType  = POSITION_TYPE_BUY;
double         gOrigLot      = 0.0;
string         gSymbol       = "";
int            gLevelCount   = 0;
LevelInfo      gLevels[3];
int            gLogHandle    = INVALID_HANDLE;
string         gObjPrefix    = "PLC_";
string         gTicketHistory = "";
long           gLastTicket    = 0;

//================ UTILS =================
void Notify(string msg)
{
   if(UseAlert) Alert(msg);
   if(UsePush)  SendNotification(msg);
   if(UseMail)  SendMail("[PLC] " + gSymbol, msg);
}

void WriteLog(int levelIndex, double closeLot, double closePrice)
{
   if(!UseLog || gLogHandle == INVALID_HANDLE) return;

   string line = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ","
               + gSymbol + ","
               + IntegerToString(gLastTicket) + ","
               + IntegerToString(levelIndex + 1) + ","
               + (gPosType == POSITION_TYPE_BUY ? "BUY" : "SELL") + ","
               + DoubleToString(closeLot, 2) + ","
               + DoubleToString(closePrice, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS));
   FileWriteString(gLogHandle, line + "\n");
   FileFlush(gLogHandle);
}

void DrawLine(int index)
{
   string name = gObjPrefix + IntegerToString(index);
   gLevels[index].lineName = name;

   color lineColor = (CloseType == CLOSE_TP) ? clrLime : clrRed;

   ObjectCreate(0, name, OBJ_HLINE, 0, 0, gLevels[index].price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);

   string tooltip = "Level" + IntegerToString(index + 1) + " ";
   if(gLevels[index].lotPercent <= 0.0)
      tooltip += "残全部";
   else
      tooltip += DoubleToString(gLevels[index].lotPercent, 1) + "%";
   tooltip += " @ " + DoubleToString(gLevels[index].price, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS));
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);

   // レベルラベル表示
   string lblName = gObjPrefix + "L" + IntegerToString(index);
   ObjectCreate(0, lblName, OBJ_TEXT, 0, TimeCurrent(), gLevels[index].price);
   ObjectSetString(0, lblName, OBJPROP_TEXT, tooltip);
   ObjectSetInteger(0, lblName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
}

//================ STATE PERSISTENCE =================
string StateFileName()
{
   return "PLC_state_" + IntegerToString(gPositionID) + ".txt";
}

string BuildParamLine()
{
   int digits = (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS);
   return IntegerToString(Ticket) + ","
        + IntegerToString(CloseType) + ","
        + DoubleToString(Level1_Price, digits) + ","
        + DoubleToString(Level1_LotPercent, 1) + ","
        + DoubleToString(Level2_Price, digits) + ","
        + DoubleToString(Level2_LotPercent, 1) + ","
        + DoubleToString(Level3_Price, digits) + ","
        + DoubleToString(Level3_LotPercent, 1);
}

void SaveState()
{
   int h = FileOpen(StateFileName(), FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("PartialLimitClose: 状態ファイル書き込み失敗 error=", GetLastError());
      return;
   }

   // Line 1: input params snapshot
   FileWriteString(h, BuildParamLine() + "\n");

   // Line 2: original lot
   FileWriteString(h, DoubleToString(gOrigLot, 2) + "\n");

   // Line 3: done flags
   string doneStr = "";
   for(int i = 0; i < 3; i++)
   {
      if(i > 0) doneStr += ",";
      doneStr += (i < gLevelCount && gLevels[i].done) ? "1" : "0";
   }
   FileWriteString(h, doneStr + "\n");

   // Line 4: last ticket
   FileWriteString(h, IntegerToString(gLastTicket) + "\n");

   // Line 5: ticket history
   FileWriteString(h, gTicketHistory + "\n");

   FileClose(h);
}

bool LoadState()
{
   string fname = StateFileName();
   if(!FileIsExist(fname)) return false;

   int h = FileOpen(fname, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return false;

   // Line 1: check params match
   string paramLine = "";
   if(!FileIsEnding(h)) paramLine = FileReadString(h);
   if(paramLine != BuildParamLine())
   {
      FileClose(h);
      FileDelete(fname);
      Print("PartialLimitClose: 状態ファイル パラメータ不一致 → 破棄");
      return false;
   }

   // Line 2: original lot
   string lotLine = "";
   if(!FileIsEnding(h)) lotLine = FileReadString(h);
   double savedOrigLot = StringToDouble(lotLine);
   if(savedOrigLot <= 0.0)
   {
      FileClose(h);
      FileDelete(fname);
      return false;
   }

   // Line 3: done flags
   string doneLine = "";
   if(!FileIsEnding(h)) doneLine = FileReadString(h);
   string doneArr[];
   int cnt = StringSplit(doneLine, ',', doneArr);

   // Line 4: last ticket
   string ticketLine = "";
   if(!FileIsEnding(h)) ticketLine = FileReadString(h);

   // Line 5: ticket history
   string histLine = "";
   if(!FileIsEnding(h)) histLine = FileReadString(h);

   FileClose(h);

   // Apply restored state
   gOrigLot = savedOrigLot;
   for(int i = 0; i < gLevelCount && i < cnt; i++)
      gLevels[i].done = (doneArr[i] == "1");

   gLastTicket    = StringToInteger(ticketLine);
   gTicketHistory = histLine;

   Print("PartialLimitClose: 状態復元完了 OrigLot=", DoubleToString(gOrigLot, 2),
         " LastTicket=", gLastTicket);
   return true;
}

void DeleteStateFile()
{
   string fname = StateFileName();
   if(FileIsExist(fname))
      FileDelete(fname);
}

//================ CHART DISPLAY =================
void UpdateChartDisplay()
{
   string posDir = (gPosType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
   string ctStr  = (CloseType == CLOSE_TP) ? "TP" : "SL";

   // Line 4 (top):    PLC | BUY-TP | PosID: 12345
   string line4 = "PLC | " + posDir + "-" + ctStr + " | PosID: " + IntegerToString(gPositionID);

   // Line 3:          Ticket: 67890 -> 67891(L1)
   string line3 = "Ticket: " + gTicketHistory;

   // Line 2:          Lot: 1.00 -> 0.60
   double remainLot = 0.0;
   if(FindPositionByID(gPositionID))
      remainLot = PositionGetDouble(POSITION_VOLUME);
   string line2 = "Lot: " + DoubleToString(gOrigLot, 2) + " -> " + DoubleToString(remainLot, 2);

   // Line 1 (bottom): L1:済  L2:待機  L3:待機
   string line1 = "";
   for(int i = 0; i < gLevelCount; i++)
   {
      if(i > 0) line1 += "  ";
      line1 += "L" + IntegerToString(i + 1) + ":";
      line1 += gLevels[i].done ? "済" : "待機";
   }

   // index 0 = bottom-most
   string lines[4];
   lines[0] = line1;
   lines[1] = line2;
   lines[2] = line3;
   lines[3] = line4;

   for(int i = 0; i < 4; i++)
   {
      string name = gObjPrefix + "DSP" + IntegerToString(i);
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 15 + i * 18);
      ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
   }

   ChartRedraw(0);
}

void RemoveDisplay()
{
   for(int i = 0; i < 4; i++)
      ObjectDelete(0, gObjPrefix + "DSP" + IntegerToString(i));
}

void RemoveLine(int index)
{
   ObjectDelete(0, gLevels[index].lineName);
   ObjectDelete(0, gObjPrefix + "L" + IntegerToString(index));
}

void RemoveAllLines()
{
   for(int i = 0; i < gLevelCount; i++)
   {
      RemoveLine(i);
   }
}

//================ LEVEL VALIDATION =================
bool ValidateLevels()
{
   double currentPrice;
   if(gPosType == POSITION_TYPE_BUY)
      currentPrice = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   else
      currentPrice = SymbolInfoDouble(gSymbol, SYMBOL_ASK);

   for(int i = 0; i < gLevelCount; i++)
   {
      if(gLevels[i].done) continue; // 復元済みレベルはスキップ

      double lvlPrice = gLevels[i].price;
      bool valid = false;

      if(gPosType == POSITION_TYPE_BUY)
      {
         if(CloseType == CLOSE_TP)
            valid = (lvlPrice > currentPrice);
         else
            valid = (lvlPrice < currentPrice);
      }
      else // SELL
      {
         if(CloseType == CLOSE_TP)
            valid = (lvlPrice < currentPrice);
         else
            valid = (lvlPrice > currentPrice);
      }

      if(!valid)
      {
         string dir = (gPosType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         string ct  = (CloseType == CLOSE_TP) ? "TP" : "SL";
         Alert("PartialLimitClose: Level" + IntegerToString(i + 1)
             + " 価格方向が不正です。"
             + " ポジション=" + dir + " CloseType=" + ct
             + " 価格=" + DoubleToString(lvlPrice, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS))
             + " 現在値=" + DoubleToString(currentPrice, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS)));
         return false;
      }
   }
   return true;
}

//================ LOT CALCULATION =================
double CalcLots(int levelIndex)
{
   // 残全部
   if(gLevels[levelIndex].lotPercent <= 0.0)
   {
      if(!FindPositionByID(gPositionID)) return 0.0;
      return PositionGetDouble(POSITION_VOLUME);
   }

   double lots = gOrigLot * gLevels[levelIndex].lotPercent / 100.0;

   double lotMin  = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_STEP);
   double lotMax  = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MAX);

   // 最小ロット単位に切り上げ
   if(lotStep > 0)
      lots = MathCeil(lots / lotStep) * lotStep;

   if(lots < lotMin)
      lots = lotMin;
   if(lots > lotMax)
      lots = lotMax;

   // 現在の残ロットを超えないようにする
   if(!FindPositionByID(gPositionID)) return 0.0;
   double remaining = PositionGetDouble(POSITION_VOLUME);
   if(lots > remaining)
      lots = remaining;

   int lotDigits = (lotStep > 0) ? (int)MathRound(-MathLog10(lotStep)) : 2;
   if(lotDigits < 0) lotDigits = 0;
   return NormalizeDouble(lots, lotDigits);
}

//================ PARTIAL CLOSE EXECUTION =================
bool ExecutePartialClose(int levelIndex)
{
   double lots = CalcLots(levelIndex);
   if(lots <= 0.0) return false;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = gSymbol;
   request.volume    = lots;
   request.type      = (gPosType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.position  = (ulong)gLastTicket;
   request.deviation = Slippage;

   // Filling Modeをシンボル対応モードから自動設定
   long fillMode = SymbolInfoInteger(gSymbol, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_FOK) != 0)
      request.type_filling = ORDER_FILLING_FOK;
   else if((fillMode & SYMBOL_FILLING_IOC) != 0)
      request.type_filling = ORDER_FILLING_IOC;
   else
      request.type_filling = ORDER_FILLING_FOK;

   if(gPosType == POSITION_TYPE_BUY)
      request.price = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   else
      request.price = SymbolInfoDouble(gSymbol, SYMBOL_ASK);

   if(!OrderSend(request, result))
   {
      Alert("PartialLimitClose: Level" + IntegerToString(levelIndex + 1)
          + " 決済失敗 エラー=" + IntegerToString(result.retcode));
      return false;
   }

   // リクオート・価格変更は次ティックで再試行（Alertなし）
   if(result.retcode == TRADE_RETCODE_REQUOTE || result.retcode == TRADE_RETCODE_PRICE_CHANGED)
   {
      Print("PartialLimitClose: リクオート発生、次ティックで再試行 retcode=", result.retcode);
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_DONE_PARTIAL)
   {
      Alert("PartialLimitClose: Level" + IntegerToString(levelIndex + 1)
          + " 決済リジェクト retcode=" + IntegerToString(result.retcode));
      return false;
   }

   // 成功
   gLevels[levelIndex].done = true;
   RemoveLine(levelIndex);

   // チケット履歴更新（部分決済後、残ポジションのチケットが変わる場合がある）
   if(FindPositionByID(gPositionID))
   {
      long curTicket = (long)PositionGetInteger(POSITION_TICKET);
      gTicketHistory += " -> " + IntegerToString(curTicket) + "(L" + IntegerToString(levelIndex + 1) + ")";
      gLastTicket = curTicket;
   }
   UpdateChartDisplay();
   SaveState();

   string msg = "PartialLimitClose: " + gSymbol
              + " Level" + IntegerToString(levelIndex + 1)
              + " 決済完了"
              + " Lot=" + DoubleToString(lots, 2)
              + " Price=" + DoubleToString(result.price, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS));
   Notify(msg);
   WriteLog(levelIndex, lots, result.price);

   return true;
}

//================ POSITION FINDER BY ID =================
bool FindPositionByID(long posID)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetInteger(POSITION_IDENTIFIER) == posID)
         return true;
   }
   return false;
}

//================ INIT =================
int OnInit()
{
   // チケット未指定チェック
   if(Ticket <= 0)
   {
      Alert("PartialLimitClose: チケット番号が指定されていません。");
      return INIT_FAILED;
   }

   // ポジション検索
   if(!PositionSelectByTicket(Ticket))
   {
      Alert("PartialLimitClose: チケット " + IntegerToString(Ticket) + " のポジションが見つかりません。");
      return INIT_FAILED;
   }

   // ポジション情報取得
   gPositionID = PositionGetInteger(POSITION_IDENTIFIER);
   gPosType    = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   gOrigLot    = PositionGetDouble(POSITION_VOLUME);
   gSymbol     = PositionGetString(POSITION_SYMBOL);

   if(gSymbol != _Symbol)
      Alert("PartialLimitClose: ポジションのシンボル(" + gSymbol + ")とチャートのシンボル(" + _Symbol + ")が異なります。ティック監視が不正確になる可能性があります。");

   // レベル設定の解析
   double prices[3]   = { Level1_Price, Level2_Price, Level3_Price };
   double percents[3]  = { Level1_LotPercent, Level2_LotPercent, Level3_LotPercent };

   gLevelCount = 0;
   bool gotCloseAll = false;

   for(int i = 0; i < 3; i++)
   {
      if(gotCloseAll) break; // 「残全部」以降は無視
      if(prices[i] <= 0.0) continue; // 価格=0 はスキップ

      gLevels[gLevelCount].price      = prices[i];
      gLevels[gLevelCount].lotPercent = percents[i];
      gLevels[gLevelCount].done       = false;
      gLevels[gLevelCount].lineName   = "";
      gLevelCount++;

      if(percents[i] <= 0.0)
         gotCloseAll = true; // 残全部が出たら以降無視
   }

   if(gLevelCount == 0)
   {
      Alert("PartialLimitClose: 有効なレベルが設定されていません。");
      return INIT_FAILED;
   }

   // 状態復元を試行（パラメータ一致時のみ復元）
   bool stateRestored = LoadState();

   // 価格方向チェック（復元済みレベルはスキップ）
   if(!ValidateLevels())
      return INIT_FAILED;

   // チャートラインを描画（済みレベルはスキップ）
   for(int i = 0; i < gLevelCount; i++)
   {
      if(!gLevels[i].done)
         DrawLine(i);
   }
   ChartRedraw(0);

   // ログファイルオープン
   if(UseLog)
   {
      gLogHandle = FileOpen("PartialLimitClose_log.csv",
                            FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(gLogHandle != INVALID_HANDLE)
      {
         // ファイル末尾が0なら（新規）ヘッダー出力
         FileSeek(gLogHandle, 0, SEEK_END);
         if(FileTell(gLogHandle) == 0)
            FileWriteString(gLogHandle, "DateTime,Symbol,Ticket,Level,Direction,Lot,Price\n");
      }
   }

   // チケット履歴初期化（状態復元時は復元値を使用）
   if(!stateRestored)
   {
      gTicketHistory = IntegerToString(Ticket);
      gLastTicket    = Ticket;
   }

   string posDir = (gPosType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
   string ctStr  = (CloseType == CLOSE_TP) ? "TP" : "SL";
   Print("PartialLimitClose: 起動 Ticket=", Ticket,
         " PositionID=", gPositionID,
         " ", posDir, " ", ctStr,
         " OrigLot=", DoubleToString(gOrigLot, 2),
         " Levels=", gLevelCount);

   // チャート左下に情報表示
   UpdateChartDisplay();

   return INIT_SUCCEEDED;
}

//================ TICK =================
void OnTick()
{
   // ポジション存在確認（PositionIDで追跡）
   if(!FindPositionByID(gPositionID))
   {
      Notify("PartialLimitClose: ポジションが外部で決済されました。EA終了します。"
           + " Symbol=" + gSymbol + " Ticket=" + IntegerToString(Ticket));
      DeleteStateFile();
      ExpertRemove();
      return;
   }

   // 現在価格
   double price;
   if(gPosType == POSITION_TYPE_BUY)
      price = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   else
      price = SymbolInfoDouble(gSymbol, SYMBOL_ASK);

   // 全レベル完了チェック用
   bool allDone = true;

   for(int i = 0; i < gLevelCount; i++)
   {
      if(gLevels[i].done)
         continue;

      allDone = false;

      bool triggered = false;

      if(CloseType == CLOSE_TP)
      {
         if(gPosType == POSITION_TYPE_BUY)
            triggered = (price >= gLevels[i].price);
         else
            triggered = (price <= gLevels[i].price);
      }
      else // CLOSE_SL
      {
         if(gPosType == POSITION_TYPE_BUY)
            triggered = (price <= gLevels[i].price);
         else
            triggered = (price >= gLevels[i].price);
      }

      if(triggered)
      {
         if(ExecutePartialClose(i))
         {
            // 決済後にポジションが消えたか確認
            if(!FindPositionByID(gPositionID))
            {
               Notify("PartialLimitClose: 全決済完了。EA終了します。"
                    + " Symbol=" + gSymbol);
               DeleteStateFile();
               ExpertRemove();
               return;
            }
         }
         // 1ティックで1レベルだけ処理（安全のため）
         break;
      }
   }

   // 全レベル処理済みチェック
   if(allDone)
   {
      Notify("PartialLimitClose: 全レベル決済完了。EA終了します。"
           + " Symbol=" + gSymbol);
      DeleteStateFile();
      ExpertRemove();
      return;
   }
}

//================ DEINIT =================
void OnDeinit(const int reason)
{
   RemoveAllLines();
   RemoveDisplay();
   ChartRedraw(0);

   if(gLogHandle != INVALID_HANDLE)
   {
      FileClose(gLogHandle);
      gLogHandle = INVALID_HANDLE;
   }

   Print("PartialLimitClose: 終了 reason=", reason);
}
