//+------------------------------------------------------------------+
//| CloseByCrossEA.mq5                                                |
//| Closes a specific position on SMA13/SMA21 cross                   |
//+------------------------------------------------------------------+
#property copyright "CloseByCrossEA"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>

//--- G1: Inputs
input ENUM_TIMEFRAMES SignalTF          = PERIOD_CURRENT;
input ulong           TargetTicket      = 0;

//--- SMA Display
input bool            ShowSMA           = true;  // Show 13SMA/21SMA on chart

//--- Panel
input bool            ShowPanel         = true;
input int             PanelX            = 10;
input int             PanelY            = 20;

//--- Internal
enum EA_STATE { ST_INIT, ST_WAIT_SYNC, ST_ARMED, ST_CLOSED, ST_ERROR };

EA_STATE  g_state       = ST_INIT;
string    g_error       = "";
string    g_posDir      = "";
int       g_hSMA13      = INVALID_HANDLE;
int       g_hSMA21      = INVALID_HANDLE;
datetime  g_lastBar     = 0;
bool      g_synced      = false;
string    g_objPrefix   = "";
CTrade    g_trade;

const int FONT_SIZE     = 9;
const int LINE_HEIGHT   = 20;
const int MAX_LINES     = 5;

//+------------------------------------------------------------------+
string StateToString(EA_STATE s)
{
   switch(s)
   {
      case ST_INIT:      return "INIT";
      case ST_WAIT_SYNC: return "WAIT_SYNC";
      case ST_ARMED:     return "ARMED";
      case ST_CLOSED:    return "CLOSED";
      case ST_ERROR:     return "ERROR";
   }
   return "UNKNOWN";
}

//+------------------------------------------------------------------+
void SetState(EA_STATE s, string err="")
{
   g_state = s;
   g_error = err;
   Print("[CloseByCrossEA] State -> ", StateToString(s),
         (err != "" ? " | " + err : ""), " | Ticket=", TargetTicket);
   UpdatePanel();
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, SignalTF, 0);
   if(t == 0) return false;
   if(t != g_lastBar)
   {
      g_lastBar = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool GetSMA(double &sma13_prev, double &sma13_curr, double &sma21_prev, double &sma21_curr)
{
   double buf13[2], buf21[2];
   if(CopyBuffer(g_hSMA13, 0, 1, 2, buf13) < 2) return false;
   if(CopyBuffer(g_hSMA21, 0, 1, 2, buf21) < 2) return false;
   sma13_prev = buf13[0]; sma13_curr = buf13[1];
   sma21_prev = buf21[0]; sma21_curr = buf21[1];
   return true;
}

//+------------------------------------------------------------------+
bool PositionExists()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == TargetTicket) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_objPrefix = "CloseByCrossEA_" + (string)TargetTicket + "_";

   if(TargetTicket == 0)
   {
      SetState(ST_ERROR, "TargetTicket=0 is not allowed");
      return INIT_SUCCEEDED;
   }

   if(!PositionExists())
   {
      SetState(ST_ERROR, "Ticket " + (string)TargetTicket + " not found");
      return INIT_SUCCEEDED;
   }

   if(!PositionSelectByTicket(TargetTicket))
   {
      SetState(ST_ERROR, "Cannot select ticket " + (string)TargetTicket);
      return INIT_SUCCEEDED;
   }

   string posSym = PositionGetString(POSITION_SYMBOL);
   if(posSym != _Symbol)
   {
      SetState(ST_ERROR, "Symbol mismatch: pos=" + posSym + " chart=" + _Symbol);
      return INIT_SUCCEEDED;
   }

   long posType = PositionGetInteger(POSITION_TYPE);
   g_posDir = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";

   g_hSMA13 = iMA(_Symbol, SignalTF, 13, 0, MODE_SMA, PRICE_CLOSE);
   g_hSMA21 = iMA(_Symbol, SignalTF, 21, 0, MODE_SMA, PRICE_CLOSE);
   if(g_hSMA13 == INVALID_HANDLE || g_hSMA21 == INVALID_HANDLE)
   {
      SetState(ST_ERROR, "Failed to create MA handles");
      return INIT_SUCCEEDED;
   }

   // Show SMA lines on chart
   if(ShowSMA)
   {
      AddSMAToChart(g_hSMA13);
      AddSMAToChart(g_hSMA21);
   }

   g_lastBar = iTime(_Symbol, SignalTF, 0);
   g_synced  = false;

   SetState(ST_WAIT_SYNC);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hSMA13 != INVALID_HANDLE)
   {
      RemoveSMAFromChart(g_hSMA13);
      IndicatorRelease(g_hSMA13);
   }
   if(g_hSMA21 != INVALID_HANDLE)
   {
      RemoveSMAFromChart(g_hSMA21);
      IndicatorRelease(g_hSMA21);
   }
   DeletePanel();
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(g_state == ST_CLOSED || g_state == ST_ERROR) return;
   if(g_state == ST_INIT) return;

   if(!PositionExists())
   {
      SetState(ST_CLOSED, "Position gone (closed externally)");
      return;
   }

   if(!IsNewBar()) return;

   double s13p, s13c, s21p, s21c;
   if(!GetSMA(s13p, s13c, s21p, s21c))
   {
      Print("[CloseByCrossEA] CopyBuffer failed, retry next bar");
      return;
   }

   // Initial sync: record relationship, don't act
   if(!g_synced)
   {
      g_synced = true;
      SetState(ST_ARMED);
      Print("[CloseByCrossEA] Synced: SMA13=", s13c, " SMA21=", s21c,
            " rel=", (s13c > s21c ? "ABOVE" : "BELOW_OR_EQ"));
      return;
   }

   // Cross detection on confirmed bars
   bool goldenCross = (s13p <= s21p) && (s13c > s21c);
   bool deadCross   = (s13p >= s21p) && (s13c < s21c);

   if(!goldenCross && !deadCross) return;

   Print("[CloseByCrossEA] Cross: ", (goldenCross ? "GOLDEN" : "DEAD"),
         " | SMA13[2]=", s13p, " SMA21[2]=", s21p,
         " | SMA13[1]=", s13c, " SMA21[1]=", s21c);

   // Direction match check
   bool shouldClose = false;
   if(goldenCross && g_posDir == "SELL") shouldClose = true;
   if(deadCross   && g_posDir == "BUY")  shouldClose = true;

   if(!shouldClose)
   {
      Print("[CloseByCrossEA] Cross direction vs position (", g_posDir, ") mismatch. Waiting.");
      return;
   }

   if(!PositionExists())
   {
      SetState(ST_CLOSED, "Position gone before close attempt");
      return;
   }

   Print("[CloseByCrossEA] Closing ticket ", TargetTicket, " (", g_posDir, ")");
   if(g_trade.PositionClose(TargetTicket))
   {
      SetState(ST_CLOSED, "Closed by " + (goldenCross ? "GoldenCross" : "DeadCross"));
   }
   else
   {
      Print("[CloseByCrossEA] Close FAILED: ", g_trade.ResultRetcode(),
            " ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| SMA Chart Display                                                  |
//+------------------------------------------------------------------+
void AddSMAToChart(int handle)
{
   // Add indicator to main chart window (colors adjustable via MT5 indicator list)
   if(!ChartIndicatorAdd(0, 0, handle))
      Print("[CloseByCrossEA] ChartIndicatorAdd failed for handle=", handle);
}

//+------------------------------------------------------------------+
void RemoveSMAFromChart(int handle)
{
   int total = ChartIndicatorsTotal(0, 0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ChartIndicatorName(0, 0, i);
      int h = ChartIndicatorGet(0, 0, name);
      if(h == handle)
      {
         ChartIndicatorDelete(0, 0, name);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Panel                                                             |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!ShowPanel) return;

   string lines[];
   ArrayResize(lines, MAX_LINES);
   int count = 0;

   lines[count++] = "CloseByCrossEA  TF=" + EnumToString(SignalTF);
   lines[count++] = "Ticket: " + (string)TargetTicket + "  " + g_posDir;
   lines[count++] = "State:  " + StateToString(g_state);
   if(g_error != "")
      lines[count++] = g_error;

   for(int i = 0; i < count; i++)
   {
      string name = g_objPrefix + (string)i;
      int yPos = PanelY + (count - 1 - i) * LINE_HEIGHT;

      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FONT_SIZE);
      }

      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PanelX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yPos);
      ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);

      color clr = clrWhite;
      if(g_state == ST_ERROR)     clr = clrRed;
      if(g_state == ST_CLOSED)    clr = clrLime;
      if(g_state == ST_ARMED)     clr = clrDodgerBlue;
      if(g_state == ST_WAIT_SYNC) clr = clrYellow;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   }

   for(int i = count; i < MAX_LINES; i++)
   {
      string name = g_objPrefix + (string)i;
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
void DeletePanel()
{
   for(int i = 0; i < MAX_LINES; i++)
   {
      string name = g_objPrefix + (string)i;
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
   }
   ChartRedraw();
}
//+------------------------------------------------------------------+