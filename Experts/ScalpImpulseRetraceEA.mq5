//+------------------------------------------------------------------+
//| ScalpImpulseRetraceEA.mq5                                        |
//| ScalpImpulseRetraceEA v1.6                                       |
//| EMA Cross Exit + RR Gate廃止 (CHANGE-008)                         |
//| GOLD Confirm OR + TPExt(CHANGE-007)                              |
//| TP Extension(CHANGE-006) + EntryGate市場別化(CHANGE-005)          |
//+------------------------------------------------------------------+
#property copyright "ScalpImpulseRetraceEA"
#property link      ""
#property version   "1.60"
#property strict

//+------------------------------------------------------------------+
//| 定数定義                                                          |
//+------------------------------------------------------------------+
#define EA_NAME           "ScaEA"
#define EA_VERSION        "v1.6"

//+------------------------------------------------------------------+
//| Enum定義（第1章・第3章・第12章）                                    |
//+------------------------------------------------------------------+

// 第1章: MarketMode
enum ENUM_MARKET_MODE
{
   MARKET_MODE_AUTO   = 0, // AUTO
   MARKET_MODE_FX     = 1, // FX
   MARKET_MODE_GOLD   = 2, // GOLD
   MARKET_MODE_CRYPTO = 3  // CRYPTO
};

// 第3章: StateID定義（固定・変更禁止）
enum ENUM_EA_STATE
{
   STATE_IDLE                    = 0, // IDLE
   STATE_IMPULSE_FOUND           = 1, // IMPULSE_FOUND
   STATE_IMPULSE_CONFIRMED       = 2, // IMPULSE_CONFIRMED
   STATE_FIB_ACTIVE              = 3, // FIB_ACTIVE
   STATE_TOUCH_1                 = 4, // TOUCH_1
   STATE_TOUCH_2_WAIT_CONFIRM    = 5, // TOUCH_2_WAIT_CONFIRM
   STATE_ENTRY_PLACED            = 6, // ENTRY_PLACED
   STATE_IN_POSITION             = 7, // IN_POSITION
   STATE_COOLDOWN                = 8  // COOLDOWN
};

// ログレベル
enum ENUM_LOG_LEVEL
{
   LOG_LEVEL_OFF     = 0, // OFF
   LOG_LEVEL_NORMAL  = 1, // NORMAL
   LOG_LEVEL_DEBUG   = 2, // DEBUG
   LOG_LEVEL_ANALYZE = 3  // ANALYZE（ログ出力制御のみ・ロジック関与なし）
};

// ロットモード
enum ENUM_LOT_MODE
{
   LOT_MODE_FIXED        = 0, // FIXED
   LOT_MODE_RISK_PERCENT = 1  // RISK_PERCENT
};

// スプレッドモード
enum ENUM_SPREAD_MODE
{
   SPREAD_MODE_FIXED    = 0, // FIXED
   SPREAD_MODE_ADAPTIVE = 1  // ADAPTIVE
};

// 方向
enum ENUM_DIRECTION
{
   DIR_NONE  = 0, // NONE
   DIR_LONG  = 1, // LONG
   DIR_SHORT = 2  // SHORT
};

// Confirm種別
enum ENUM_CONFIRM_TYPE
{
   CONFIRM_NONE           = 0, // NONE
   CONFIRM_WICK_REJECTION = 1, // WickRejection
   CONFIRM_ENGULFING      = 2, // Engulfing
   CONFIRM_MICRO_BREAK    = 3  // MicroBreak
};

// Entry種別
enum ENUM_ENTRY_TYPE
{
   ENTRY_NONE   = 0, // NONE
   ENTRY_LIMIT  = 1, // LIMIT
   ENTRY_MARKET = 2  // MARKET
};

// ログイベント分類（第13章）
enum ENUM_LOG_EVENT
{
   LOG_STATE     = 0, // LOG_STATE
   LOG_IMPULSE   = 1, // LOG_IMPULSE
   LOG_TOUCH     = 2, // LOG_TOUCH
   LOG_CONFIRM   = 3, // LOG_CONFIRM
   LOG_ENTRY     = 4, // LOG_ENTRY
   LOG_POSITION  = 5, // LOG_POSITION
   LOG_EXIT      = 6, // LOG_EXIT
   LOG_REJECT    = 7  // LOG_REJECT
};

//+------------------------------------------------------------------+
//| Inputs（第12章：グルーピングと初期値）                               |
//+------------------------------------------------------------------+

// 【G1：運用（普段触る）】
input bool              EnableTrading          = true;           // EnableTrading(false=ロジック稼働・Entry禁止)
input ENUM_MARKET_MODE  MarketMode             = MARKET_MODE_AUTO; // MarketMode
input bool              UseLimitEntry          = true;           // UseLimitEntry
input bool              UseMarketFallback      = true;           // UseMarketFallback
input ENUM_LOT_MODE     LotMode                = LOT_MODE_FIXED; // LotMode
input double            FixedLot               = 0.01;           // FixedLot
input ENUM_LOG_LEVEL    LogLevel               = LOG_LEVEL_NORMAL; // LogLevel
input int               RunId                  = 1;              // RunId

// --- Notification (Impulse only) ---
input bool              EnableDialogNotification = true;          // MT5端末ダイアログ通知（Alert）
input bool              EnablePushNotification   = true;          // MT5プッシュ通知（SendNotification）
input bool              EnableMailNotification   = false;         // メール通知（初期OFF）
input bool              EnableSoundNotification  = false;         // サウンド通知（初期OFF）
input string            SoundFileName            = "alert.wav";   // terminal/Sounds 内

// --- Exit: EMAクロス決済 ---
input int               ExitMAFastPeriod       = 13;             // Exit EMA Fast Period
input int               ExitMASlowPeriod       = 21;             // Exit EMA Slow Period
input int               ExitConfirmBars        = 1;              // Exit Confirm Bars (1本確認)

// === TrendFilter / ReversalGuard (順張り方向フィルタ) ===
input bool   TrendFilter_Enable          = true;
input double TrendSlopeMult_FX           = 0.05;   // FX ATR(M15)*mult
input double TrendSlopeMult_GOLD         = 0.07;   // GOLD ATR(M15)*mult
input double TrendATRFloorPts_GOLD       = 80.0;   // GOLD ATR(M15) in points floor
input double TrendSlopeMult_CRYPTO       = 0.04;   // CRYPTO ATR(M15)*mult

input bool   ReversalGuard_Enable        = true;
input bool   ReversalEngulfing_Enable    = true;
input double ReversalBigBodyMult_FX      = 0.9;    // FX ATR(H1)*mult
input double ReversalBigBodyMult_GOLD    = 1.0;    // GOLD ATR(H1)*mult
input double ReversalBigBodyMult_CRYPTO  = 0.9;    // CRYPTO ATR(H1)*mult
input bool   ReversalWickReject_Enable_GOLD = true;
input double ReversalWickRatioMin_GOLD   = 0.60;

input bool              EnableFibVisualization = true;           // EnableFibVisualization

// 【G2：安全弁（事故防止）】
input ENUM_SPREAD_MODE  MaxSpreadMode          = SPREAD_MODE_ADAPTIVE; // MaxSpreadMode
input double            SpreadMult_FX          = 2.0;           // SpreadMult_FX
input double            SpreadMult_GOLD        = 2.5;           // SpreadMult_GOLD
input double            SpreadMult_CRYPTO      = 3.0;           // SpreadMult_CRYPTO
input double            InputMaxSlippagePts    = 0;             // MaxSlippagePts(0=市場別デフォルト)
input double            InputMaxFillDeviationPts = 0;           // MaxFillDeviationPts(0=市場別デフォルト)
input double            InputMaxSpreadPts      = 0;             // MaxSpreadPts(FIXED時)
// --- EntryGate: RR / RangeCost / SL倍率（市場別） ---
input double            MinRR_EntryGate_FX      = 0.7;           // MinRR_EntryGate_FX
input double            MinRR_EntryGate_GOLD    = 0.6;           // MinRR_EntryGate_GOLD
input double            MinRR_EntryGate_CRYPTO  = 0.5;           // MinRR_EntryGate_CRYPTO
input double            MinRangeCostMult_FX     = 2.5;           // MinRangeCostMult_FX
input double            MinRangeCostMult_GOLD   = 2.5;           // MinRangeCostMult_GOLD
input double            MinRangeCostMult_CRYPTO = 2.0;           // MinRangeCostMult_CRYPTO
input double            SLATRMult_FX            = 0.7;           // SLATRMult_FX(SL=ImpulseStart±ATR*this)
input double            SLATRMult_GOLD          = 0.8;           // SLATRMult_GOLD
input double            SLATRMult_CRYPTO        = 0.7;           // SLATRMult_CRYPTO
// --- TP Extension: TP = ImpulseEnd ± Range × this（市場別） ---
input double            TPExtRatio_FX           = 0.382;         // TPExtRatio_FX(0=Fib100そのまま)
input double            TPExtRatio_GOLD         = 0.382;         // TPExtRatio_GOLD(CHANGE-007)
input double            TPExtRatio_CRYPTO       = 0.382;         // TPExtRatio_CRYPTO(CHANGE-006)

// 【G3：戦略（基本触らない）】
input bool              OptionalBand38         = false;          // OptionalBand38
input bool              ConfirmModeOverride    = false;          // ConfirmModeOverride

// 【G4：検証・デバッグ（普段触らない）】
input bool              DumpStateOnChange      = true;           // DumpStateOnChange
input bool              DumpRejectReason       = true;           // DumpRejectReason
input bool              DumpFibValues          = true;           // DumpFibValues
input bool              DumpMarketProfile      = true;           // DumpMarketProfile
input bool              LogStateTransitions    = true;           // LogStateTransitions
input bool              LogImpulseEvents       = true;           // LogImpulseEvents
input bool              LogTouchEvents         = true;           // LogTouchEvents
input bool              LogConfirmEvents       = true;           // LogConfirmEvents
input bool              LogEntryExit           = true;           // LogEntryExit
input bool              LogRejectReason        = true;           // LogRejectReason
input bool              LogMAConfluence        = true;           // LogMAConfluence(ANALYZE時のみ有効)

//+------------------------------------------------------------------+
//| MarketProfile構造体（第1章・第10章）                                 |
//| 市場別パラメータセット（Input変更不可・内部定義のみ）                   |
//+------------------------------------------------------------------+
struct MarketProfileData
{
   ENUM_MARKET_MODE  marketMode;

   // 第4章: Impulse確定パラメータ
   double            impulseATRMult;
   int               impulseMinBars;
   double            smallBodyRatio;
   int               freezeCancelWindowBars;

   // 第5章: 押し帯パラメータ
   // BandWidthPtsはFIB_ACTIVE遷移時に算出（本構造体には格納しない）
   bool              deepBandEnabled;         // GOLD用: 動的判定結果
   bool              cryptoDeepBandAlwaysOn;  // CRYPTO: 常時ON
   bool              optionalBand38;          // 38.2帯有効化

   // 第5章: タッチ/離脱パラメータ
   double            leaveDistanceMult;       // LeaveDistance = BandWidthPts × この値
   int               leaveMinBars;
   int               retouchTimeLimitBars;
   int               resetMinBars;

   // 第7章: Confirm
   int               confirmTimeLimitBars;

   // 第8章: Execution
   double            maxSlippagePts;
   double            maxFillDeviationPts;

   // 第9章: Risk
   int               timeExitBars;

   // 第10章: スプレッド
   double            spreadMult;

   // 第6章: GOLD DeepBand条件パラメータ
   double            volExpansionRatio;
   double            overextensionMult;

   // 第7章: GOLD WickRatioMin
   double            wickRatioMin;

   // CRYPTO: MicroBreak LookbackBars
   int               lookbackMicroBars;

   // === EntryGate: 市場別RR/RangeCost/SL倍率 ===
   double            slATRMult;               // SL = ImpulseStart ± ATR × this
   double            minRR_EntryGate;         // 最低リスクリワード
   double            minRangeCostMult;        // 最低コスト倍率
   double            tpExtensionRatio;        // TP = ImpulseEnd ± Range × this (CHANGE-006)
};

// === ANALYZE追加 === ImpulseSummary構造体
struct ImpulseStats
{
   datetime   StartTime;
   string     TradeUUID;

   double     RangePts;
   double     BandWidthPts;
   double     LeaveDistancePts;
   double     SpreadBasePts;

   int        FreezeCancelCount;

   int        Touch1Count;
   int        LeaveCount;
   int        Touch2Count;
   int        ConfirmCount;

   bool       RiskGatePass;
   bool       Touch2Reached;
   bool       ConfirmReached;
   bool       EntryGatePass;

   double     RR_Actual;
   double     RR_Min;
   double     RangeCostMult_Actual;
   double     RangeCostMult_Min;

   string     FinalState;
   string     RejectStage;

   // === STRUCTURE_BREAK 詳細 ===
   string     StructBreakReason;
   int        StructBreakPriority;
   string     StructBreakRefLevel;
   double     StructBreakRefPrice;
   double     StructBreakAtPrice;
   double     StructBreakDistPts;
   int        StructBreakBarShift;
   string     StructBreakSide;

   // === [ADD] 追加深掘り：At種別 + Wick跨ぎ ===
   string     StructBreakAtKind;      // "CLOSE" / "HIGH" / "LOW"
   int        StructBreakWickCross;   // 0/1
   double     StructBreakWickDistPts; // (WickPrice-RefPrice)/_Point signed

   // === MA Confluence ===
   int        MA_ConfluenceCount;
   string     MA_InBand_List;
   string     MA_InBand_FibPct;
   int        MA_TightHitCount;
   string     MA_TightHit_List;
   string     MA_NearBand_List;
   double     MA_NearestDistance;
   int        MA_DirectionAligned;
   string     MA_Values;
   double     MA_Eval_Price;
   bool       MA_Evaluated;

   // === TrendFilter / ReversalGuard ===
   int        TrendFilterEnable;       // 1/0, 未評価は-1
   string     TrendTF;                // 例: "M15"
   string     TrendMethod;            // 例: "EMA50_SLOPE" / "EMA21x50_SLOPE"
   string     TrendDir;               // "LONG" / "SHORT" / "FLAT"
   double     TrendSlope;
   double     TrendSlopeMin;
   bool       TrendSlopeSet;
   double     TrendATRFloor;
   bool       TrendATRFloorSet;
   int        TrendAligned;           // 1/0, 未評価は-1

   int        ReversalGuardEnable;     // 1/0, 未評価は-1
   string     ReversalTF;             // 例: "H1"
   int        ReversalGuardTriggered; // 1/0, 未評価は-1
   string     ReversalReason;

   void Reset()
   {
      StartTime = TimeCurrent();
      TradeUUID = "";

      RangePts = 0;
      BandWidthPts = 0;
      LeaveDistancePts = 0;
      SpreadBasePts = 0;

      FreezeCancelCount = 0;

      Touch1Count = 0;
      LeaveCount = 0;
      Touch2Count = 0;
      ConfirmCount = 0;

      RiskGatePass = false;
      Touch2Reached = false;
      ConfirmReached = false;
      EntryGatePass = false;

      RR_Actual = 0;
      RR_Min = 0;
      RangeCostMult_Actual = 0;
      RangeCostMult_Min = 0;

      FinalState = "";
      RejectStage = "NONE";

      StructBreakReason = "";
      StructBreakPriority = 0;
      StructBreakRefLevel = "";
      StructBreakRefPrice = 0;
      StructBreakAtPrice = 0;
      StructBreakDistPts = 0;
      StructBreakBarShift = 0;
      StructBreakSide = "";

      StructBreakAtKind = "";
      StructBreakWickCross = 0;
      StructBreakWickDistPts = 0;

      MA_ConfluenceCount = 0;
      MA_InBand_List = "";
      MA_InBand_FibPct = "";
      MA_TightHitCount = 0;
      MA_TightHit_List = "";
      MA_NearBand_List = "";
      MA_NearestDistance = 0;
      MA_DirectionAligned = -1;
      MA_Values = "";
      MA_Eval_Price = 0;
      MA_Evaluated = false;

      TrendFilterEnable = -1;
      TrendTF = "";
      TrendMethod = "";
      TrendDir = "";
      TrendSlope = 0;
      TrendSlopeMin = 0;
      TrendSlopeSet = false;
      TrendATRFloor = 0;
      TrendATRFloorSet = false;
      TrendAligned = -1;

      ReversalGuardEnable = -1;
      ReversalTF = "";
      ReversalGuardTriggered = -1;
      ReversalReason = "";
   }
};

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+

// State
ENUM_EA_STATE     g_currentState       = STATE_IDLE;
ENUM_EA_STATE     g_previousState      = STATE_IDLE;

// MarketProfile
MarketProfileData g_profile;
ENUM_MARKET_MODE  g_resolvedMarketMode = MARKET_MODE_FX;

// === ANALYZE追加 === ImpulseSummary統計グローバル
ImpulseStats      g_stats;

// Impulse
ENUM_DIRECTION    g_impulseDir         = DIR_NONE;
double            g_impulseStart       = 0.0;  // 0 (起点)
double            g_impulseEnd         = 0.0;   // 100 (終点)
double            g_impulseHigh        = 0.0;
double            g_impulseLow         = 0.0;
bool              g_startAdjusted      = false;
int               g_impulseBarIndex    = -1;
datetime          g_impulseBarTime     = 0;

// Freeze
bool              g_frozen             = false;
double            g_frozen100          = 0.0;
int               g_freezeBarIndex     = -1;
datetime          g_freezeBarTime      = 0;
int               g_freezeCancelCount  = 0;

// Fib
double            g_fib382             = 0.0;
double            g_fib500             = 0.0;
double            g_fib618             = 0.0;
double            g_fib786             = 0.0;

// BandWidth
double            g_bandWidthPts       = 0.0;
double            g_effectiveBandWidthPts = 0.0; // Bands/Leaveに実際に使う帯幅（縮小後）


// Band上下限
double            g_primaryBandUpper   = 0.0;
double            g_primaryBandLower   = 0.0;
double            g_deepBandUpper      = 0.0;
double            g_deepBandLower      = 0.0;
double            g_optBand38Upper     = 0.0;
double            g_optBand38Lower     = 0.0;

// Touch
int               g_touchCount_Primary   = 0;
int               g_touchCount_Deep      = 0;
int               g_touchCount_Opt38     = 0;
bool              g_inBand_Primary       = false;
bool              g_inBand_Deep          = false;
bool              g_inBand_Opt38         = false;
bool              g_leaveEstablished_Primary = false;
bool              g_leaveEstablished_Deep    = false;
bool              g_leaveEstablished_Opt38   = false;
int               g_leaveBarCount_Primary    = 0;
int               g_leaveBarCount_Deep       = 0;
int               g_leaveBarCount_Opt38      = 0;

// Touch2成立帯識別
int               g_touch2BandId       = -1; // 0=Primary, 1=Deep, 2=Opt38

// Confirm
ENUM_CONFIRM_TYPE g_confirmType        = CONFIRM_NONE;
int               g_confirmWaitBars    = 0;

// MicroBreak用（フラクタル型）
double            g_microHigh          = 0.0;
double            g_microLow           = 0.0;
bool              g_microHighValid     = false;
bool              g_microLowValid      = false;

// WickRejection状態（GOLD用）
bool              g_wickRejectionSeen  = false;

// Entry / Position
ENUM_ENTRY_TYPE   g_entryType          = ENTRY_NONE;
double            g_entryPrice         = 0.0;
double            g_sl                 = 0.0;
double            g_tp                 = 0.0;
ulong             g_ticket             = 0;
int               g_positionBars       = 0;

// Spread（ADAPTIVE）
double            g_spreadBasePts      = 0.0;
double            g_maxSpreadPts       = 0.0;

// TradeUUID
string            g_tradeUUID          = "";


// Visualization object names (第16章)
string            g_fibObjName         = "";
string            g_bandObjName        = "";
// タイマーカウンタ（Freeze後からのBar数）
int               g_barsAfterFreeze    = 0;

// Touch2成立後のBar数（Confirm待ち）
int               g_barsAfterTouch2    = 0;

// Cooldownカウンタ
int               g_cooldownBars       = 0;
int               g_cooldownDuration   = 3; // 内部定数

// GOLD DeepBand
bool              g_goldDeepBandON     = false;
bool              g_riskGateSoftPass   = false;  // ANALYZE時: RiskGateFail→FIB_ACTIVE継続、Confirm時にブロック

// Logger
int               g_logFileHandle      = INVALID_HANDLE;
string            g_logFileName        = "";

// Bar管理
datetime          g_lastBarTime        = 0;
bool              g_newBar             = false;

// FreezeCancel後の再監視フラグ
bool              g_freezeCancelled    = false;

// 離脱開始バー
datetime          g_leaveStartTime_Primary = 0;
datetime          g_leaveStartTime_Deep    = 0;
datetime          g_leaveStartTime_Opt38   = 0;

// ADAPTIVE Spread計算用
int               g_spreadSampleMinutes = 15; // 内部定数

// === CHANGE-008 === Exit EMAクロス用ハンドル・状態
int               g_exitEMAFastHandle  = INVALID_HANDLE;
int               g_exitEMASlowHandle  = INVALID_HANDLE;
bool              g_exitPending        = false;   // EMAクロス検出後の確認待ち
int               g_exitPendingBars    = 0;       // ExitPending経過バー数

// ATRハンドル
int               g_atrHandleM1        = INVALID_HANDLE;

// === 13.9.6 MA Confluence ===
// MA期間定義（MarketProfile内部・固定）
// FX/GOLD: {5, 13, 21, 100, 200}   CRYPTO: {5, 13, 21, 100, 200, 365}
#define MA_MAX_PERIODS 6
int               g_maPeriods[];                     // 市場別に初期化
int               g_maPeriodsCount     = 0;
int               g_smaHandles[MA_MAX_PERIODS];      // SMAハンドル配列

// Impulse確定後のBar位置
int               g_freezeConfirmedBarShift = 0;

//+------------------------------------------------------------------+
//| MarketProfile初期化（第1章・第10章）                                 |
//+------------------------------------------------------------------+
ENUM_MARKET_MODE ResolveMarketMode()
{
   if(MarketMode != MARKET_MODE_AUTO)
      return MarketMode;

   string sym = Symbol();
   StringToUpper(sym);

   // GOLD判定
   if(StringFind(sym, "XAUUSD") >= 0 || StringFind(sym, "GOLD") >= 0)
      return MARKET_MODE_GOLD;

   // CRYPTO判定
   if(StringFind(sym, "BTCUSD") >= 0 || StringFind(sym, "ETHUSD") >= 0 ||
      StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0 ||
      StringFind(sym, "CRYPTO") >= 0)
      return MARKET_MODE_CRYPTO;

   // 判定不能時はFX扱い（安全側）
   return MARKET_MODE_FX;
}

void InitMarketProfile()
{
   g_resolvedMarketMode = ResolveMarketMode();
   g_profile.marketMode = g_resolvedMarketMode;

   switch(g_resolvedMarketMode)
   {
      case MARKET_MODE_FX:
         g_profile.impulseATRMult         = 1.6;
         g_profile.impulseMinBars          = 1;
         g_profile.smallBodyRatio          = 0.35;
         g_profile.freezeCancelWindowBars  = 2;
         g_profile.deepBandEnabled         = false;
         g_profile.cryptoDeepBandAlwaysOn  = false;
         g_profile.optionalBand38          = OptionalBand38;
         g_profile.leaveDistanceMult       = 1.5;
         g_profile.leaveMinBars            = 1;       // BT の改善提案で 2->1 2026/02/22
         g_profile.retouchTimeLimitBars    = 35;
         g_profile.resetMinBars            = 10;
         g_profile.confirmTimeLimitBars    = 6;
         g_profile.maxSlippagePts          = (InputMaxSlippagePts > 0) ? InputMaxSlippagePts : 2.0;
         g_profile.maxFillDeviationPts     = (InputMaxFillDeviationPts > 0) ? InputMaxFillDeviationPts : 3.0;
         g_profile.timeExitBars            = 10;
         g_profile.spreadMult              = SpreadMult_FX;
         g_profile.volExpansionRatio       = 0.0;  // N/A
         g_profile.overextensionMult       = 0.0;  // N/A
         g_profile.wickRatioMin            = 0.0;  // FXはWickRejection不採用
         g_profile.lookbackMicroBars       = 0;    // FXはフラクタル型
         g_profile.slATRMult               = SLATRMult_FX;
         g_profile.minRR_EntryGate         = MinRR_EntryGate_FX;
         g_profile.minRangeCostMult        = MinRangeCostMult_FX;
         g_profile.tpExtensionRatio        = TPExtRatio_FX;
         break;

      case MARKET_MODE_GOLD:
         g_profile.impulseATRMult         = 1.8;
         g_profile.impulseMinBars          = 1;
         g_profile.smallBodyRatio          = 0.40;
         g_profile.freezeCancelWindowBars  = 3;
         g_profile.deepBandEnabled         = false;   // 動的判定（第6章）
         g_profile.cryptoDeepBandAlwaysOn  = false;
         g_profile.optionalBand38          = false;   // GOLDは38.2帯なし
         g_profile.leaveDistanceMult       = 1.5;     // BT の改善提案で 2.0 -> 1.5 2026/02/22
         g_profile.leaveMinBars            = 1;       // BT の改善提案で 2->1 2026/02/22
         g_profile.retouchTimeLimitBars    = 30;
         g_profile.resetMinBars            = 8;
         g_profile.confirmTimeLimitBars    = 5;
         g_profile.maxSlippagePts          = (InputMaxSlippagePts > 0) ? InputMaxSlippagePts : 5.0;
         g_profile.maxFillDeviationPts     = (InputMaxFillDeviationPts > 0) ? InputMaxFillDeviationPts : 8.0;
         g_profile.timeExitBars            = 8;
         g_profile.spreadMult              = SpreadMult_GOLD;
         g_profile.volExpansionRatio       = 1.5;   // 第6章
         g_profile.overextensionMult       = 2.5;   // 第6章
         g_profile.wickRatioMin            = 0.55;  // 第7章
         g_profile.lookbackMicroBars       = 0;     // GOLDはフラクタル型
         g_profile.slATRMult               = SLATRMult_GOLD;
         g_profile.minRR_EntryGate         = MinRR_EntryGate_GOLD;
         g_profile.minRangeCostMult        = MinRangeCostMult_GOLD;
         g_profile.tpExtensionRatio        = TPExtRatio_GOLD;
         break;

      case MARKET_MODE_CRYPTO:
         g_profile.impulseATRMult         = 2.0;
         g_profile.impulseMinBars          = 1;
         g_profile.smallBodyRatio          = 0.45;
         g_profile.freezeCancelWindowBars  = 1;
         g_profile.deepBandEnabled         = false;
         g_profile.cryptoDeepBandAlwaysOn  = true;  // CRYPTO: 61.8常時ON
         g_profile.optionalBand38          = OptionalBand38;
         g_profile.leaveDistanceMult       = 1.2;
         g_profile.leaveMinBars            = 1;
         g_profile.retouchTimeLimitBars    = 25;
         g_profile.resetMinBars            = 6;
         g_profile.confirmTimeLimitBars    = 4;
         g_profile.maxSlippagePts          = (InputMaxSlippagePts > 0) ? InputMaxSlippagePts : 8.0;
         g_profile.maxFillDeviationPts     = (InputMaxFillDeviationPts > 0) ? InputMaxFillDeviationPts : 12.0;
         g_profile.timeExitBars            = 6;
         g_profile.spreadMult              = SpreadMult_CRYPTO;
         g_profile.volExpansionRatio       = 0.0;   // N/A
         g_profile.overextensionMult       = 0.0;   // N/A
         g_profile.wickRatioMin            = 0.0;   // CRYPTOはWickRejection不採用
         g_profile.lookbackMicroBars       = 3;     // 第7章
         g_profile.slATRMult               = SLATRMult_CRYPTO;
         g_profile.minRR_EntryGate         = MinRR_EntryGate_CRYPTO;
         g_profile.minRangeCostMult        = MinRangeCostMult_CRYPTO;
         g_profile.tpExtensionRatio        = TPExtRatio_CRYPTO;
         break;

      default:
         // 安全側: FX扱い（再帰的にFXを設定）
         g_resolvedMarketMode = MARKET_MODE_FX;
         InitMarketProfile();
         return;
   }
}

//+------------------------------------------------------------------+
//| Logger（第13章）                                                   |
//+------------------------------------------------------------------+
string MarketModeToString(ENUM_MARKET_MODE mode)
{
   switch(mode)
   {
      case MARKET_MODE_FX:     return "FX";
      case MARKET_MODE_GOLD:   return "GOLD";
      case MARKET_MODE_CRYPTO: return "CRYPTO";
      default:                 return "FX";
   }
}

string StateToString(ENUM_EA_STATE state)
{
   switch(state)
   {
      case STATE_IDLE:                   return "IDLE";
      case STATE_IMPULSE_FOUND:          return "IMPULSE_FOUND";
      case STATE_IMPULSE_CONFIRMED:      return "IMPULSE_CONFIRMED";
      case STATE_FIB_ACTIVE:             return "FIB_ACTIVE";
      case STATE_TOUCH_1:                return "TOUCH_1";
      case STATE_TOUCH_2_WAIT_CONFIRM:   return "TOUCH_2_WAIT_CONFIRM";
      case STATE_ENTRY_PLACED:           return "ENTRY_PLACED";
      case STATE_IN_POSITION:            return "IN_POSITION";
      case STATE_COOLDOWN:               return "COOLDOWN";
      default:                           return "UNKNOWN";
   }
}

string DirectionToString(ENUM_DIRECTION dir)
{
   switch(dir)
   {
      case DIR_LONG:  return "LONG";
      case DIR_SHORT: return "SHORT";
      default:        return "NONE";
   }
}

string ConfirmTypeToString(ENUM_CONFIRM_TYPE ct)
{
   switch(ct)
   {
      case CONFIRM_WICK_REJECTION: return "WickRejection";
      case CONFIRM_ENGULFING:      return "Engulfing";
      case CONFIRM_MICRO_BREAK:    return "MicroBreak";
      default:                     return "NONE";
   }
}

string EntryTypeToString(ENUM_ENTRY_TYPE et)
{
   switch(et)
   {
      case ENTRY_LIMIT:  return "LIMIT";
      case ENTRY_MARKET: return "MARKET";
      default:           return "NONE";
   }
}

string LogEventToString(ENUM_LOG_EVENT ev)
{
   switch(ev)
   {
      case LOG_STATE:    return "LOG_STATE";
      case LOG_IMPULSE:  return "LOG_IMPULSE";
      case LOG_TOUCH:    return "LOG_TOUCH";
      case LOG_CONFIRM:  return "LOG_CONFIRM";
      case LOG_ENTRY:    return "LOG_ENTRY";
      case LOG_POSITION: return "LOG_POSITION";
      case LOG_EXIT:     return "LOG_EXIT";
      case LOG_REJECT:   return "LOG_REJECT";
      default:           return "UNKNOWN";
   }
}

// 第13.5章: ログファイル命名規則
// 第13.5章: ログファイル命名規則
string BuildLogFileName()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string runId = StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);

   string fileName = EA_NAME + "_" + runId + "_" + Symbol() + ".tsv";
   return fileName;
}

string BuildSummaryFileName()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string runId = StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);

   string fileName = EA_NAME + "_SUMMARY_" + runId + "_" + Symbol() + ".tsv";
   return fileName;
}

void LoggerInit()
{
   if(LogLevel == LOG_LEVEL_OFF)
      return;

   g_logFileName = BuildLogFileName();

   // 既存ファイルがあれば追記、無ければ新規作成してヘッダ出力
   bool exists = FileIsExist(g_logFileName);

   // FILE_WRITE は先頭上書きになるため、READ|WRITE で開いて末尾へシークする
   // === IMPROVEMENT === FILE_SHARE_READ追加: 外部ツールでの並行読み取りを許可
   g_logFileHandle = FileOpen(g_logFileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ, '\t');

   if(g_logFileHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot open log file: ", g_logFileName);
      return;
   }

   if(exists)
   {
      // 追記モード：末尾へ
      FileSeek(g_logFileHandle, 0, SEEK_END);
   }
   else
   {
      // 第13.1章: TSV固定列ヘッダ
      string header = "Time\tSymbol\tMarketMode\tState\tTradeUUID\tEvent\t"
                      "StartAdjusted\tDeepBandON\tImpulseATR\tStartPrice\tEndPrice\t"
                      "BandLower\tBandUpper\tTouchCount\tFreezeCancelCount\t"
                      "ConfirmType\tEntryType\tEntryPrice\tSL\tTP\t"
                      "SpreadPts\tSlippagePts\tFillDeviationPts\tResult\tRejectReason\tExtra";
      FileWriteString(g_logFileHandle, header + "\n");
      FileFlush(g_logFileHandle);
   }
}

void LoggerDeinit()
{
   if(g_logFileHandle != INVALID_HANDLE)
   {
      FileClose(g_logFileHandle);
      g_logFileHandle = INVALID_HANDLE;
   }
}

// === ANALYZE追加 === ImpulseSummary TSV出力（1 Impulse = 1行）
// === ANALYZE追加 === ImpulseSummary TSV出力（1 Impulse = 1行）
void DumpImpulseSummary()
{
   if(LogLevel != LOG_LEVEL_ANALYZE) return;
   if(g_stats.TradeUUID == "") return;

   string fileName = BuildSummaryFileName();
   bool headerNeeded = !FileIsExist(fileName);

   int handle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_SHARE_WRITE | FILE_SHARE_READ, '\t');
   if(handle == INVALID_HANDLE) return;

   if(headerNeeded)
   {
      FileWrite(handle,
         "Time", "Symbol", "MarketMode", "TradeUUID",
         "RangePts", "BandWidthPts", "LeaveDistancePts", "SpreadBasePts",
         "FreezeCancelCount",
         "Touch1Count", "LeaveCount", "Touch2Count", "ConfirmCount",
         "RiskGatePass", "Touch2Reached", "ConfirmReached", "EntryGatePass",
         "RR_Actual", "RR_Min",
         "RangeCostMult_Actual", "RangeCostMult_Min",
         "FinalState", "RejectStage",

         // --- MA Confluence（列順はDOC-LOG 3.3が正典：この位置固定）
         "MA_ConfluenceCount", "MA_InBand_List", "MA_InBand_FibPct",
         "MA_TightHitCount", "MA_TightHit_List",
         "MA_NearBand_List", "MA_NearestDistance",
         "MA_DirectionAligned", "MA_Values", "MA_Eval_Price",

         // --- STRUCTURE_BREAK（後方互換：末尾追加）
         "StructBreakReason", "StructBreakPriority", "StructBreakRefLevel",
         "StructBreakRefPrice", "StructBreakAtPrice", "StructBreakDistPts", "StructBreakBarShift",
         "StructBreakSide",

         // --- TrendFilter / ReversalGuard（後方互換：末尾追加）
         "TrendFilterEnable", "TrendTF", "TrendMethod", "TrendDir",
         "TrendSlope", "TrendSlopeMin", "TrendATRFloor", "TrendAligned",
         "ReversalGuardEnable", "ReversalTF", "ReversalGuardTriggered", "ReversalReason"
      );
   }

   FileSeek(handle, 0, SEEK_END);

   FileWrite(handle,
      TimeToString(g_stats.StartTime, TIME_DATE|TIME_SECONDS),
      Symbol(),
      MarketModeToString(g_resolvedMarketMode),
      g_stats.TradeUUID,

      g_stats.RangePts,
      g_stats.BandWidthPts,
      g_stats.LeaveDistancePts,
      g_stats.SpreadBasePts,

      g_stats.FreezeCancelCount,

      g_stats.Touch1Count,
      g_stats.LeaveCount,
      g_stats.Touch2Count,
      g_stats.ConfirmCount,

      g_stats.RiskGatePass ? 1 : 0,
      g_stats.Touch2Reached ? 1 : 0,
      g_stats.ConfirmReached ? 1 : 0,
      g_stats.EntryGatePass ? 1 : 0,

      g_stats.RR_Actual,
      g_stats.RR_Min,

      g_stats.RangeCostMult_Actual,
      g_stats.RangeCostMult_Min,

      // ★FIX: FinalState は string のため StateToString() を通さずそのまま出力
      g_stats.FinalState,
      g_stats.RejectStage,

      // --- MA Confluence
      (g_stats.MA_ConfluenceCount >= 0) ? IntegerToString(g_stats.MA_ConfluenceCount) : "",
      g_stats.MA_InBand_List,
      g_stats.MA_InBand_FibPct,
      (g_stats.MA_TightHitCount >= 0) ? IntegerToString(g_stats.MA_TightHitCount) : "",
      g_stats.MA_TightHit_List,
      g_stats.MA_NearBand_List,
      g_stats.MA_NearestDistance,
      (g_stats.MA_DirectionAligned >= 0) ? IntegerToString(g_stats.MA_DirectionAligned) : "",
      g_stats.MA_Values,
      g_stats.MA_Eval_Price,

      // --- STRUCTURE_BREAK
      g_stats.StructBreakReason,
      g_stats.StructBreakPriority,
      g_stats.StructBreakRefLevel,
      g_stats.StructBreakRefPrice,
      g_stats.StructBreakAtPrice,
      g_stats.StructBreakDistPts,
      g_stats.StructBreakBarShift,
      g_stats.StructBreakSide,

      // --- TrendFilter / ReversalGuard
      (g_stats.TrendFilterEnable>=0) ? IntegerToString(g_stats.TrendFilterEnable) : "",
      g_stats.TrendTF,
      g_stats.TrendMethod,
      g_stats.TrendDir,
      g_stats.TrendSlope,
      g_stats.TrendSlopeMin,
      g_stats.TrendATRFloor,
      (g_stats.TrendAligned>=0) ? IntegerToString(g_stats.TrendAligned) : "",
      (g_stats.ReversalGuardEnable>=0) ? IntegerToString(g_stats.ReversalGuardEnable) : "",
      g_stats.ReversalTF,
      (g_stats.ReversalGuardTriggered>=0) ? IntegerToString(g_stats.ReversalGuardTriggered) : "",
      g_stats.ReversalReason
   );

   FileClose(handle);
}

// ログ1行出力
void WriteLog(ENUM_LOG_EVENT event,
              string result = "",
              string rejectReason = "",
              string extra = "",
              double slippagePts = 0.0,
              double fillDeviationPts = 0.0)
{
   if(LogLevel == LOG_LEVEL_OFF)
      return;

   // NORMAL: State変更 + ENTRY/EXITのみ
   if(LogLevel == LOG_LEVEL_NORMAL)
   {
      if(event != LOG_STATE && event != LOG_ENTRY && event != LOG_EXIT &&
         event != LOG_POSITION)
         return;
   }

   // G4個別フラグチェック
   if(event == LOG_STATE && !LogStateTransitions) return;
   if(event == LOG_IMPULSE && !LogImpulseEvents) return;
   if(event == LOG_TOUCH && !LogTouchEvents) return;
   if(event == LOG_CONFIRM && !LogConfirmEvents) return;
   if((event == LOG_ENTRY || event == LOG_EXIT) && !LogEntryExit) return;
   if(event == LOG_REJECT && !LogRejectReason) return;

   if(g_logFileHandle == INVALID_HANDLE)
      return;

   double currentSpread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point();

   // 押し帯情報（アクティブな帯を出力）
   double bandLower = g_primaryBandLower;
   double bandUpper = g_primaryBandUpper;
   if(g_touch2BandId == 1) { bandLower = g_deepBandLower; bandUpper = g_deepBandUpper; }
   if(g_touch2BandId == 2) { bandLower = g_optBand38Lower; bandUpper = g_optBand38Upper; }

   int totalTouches = g_touchCount_Primary;
   if(g_touch2BandId == 1) totalTouches = g_touchCount_Deep;
   if(g_touch2BandId == 2) totalTouches = g_touchCount_Opt38;

   // ATR値
   double atrVal = GetATR_M1(0);

   string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\t" +
                 Symbol() + "\t" +
                 MarketModeToString(g_resolvedMarketMode) + "\t" +
                 StateToString(g_currentState) + "\t" +
                 g_tradeUUID + "\t" +
                 LogEventToString(event) + "\t" +
                 (g_startAdjusted ? "true" : "false") + "\t" +
                 (g_goldDeepBandON ? "true" : "false") + "\t" +
                 DoubleToString(atrVal, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) + "\t" +
                 DoubleToString(g_impulseStart, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) + "\t" +
                 DoubleToString(g_impulseEnd, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) + "\t" +
                 DoubleToString(bandLower, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) + "\t" +
                 DoubleToString(bandUpper, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) + "\t" +
                 IntegerToString(totalTouches) + "\t" +
                 IntegerToString(g_freezeCancelCount) + "\t" +
                 ConfirmTypeToString(g_confirmType) + "\t" +
                 EntryTypeToString(g_entryType) + "\t" +
                 DoubleToString(g_entryPrice, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) + "\t" +
                 DoubleToString(g_sl, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) + "\t" +
                 DoubleToString(g_tp, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) + "\t" +
                 DoubleToString(currentSpread / Point(), 1) + "\t" +
                 DoubleToString(slippagePts, 1) + "\t" +
                 DoubleToString(fillDeviationPts, 1) + "\t" +
                 result + "\t" +
                 rejectReason + "\t" +
                 extra;

   FileWriteString(g_logFileHandle, line + "\n");
   FileFlush(g_logFileHandle);
}

//+------------------------------------------------------------------+
//| TradeUUID生成（第13.7章）                                          |
//+------------------------------------------------------------------+
string GenerateTradeUUID()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string ts = StringFormat("%04d%02d%02d%02d%02d%02d",
                            dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
   string runStr = StringFormat("%02d", RunId);
   return ts + "_" + Symbol() + "_" + runStr;
}

//+------------------------------------------------------------------+
//| ATR取得ヘルパー                                                    |
//+------------------------------------------------------------------+
double GetATR_M1(int shift)
{
   if(g_atrHandleM1 == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandleM1, 0, shift, 1, buf) <= 0)
      return 0.0;
   return buf[0];
}

// 長期ATR（第6章: VolExpansionRatio用）
double GetATR_M1_Long(int shift, int period = 50)
{
   int handle = iATR(Symbol(), PERIOD_M1, period);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0)
   {
      IndicatorRelease(handle);
      return 0.0;
   }
   double val = buf[0];
   IndicatorRelease(handle);
   return val;
}

//+------------------------------------------------------------------+
//| 新しいバー検出                                                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(Symbol(), PERIOD_M1, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| State遷移関数                                                     |
//+------------------------------------------------------------------+
void ChangeState(ENUM_EA_STATE newState, string reason = "")
{
   g_previousState = g_currentState;
   g_currentState  = newState;

   if(newState == STATE_IDLE)
      DeleteCurrentFibVisualization();

   if(newState == STATE_IDLE && LogLevel == LOG_LEVEL_ANALYZE)
   {
      if(g_stats.FinalState == "")
         g_stats.FinalState = reason;

      if(g_stats.RejectStage == "NONE")
      {
         if(!g_stats.Touch2Reached)
            g_stats.RejectStage = "NO_TOUCH2";
         else if(!g_stats.ConfirmReached)
            g_stats.RejectStage = "NO_CONFIRM";
      }

      DumpImpulseSummary();
   }

   string extra = "reason=" + reason;
   WriteLog(LOG_STATE, "", "", extra);

   if(DumpStateOnChange)
      Print("[STATE] ", StateToString(g_previousState), " -> ", StateToString(g_currentState), " | ", reason);
}


//+------------------------------------------------------------------+
//| Spread取得・計算（第12.3章）                                        |
//+------------------------------------------------------------------+
double GetCurrentSpreadPts()
{
   return (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
}

void UpdateAdaptiveSpread()
{
   // ADAPTIVE算出更新: 新規IMPULSE_FOUND発生時のみ
   if(MaxSpreadMode == SPREAD_MODE_FIXED)
   {
      g_maxSpreadPts = InputMaxSpreadPts;
      return;
   }

   // SpreadBasePts = 直近N分のスプレッド中央値（簡易実装: 現在スプレッドを使用）
   // 仕様: N は内部定数（例：15分）
   double spreadNow = GetCurrentSpreadPts();
   g_spreadBasePts = spreadNow; // 簡易版：Impulse発生時点のスプレッド
   g_maxSpreadPts  = g_spreadBasePts * g_profile.spreadMult;
}

bool IsSpreadOK()
{
   double spread = GetCurrentSpreadPts();
   return (spread <= g_maxSpreadPts);
}

//+------------------------------------------------------------------+
//| ImpulseDetector（第2章・第4章）                                     |
//+------------------------------------------------------------------+

// 第4章: Impulse認定（単足基準）
bool DetectImpulse()
{
   // M1確定足[1]で判定
   double open1  = iOpen(Symbol(), PERIOD_M1, 1);
   double close1 = iClose(Symbol(), PERIOD_M1, 1);
   double high1  = iHigh(Symbol(), PERIOD_M1, 1);
   double low1   = iLow(Symbol(), PERIOD_M1, 1);

   double body = MathAbs(close1 - open1);
   double atr  = GetATR_M1(1);

   if(atr <= 0) return false;

   double impulseThreshold = atr * g_profile.impulseATRMult;

   if(body < impulseThreshold)
      return false;

   // 方向判定
   if(close1 > open1)
      g_impulseDir = DIR_LONG;
   else if(close1 < open1)
      g_impulseDir = DIR_SHORT;
   else
      return false;

   // Impulse足の高安を記録
   g_impulseHigh = high1;
   g_impulseLow  = low1;
   g_impulseBarIndex = 1; // 確定足[1]

   // 起点算出（第2章 ImpulseDetector: 起点算出ロジック）
   CalculateImpulseStart();

   // 終点（100）はImpulse方向の先端
   if(g_impulseDir == DIR_LONG)
      g_impulseEnd = high1;
   else
      g_impulseEnd = low1;

   return true;
}

// 第2章: 起点算出ロジック（条件付き補正）
void CalculateImpulseStart()
{
   int impBar = g_impulseBarIndex; // 確定足のshift

   double open_imp  = iOpen(Symbol(), PERIOD_M1, impBar);
   double close_imp = iClose(Symbol(), PERIOD_M1, impBar);
   double high_imp  = iHigh(Symbol(), PERIOD_M1, impBar);
   double low_imp   = iLow(Symbol(), PERIOD_M1, impBar);

   // 前足（Impulse足の1本前）
   int prevBar = impBar + 1;
   double open_prev  = iOpen(Symbol(), PERIOD_M1, prevBar);
   double close_prev = iClose(Symbol(), PERIOD_M1, prevBar);
   double high_prev  = iHigh(Symbol(), PERIOD_M1, prevBar);
   double low_prev   = iLow(Symbol(), PERIOD_M1, prevBar);

   double prevBody = MathAbs(close_prev - open_prev);
   double atr      = GetATR_M1(impBar);

   g_startAdjusted = false;

   // ■ 条件（両方成立時のみ補正）
   bool cond1 = false; // 前足がImpulse方向と逆色
   bool cond2 = false; // 前足実体 <= ATR(M1) × SmallBodyRatio

   if(g_impulseDir == DIR_LONG)
      cond1 = (close_prev < open_prev); // 前足陰線 = Long方向と逆色
   else
      cond1 = (close_prev > open_prev); // 前足陽線 = Short方向と逆色

   if(atr > 0)
      cond2 = (prevBody <= atr * g_profile.smallBodyRatio);

   if(cond1 && cond2)
   {
      // ■ 条件成立時
      g_startAdjusted = true;
      if(g_impulseDir == DIR_LONG)
         g_impulseStart = MathMin(low_imp, low_prev);
      else
         g_impulseStart = MathMax(high_imp, high_prev);
   }
   else
   {
      // ■ 条件不成立時
      if(g_impulseDir == DIR_LONG)
         g_impulseStart = low_imp;
      else
         g_impulseStart = high_imp;
   }
}

//+------------------------------------------------------------------+
//| Freeze判定（第4章: 市場別）                                        |
//+------------------------------------------------------------------+
bool CheckFreeze()
{
   // 確定足[1]で判定
   double open1  = iOpen(Symbol(), PERIOD_M1, 1);
   double close1 = iClose(Symbol(), PERIOD_M1, 1);
   double high1  = iHigh(Symbol(), PERIOD_M1, 1);
   double low1   = iLow(Symbol(), PERIOD_M1, 1);

   // 100追従更新（Freeze前）
   if(!g_frozen)
   {
      if(g_impulseDir == DIR_LONG)
      {
         if(high1 > g_impulseEnd)
         {
            g_impulseEnd  = high1;
            g_impulseHigh = high1;
         }
      }
      else
      {
         if(low1 < g_impulseEnd)
         {
            g_impulseEnd = low1;
            g_impulseLow = low1;
         }
      }
   }

   // Freeze判定
   switch(g_resolvedMarketMode)
   {
      case MARKET_MODE_FX:
         return CheckFreeze_FX(open1, close1, high1, low1);

      case MARKET_MODE_GOLD:
         return CheckFreeze_GOLD(open1, close1, high1, low1);

      case MARKET_MODE_CRYPTO:
         return CheckFreeze_CRYPTO(open1, close1, high1, low1);

      default:
         return CheckFreeze_FX(open1, close1, high1, low1);
   }
}

// ■ FX（Level2固定）
bool CheckFreeze_FX(double open1, double close1, double high1, double low1)
{
   bool updateStopped = false;
   bool oppositeColor = false;

   // 1) 更新停止
   if(g_impulseDir == DIR_LONG)
      updateStopped = (high1 <= g_impulseHigh);
   else
      updateStopped = (low1 >= g_impulseLow);

   // 2) 反対色足
   if(g_impulseDir == DIR_LONG)
      oppositeColor = (close1 < open1);
   else
      oppositeColor = (close1 > open1);

   return (updateStopped && oppositeColor);
}

// ■ GOLD（Level3固定）
bool CheckFreeze_GOLD(double open1, double close1, double high1, double low1)
{
   bool updateStopped = false;
   bool oppositeColor = false;
   bool internalReturn = false;

   // 1) 更新停止
   if(g_impulseDir == DIR_LONG)
      updateStopped = (high1 <= g_impulseHigh);
   else
      updateStopped = (low1 >= g_impulseLow);

   // 2) 反対色足
   if(g_impulseDir == DIR_LONG)
      oppositeColor = (close1 < open1);
   else
      oppositeColor = (close1 > open1);

   // 3) 内部回帰（ATR(M1)×0.15以上戻す）
   double atr = GetATR_M1(1);
   double returnThreshold = atr * 0.15;

   if(g_impulseDir == DIR_LONG)
   {
      double returnAmount = g_impulseHigh - close1;
      internalReturn = (returnAmount >= returnThreshold);
   }
   else
   {
      double returnAmount = close1 - g_impulseLow;
      internalReturn = (returnAmount >= returnThreshold);
   }

   return (updateStopped && oppositeColor && internalReturn);
}

// ■ CRYPTO（Level2）
bool CheckFreeze_CRYPTO(double open1, double close1, double high1, double low1)
{
   // FXと同一条件（Level2）
   return CheckFreeze_FX(open1, close1, high1, low1);
}

//+------------------------------------------------------------------+
//| Freeze取消判定（第4章: 市場別）                                     |
//+------------------------------------------------------------------+
bool CheckFreezeCancel()
{
   if(!g_frozen) return false;

   // CancelWindowBars内のみチェック
   int barsSinceFreeze = g_barsAfterFreeze;
   if(barsSinceFreeze > g_profile.freezeCancelWindowBars)
      return false;

   double high0 = iHigh(Symbol(), PERIOD_M1, 0); // 現在足（Tick単位）
   double low0  = iLow(Symbol(), PERIOD_M1, 0);

   switch(g_resolvedMarketMode)
   {
      case MARKET_MODE_FX:
         return CheckFreezeCancel_FX(high0, low0);
      case MARKET_MODE_GOLD:
         return CheckFreezeCancel_GOLD(high0, low0);
      case MARKET_MODE_CRYPTO:
         return CheckFreezeCancel_CRYPTO(high0, low0);
      default:
         return CheckFreezeCancel_FX(high0, low0);
   }
}

// FX: Frozen100を1tick超えて更新
bool CheckFreezeCancel_FX(double high0, double low0)
{
   double tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(g_impulseDir == DIR_LONG)
      return (high0 > g_frozen100 + tick);
   else
      return (low0 < g_frozen100 - tick);
}

// GOLD: Frozen100をSpread×2以上突破
bool CheckFreezeCancel_GOLD(double high0, double low0)
{
   double spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double threshold = spread * 2.0;

   if(g_impulseDir == DIR_LONG)
      return (high0 > g_frozen100 + threshold);
   else
      return (low0 < g_frozen100 - threshold);
}

// CRYPTO: Frozen100を0.1%以上更新
bool CheckFreezeCancel_CRYPTO(double high0, double low0)
{
   double threshold = g_frozen100 * 0.001;

   if(g_impulseDir == DIR_LONG)
      return (high0 > g_frozen100 + threshold);
   else
      return (low0 < g_frozen100 - threshold);
}

//+------------------------------------------------------------------+
//| GOLD DeepBand判定（第6章）                                         |
//+------------------------------------------------------------------+
bool EvaluateGoldDeepBand()
{
   if(g_resolvedMarketMode != MARKET_MODE_GOLD)
      return false;

   // 【必須ゲート】（いずれか1つ）
   bool G1 = false;
   bool G2 = false;

   // G1: ATR(M1) / ATR(M1,長期) >= VolExpansionRatio
   double atrShort = GetATR_M1(0);
   double atrLong  = GetATR_M1_Long(0, 50);
   if(atrLong > 0)
      G1 = (atrShort / atrLong >= g_profile.volExpansionRatio);

   // G2: Impulseが"過伸長": ImpulseRangePts >= ATR(M1) * OverextensionMult
   double impulseRange = MathAbs(g_impulseEnd - g_impulseStart);
   if(atrShort > 0)
      G2 = (impulseRange >= atrShort * g_profile.overextensionMult);

   bool gate = (G1 || G2);

   // 【追加条件】（いずれか1つ）
   bool C1 = false;
   bool C2 = false;
   bool C3 = false;

   // C1: セッションが荒い時間帯（NY前半など）
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   // NY前半: サーバー時間で13-17時（概算。MT5サーバーがGMT+2/+3想定）
   C1 = (hour >= 13 && hour <= 17);

   // C2: 直近でスイープ痕跡（直近高安を一瞬抜いて戻す）
   // 簡易判定: 直近5本で高値を抜いてから戻った or 安値を抜いてから戻った
   C2 = DetectSweep(5);

   // C3: スプレッドが通常域（拡大していない）
   double spread = GetCurrentSpreadPts();
   C3 = (spread <= g_maxSpreadPts);

   bool additional = (C1 || C2 || C3);

   return (gate && additional);
}

bool DetectSweep(int lookback)
{
   // 直近lookback本での高安スイープ痕跡
   // 高値が前の高値を上回ったが、次足以降で戻った場合
   for(int i = 1; i < lookback; i++)
   {
      double h_i = iHigh(Symbol(), PERIOD_M1, i);
      double h_prev = iHigh(Symbol(), PERIOD_M1, i + 1);
      double c_i = iClose(Symbol(), PERIOD_M1, i);

      // 高値スイープ: 高値が前足高値を超えたが終値が前足高値以下
      if(h_i > h_prev && c_i <= h_prev)
         return true;

      double l_i = iLow(Symbol(), PERIOD_M1, i);
      double l_prev = iLow(Symbol(), PERIOD_M1, i + 1);

      // 安値スイープ: 安値が前足安値を下回ったが終値が前足安値以上
      if(l_i < l_prev && c_i >= l_prev)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| FibEngine（第3章・第5章）                                          |
//+------------------------------------------------------------------+
void CalculateFibLevels()
{
   // Impulse起点(0) / 終点(100)からFib算出
   double range = g_impulseEnd - g_impulseStart;

   if(g_impulseDir == DIR_LONG)
   {
      // Long: 0=Low, 100=High, 押しは上から下
      g_fib382 = g_impulseEnd - range * 0.382;
      g_fib500 = g_impulseEnd - range * 0.500;
      g_fib618 = g_impulseEnd - range * 0.618;
      g_fib786 = g_impulseEnd - range * 0.786;
   }
   else
   {
      // Short: 0=High, 100=Low, 戻しは下から上
      g_fib382 = g_impulseEnd + range * 0.382; // range is negative for short
      g_fib500 = g_impulseEnd + range * 0.500;
      g_fib618 = g_impulseEnd + range * 0.618;
      g_fib786 = g_impulseEnd + range * 0.786;
   }

   // 正規化 (Shortの場合 range = impulseEnd - impulseStart < 0)
   // 再計算: |range|使用
   double absRange = MathAbs(g_impulseEnd - g_impulseStart);

   if(g_impulseDir == DIR_LONG)
   {
      g_fib382 = g_impulseEnd - absRange * 0.382;
      g_fib500 = g_impulseEnd - absRange * 0.500;
      g_fib618 = g_impulseEnd - absRange * 0.618;
      g_fib786 = g_impulseEnd - absRange * 0.786;
   }
   else
   {
      // Short: impulseStart=High(0), impulseEnd=Low(100)
      // 戻し（押し）はLow(100)からHigh(0)方向
      g_fib382 = g_impulseEnd + absRange * 0.382;
      g_fib500 = g_impulseEnd + absRange * 0.500;
      g_fib618 = g_impulseEnd + absRange * 0.618;
      g_fib786 = g_impulseEnd + absRange * 0.786;
   }
}

// BandWidthPts確定（第10章: 唯一の定義）
void CalculateBandWidth()
{
   switch(g_resolvedMarketMode)
   {
      case MARKET_MODE_FX:
      {
         // FX = Spread×2相当（第5.4章）
         double spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
         g_bandWidthPts = spread * 2.0;
         break;
      }
      case MARKET_MODE_GOLD:
      {
         // GOLD = ATR(M1)×0.05
         double atr = GetATR_M1(0);
         g_bandWidthPts = atr * 0.05;
         break;
      }
      case MARKET_MODE_CRYPTO:
      {
         // CRYPTO = ATR(M1)×0.08
         double atr = GetATR_M1(0);
         g_bandWidthPts = atr * 0.08;
         break;
      }
   }
}


// BandがFib(0-100)の範囲を超えないようにクランプ（行って来い等でBandWidthが過大でも暴れないように）
void ClampBandToFibRange(double &upper, double &lower)
{
   double minP = MathMin(g_impulseStart, g_impulseEnd);
   double maxP = MathMax(g_impulseStart, g_impulseEnd);

   if(upper > maxP) upper = maxP;
   if(upper < minP) upper = minP;
   if(lower > maxP) lower = maxP;
   if(lower < minP) lower = minP;

   // 念のため上下逆転を補正
   if(upper < lower)
   {
      double tmp = upper;
      upper = lower;
      lower = tmp;
   }
}

// 押し帯の上下限を計算（第5.2章）
void CalculateBands()
{
   // 帯幅は「50±BandWidthPts」だが、Impulse(0-100)レンジが小さい局面では 0-100 をはみ出し得る。
   // そこで *クランプで潰す* のではなく、中心(50)を保ったまま帯幅を Impulseレンジ内に収まる最大値へ縮小する。
   // これにより「帯の意味」が壊れにくく、過小Impulseの時は実質的に帯が極端に細くなる（=エントリー期待が薄い）状態になる。
   double bw = g_bandWidthPts;

   double point  = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double rangeP = MathAbs(g_impulseEnd - g_impulseStart);          // 0-100価格レンジ
   double maxBw  = (rangeP * 0.5) - (point * 0.5);                  // 50±bw がレンジ内に収まる最大bw（微小マージン付き）

   if(maxBw < 0.0)
      maxBw = 0.0;

   if(bw > maxBw)
      bw = maxBw;


   g_effectiveBandWidthPts = bw;
   // PrimaryBand
   switch(g_resolvedMarketMode)
   {
      case MARKET_MODE_FX:
      {
         // PrimaryBand: 50（±BandWidthPts）
         g_primaryBandUpper = g_fib500 + bw;
         g_primaryBandLower = g_fib500 - bw;

         // OptionalBand: 38.2（±BandWidthPts）
         if(g_profile.optionalBand38)
         {
            g_optBand38Upper = g_fib382 + bw;
            g_optBand38Lower = g_fib382 - bw;
         }
         // 61.8は押し帯に含めない
         g_deepBandUpper = 0;
         g_deepBandLower = 0;
         break;
      }
      case MARKET_MODE_GOLD:
      {
         // PrimaryBand: 50（±BandWidthPts）
         g_primaryBandUpper = g_fib500 + bw;
         g_primaryBandLower = g_fib500 - bw;

         // DeepBand: 50〜61.8（ON条件成立時のみ）
         if(g_goldDeepBandON)
         {
            if(g_impulseDir == DIR_LONG)
            {
               g_deepBandUpper = g_fib500 + bw;
               g_deepBandLower = g_fib618 - bw;
            }
            else
            {
               g_deepBandLower = g_fib500 - bw;
               g_deepBandUpper = g_fib618 + bw;
            }
         }
         else
         {
            g_deepBandUpper = 0;
            g_deepBandLower = 0;
         }
         g_optBand38Upper = 0;
         g_optBand38Lower = 0;
         break;
      }
      case MARKET_MODE_CRYPTO:
      {
         // PrimaryBand: 50〜61.8（帯として常時運用）
         if(g_impulseDir == DIR_LONG)
         {
            g_primaryBandUpper = g_fib500 + bw;
            g_primaryBandLower = g_fib618 - bw;
         }
         else
         {
            g_primaryBandLower = g_fib500 - bw;
            g_primaryBandUpper = g_fib618 + bw;
         }

         // OptionalBand: 38.2
         if(g_profile.optionalBand38)
         {
            g_optBand38Upper = g_fib382 + bw;
            g_optBand38Lower = g_fib382 - bw;
         }
         g_deepBandUpper = 0;
         g_deepBandLower = 0;
         break;
      }
   }

   // Fib(0-100) 範囲外にBandが飛び出さないようクランプ
   if(g_primaryBandUpper != 0 || g_primaryBandLower != 0)
      ClampBandToFibRange(g_primaryBandUpper, g_primaryBandLower);
   if(g_optBand38Upper != 0 || g_optBand38Lower != 0)
      ClampBandToFibRange(g_optBand38Upper, g_optBand38Lower);
   if(g_deepBandUpper != 0 || g_deepBandLower != 0)
      ClampBandToFibRange(g_deepBandUpper, g_deepBandLower);
}


//+------------------------------------------------------------------+
//| Fib Visualization（第16章）                                       |
//+------------------------------------------------------------------+
string BuildFibObjName(const string trade_uuid)
{
   return "EA_FIB_" + trade_uuid;
}

string BuildBandObjName(const string trade_uuid)
{
   return "EA_BAND_" + trade_uuid;
}


// 旧UUIDのFib/Bandオブジェクトを掃除して「直近作成分だけ」オブジェクトリストに残す
void PurgeOldFibObjectsExcept(const string keepFibName, const string keepBandName)
{
   // 逆順で削除（インデックスずれ防止）
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(name == "") continue;

      bool isFib  = (StringFind(name, "EA_FIB_")  == 0);
      bool isBand = (StringFind(name, "EA_BAND_") == 0);
      if(!isFib && !isBand) continue;

      if(name == keepFibName || name == keepBandName) continue;

      ObjectDelete(0, name);
   }
}

color GetBandColorForMarket(ENUM_MARKET_MODE mode)
{
   // 仕様書推奨: FX=Blue系, GOLD=Gold系, CRYPTO=Purple系（透明度は60%推奨）
   // 実装: ARGBで半透明
   switch(mode)
   {
      case MARKET_MODE_GOLD:   return (color)ColorToARGB(clrGold, 150);
      case MARKET_MODE_CRYPTO: return (color)ColorToARGB(clrPurple, 150);
      case MARKET_MODE_FX:
      default:                 return (color)ColorToARGB(clrDodgerBlue, 150);
   }
}

void CreateFibVisualization()
{
   if(!EnableFibVisualization) return;
   if(g_tradeUUID == "") return;

   string fibName = BuildFibObjName(g_tradeUUID);
   string bandName = BuildBandObjName(g_tradeUUID);

   g_fibObjName = fibName;
   g_bandObjName = bandName;

   // --- 追加：新規作成前に、現在のUUID以外のゴミを掃除する ---
   PurgeOldFibObjectsExcept(fibName, bandName); 

   if(ObjectFind(0, fibName) < 0)
   {
      datetime t1 = iTime(Symbol(), PERIOD_M1, g_impulseBarIndex);
      datetime t2 = g_freezeBarTime;
      if(t1 <= 0) t1 = iTime(Symbol(), PERIOD_M1, 0);
      if(t1 <= 0) t1 = TimeCurrent();
      if(t2 <= 0) t2 = iTime(Symbol(), PERIOD_M1, 0);
      if(t2 <= 0) t2 = TimeCurrent();
      if(t2 < t1) t2 = t1 + PeriodSeconds(PERIOD_M1);

      if(!ObjectCreate(0, fibName, OBJ_FIBO, 0, t1, g_impulseStart, t2, g_impulseEnd))
      {
         Print("[VIS] Fib create failed: ", GetLastError());
      }
      else
      {
         ObjectSetInteger(0, fibName, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, fibName, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, fibName, OBJPROP_HIDDEN, false);

         ObjectSetInteger(0, fibName, OBJPROP_LEVELS, 6);

         ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 0, 0.0);
         ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 1, 0.382);
         ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 2, 0.5);
         ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 3, 0.618);
         ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 4, 0.786);
         ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 5, 1.0);

         ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 0, "0");
         ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 1, "38.2");
         ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 2, "50");
         ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 3, "61.8");
         ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 4, "78.6");
         ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 5, "100");
      }
   }

   if(ObjectFind(0, bandName) < 0)
   {
      double bandUpper = 0.0;
      double bandLower = 0.0;

      if(g_resolvedMarketMode == MARKET_MODE_GOLD && g_goldDeepBandON && g_deepBandUpper > 0 && g_deepBandLower > 0)
      {
         bandUpper = g_deepBandUpper;
         bandLower = g_deepBandLower;
      }
      else if(g_primaryBandUpper > 0 && g_primaryBandLower > 0)
      {
         bandUpper = g_primaryBandUpper;
         bandLower = g_primaryBandLower;
      }

      if(bandUpper > 0 && bandLower > 0)
      {
         datetime t1 = g_freezeBarTime;
         if(t1 <= 0) t1 = iTime(Symbol(), PERIOD_M1, 0);
         if(t1 <= 0) t1 = TimeCurrent();

         int futureBars = g_profile.retouchTimeLimitBars + 50;
         if(futureBars < 200) futureBars = 200;
         if(futureBars > 2000) futureBars = 2000;
         datetime t2 = t1 + (datetime)(PeriodSeconds(PERIOD_M1) * futureBars);
         if(t2 <= t1) t2 = t1 + 60 * 60 * 4;

         if(!ObjectCreate(0, bandName, OBJ_RECTANGLE, 0, t1, bandUpper, t2, bandLower))
         {
            Print("[VIS] Band create failed: ", GetLastError());
         }
         else
         {
            ObjectSetInteger(0, bandName, OBJPROP_BACK, true);
            ObjectSetInteger(0, bandName, OBJPROP_FILL, true);
            ObjectSetInteger(0, bandName, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, bandName, OBJPROP_HIDDEN, false);
            ObjectSetInteger(0, bandName, OBJPROP_COLOR, GetBandColorForMarket(g_resolvedMarketMode));
         }
      }
   }
}

void DeleteFibVisualizationForUUID(const string trade_uuid)
{
   if(trade_uuid == "") return;

   string fibName  = BuildFibObjName(trade_uuid);
   string bandName = BuildBandObjName(trade_uuid);

   if(ObjectFind(0, fibName) >= 0)  ObjectDelete(0, fibName);
   if(ObjectFind(0, bandName) >= 0) ObjectDelete(0, bandName);

   if(g_tradeUUID == trade_uuid)
   {
      g_fibObjName  = "";
      g_bandObjName = "";
   }
}

void DeleteCurrentFibVisualization()
{
   DeleteFibVisualizationForUUID(g_tradeUUID);
}

//+------------------------------------------------------------------+
//| Touch / Leave / ReTouch判定（第5.3章）                             |
//+------------------------------------------------------------------+

// 帯への侵入判定
bool CheckBandEntry(double bandUpper, double bandLower)
{
   double low0  = iLow(Symbol(), PERIOD_M1, 1);  // 確定足
   double high0 = iHigh(Symbol(), PERIOD_M1, 1);

   if(g_impulseDir == DIR_LONG)
   {
      // Long: Low が BandUpper以下に到達
      return (low0 <= bandUpper);
   }
   else
   {
      // Short: High が BandLower以上に到達
      return (high0 >= bandLower);
   }
}

// 離脱判定（第5.3.3章）
bool CheckLeave(double bandUpper, double bandLower, double leaveDistance,
                int &leaveBarCount, bool &leaveEstablished)
{
   if(leaveEstablished) return true;

   double close1 = iClose(Symbol(), PERIOD_M1, 1);

   bool outsideFar = false;
   if(g_impulseDir == DIR_LONG)
   {
      // Close が BandUpper + LeaveDistance を上回る
      outsideFar = (close1 > bandUpper + leaveDistance);
   }
   else
   {
      // Close が BandLower - LeaveDistance を下回る
      outsideFar = (close1 < bandLower - leaveDistance);
   }

   if(outsideFar)
   {
      leaveBarCount++;
      if(leaveBarCount >= g_profile.leaveMinBars)
      {
         leaveEstablished = true;
         return true;
      }
   }
   else
   {
      leaveBarCount = 0; // リセット（連続確定が必要）
   }

   return false;
}

// タッチ処理（全帯を処理）
// 戻り値: Touch2が成立した帯ID (0=Primary, 1=Deep, 2=Opt38, -1=なし)
int ProcessTouches()
{
   double leaveDistPrimary = g_effectiveBandWidthPts * g_profile.leaveDistanceMult;
   double leaveDistDeep    = g_effectiveBandWidthPts * g_profile.leaveDistanceMult;
   double leaveDistOpt38   = g_effectiveBandWidthPts * g_profile.leaveDistanceMult;

   // --- Primary Band ---
   if(g_primaryBandUpper > 0 && g_primaryBandLower > 0)
   {
      int result = ProcessSingleBandTouch(
         g_primaryBandUpper, g_primaryBandLower, leaveDistPrimary,
         g_touchCount_Primary, g_inBand_Primary,
         g_leaveEstablished_Primary, g_leaveBarCount_Primary, 0);
      if(result >= 0) return result;
   }

   // --- Deep Band (GOLD) ---
   if(g_deepBandUpper > 0 && g_deepBandLower > 0 && g_goldDeepBandON)
   {
      int result = ProcessSingleBandTouch(
         g_deepBandUpper, g_deepBandLower, leaveDistDeep,
         g_touchCount_Deep, g_inBand_Deep,
         g_leaveEstablished_Deep, g_leaveBarCount_Deep, 1);
      if(result >= 0) return result;
   }

   // --- Optional 38.2 Band ---
   if(g_optBand38Upper > 0 && g_optBand38Lower > 0 && g_profile.optionalBand38)
   {
      int result = ProcessSingleBandTouch(
         g_optBand38Upper, g_optBand38Lower, leaveDistOpt38,
         g_touchCount_Opt38, g_inBand_Opt38,
         g_leaveEstablished_Opt38, g_leaveBarCount_Opt38, 2);
      if(result >= 0) return result;
   }

   return -1;
}

// 個別帯のタッチ処理
int ProcessSingleBandTouch(double bandUpper, double bandLower, double leaveDist,
                           int &touchCount, bool &inBand,
                           bool &leaveEstablished, int &leaveBarCount,
                           int bandId)
{
   bool isInBand = CheckBandEntry(bandUpper, bandLower);

   if(isInBand && !inBand)
   {
      // 新規侵入
      inBand = true;

      if(touchCount == 0)
      {
         // 1回目タッチ
         touchCount = 1;
         RecordTouch1(bandId);
         return -1; // Touch1ではまだ遷移しない（FIB_ACTIVE -> TOUCH_1は呼び出し側で処理）
      }
      else if(touchCount == 1 && leaveEstablished)
      {
         // 2回目タッチ（離脱成立後の再侵入）
         touchCount = 2;
         RecordTouch2(bandId);
         return bandId; // Touch2成立
      }
   }
   else if(!isInBand && inBand)
   {
      // 帯から出た
      inBand = false;
   }

   // 離脱判定（帯外にいる間）
   if(!inBand && touchCount >= 1 && !leaveEstablished)
   {
      bool prevLeaveEstablished = leaveEstablished;
      CheckLeave(bandUpper, bandLower, leaveDist, leaveBarCount, leaveEstablished);
      if(!prevLeaveEstablished && leaveEstablished)
      {
         RecordLeave(bandId);
      }
   }

   return -1;
}

//+------------------------------------------------------------------+
//| 構造無効判定（第9.4章）: 詳細版                              |
//+------------------------------------------------------------------+
bool CheckStructureInvalid_Detail(
   string &reason, int &priority,
   string &refLevel, double &refPrice,
   double &atPrice, double &distPts,
   int &barShift
)
{
   barShift = 1;

   double close1 = iClose(Symbol(), PERIOD_M1, barShift);

   // ■ 共通: 起点(START)割れ/超え（close判定）
   if(g_impulseDir == DIR_LONG)
   {
      if(close1 < g_impulseStart)
      {
         reason   = "BRK_OUT_START";
         priority = 1;
         refLevel = "START";
         refPrice = g_impulseStart;

         atPrice  = close1;
         distPts  = (atPrice - refPrice) / _Point;
         return true;
      }
   }
   else
   {
      if(close1 > g_impulseStart)
      {
         reason   = "BRK_OUT_START";
         priority = 1;
         refLevel = "START";
         refPrice = g_impulseStart;

         atPrice  = close1;
         distPts  = (atPrice - refPrice) / _Point;
         return true;
      }
   }

   // ■ 市場別（close判定）
   switch(g_resolvedMarketMode)
   {
      case MARKET_MODE_FX:
      {
         // FX: 61.8終値突破
         if(g_impulseDir == DIR_LONG)
         {
            if(close1 < g_fib618)
            {
               reason="BRK_CLOSE_61_8"; priority=2;
               refLevel="61.8"; refPrice=g_fib618;
               atPrice=close1; distPts=(atPrice-refPrice)/_Point;
               return true;
            }
         }
         else
         {
            if(close1 > g_fib618)
            {
               reason="BRK_CLOSE_61_8"; priority=2;
               refLevel="61.8"; refPrice=g_fib618;
               atPrice=close1; distPts=(atPrice-refPrice)/_Point;
               return true;
            }
         }
         break;
      }

      case MARKET_MODE_GOLD:
      {
         if(g_goldDeepBandON)
         {
            // GOLD deep: 78.6終値割れ/超え
            if(g_impulseDir == DIR_LONG)
            {
               if(close1 < g_fib786)
               {
                  reason="BRK_CLOSE_78_6"; priority=2;
                  refLevel="78.6"; refPrice=g_fib786;
                  atPrice=close1; distPts=(atPrice-refPrice)/_Point;
                  return true;
               }
            }
            else
            {
               if(close1 > g_fib786)
               {
                  reason="BRK_CLOSE_78_6"; priority=2;
                  refLevel="78.6"; refPrice=g_fib786;
                  atPrice=close1; distPts=(atPrice-refPrice)/_Point;
                  return true;
               }
            }
         }
         else
         {
            // deep OFF: 61.8終値突破
            if(g_impulseDir == DIR_LONG)
            {
               if(close1 < g_fib618)
               {
                  reason="BRK_CLOSE_61_8"; priority=2;
                  refLevel="61.8"; refPrice=g_fib618;
                  atPrice=close1; distPts=(atPrice-refPrice)/_Point;
                  return true;
               }
            }
            else
            {
               if(close1 > g_fib618)
               {
                  reason="BRK_CLOSE_61_8"; priority=2;
                  refLevel="61.8"; refPrice=g_fib618;
                  atPrice=close1; distPts=(atPrice-refPrice)/_Point;
                  return true;
               }
            }
         }
         break;
      }

      case MARKET_MODE_CRYPTO:
      {
         // CRYPTO: 78.6終値割れ/超え
         if(g_impulseDir == DIR_LONG)
         {
            if(close1 < g_fib786)
            {
               reason="BRK_CLOSE_78_6"; priority=2;
               refLevel="78.6"; refPrice=g_fib786;
               atPrice=close1; distPts=(atPrice-refPrice)/_Point;
               return true;
            }
         }
         else
         {
            if(close1 > g_fib786)
            {
               reason="BRK_CLOSE_78_6"; priority=2;
               refLevel="78.6"; refPrice=g_fib786;
               atPrice=close1; distPts=(atPrice-refPrice)/_Point;
               return true;
            }
         }
         break;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Entry待ちの「リスク/コスト過大」失効ゲート（追加）                    |
//| 目的: 0-100幅 / 帯幅 / Leave距離 / スプレッド等の摩擦を総合して、     |
//|       「取りに行ける値幅が無い」状態ならFIB_ACTIVE開始前に失効させる |
//+------------------------------------------------------------------+
bool CheckNoEntryRiskGate()
{
   // RiskGate = 「待つ価値が無いImpulse」をFIB_ACTIVE開始前に落とす事前スクリーニング。
   // CHANGE-002で MinRR_EntryGate / MinRangeCostMult は EntryGate 側へ移動したため、
   // ここでは「帯がレンジを支配する」系（主にFXのSpread由来帯幅）だけを扱う。

   double point  = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double rangeP = MathAbs(g_impulseEnd - g_impulseStart);     // 0–100 価格レンジ
   if(rangeP <= point * 2.0)
      return true; // そもそもレンジが無さすぎる（安全側）

   // 帯高さ = 2×BandWidth（上下±）
   double bandHeight = g_effectiveBandWidthPts * 2.0;
   double ratio = bandHeight / rangeP; // BandDominanceRatio

   // FXはBandWidthがSpread由来なので、過大化すると「帯=ほぼ全域」になりやすい。
   // この状態は“待つ場所”ではないため失効させる（固定閾値）。
   if(g_resolvedMarketMode == MARKET_MODE_FX)
   {
      if(ratio >= 0.85)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Confirm判定（第7章）                                               |
//+------------------------------------------------------------------+

// A) WickRejection（ヒゲ拒否）
bool CheckWickRejection()
{
   double open1  = iOpen(Symbol(), PERIOD_M1, 1);
   double close1 = iClose(Symbol(), PERIOD_M1, 1);
   double high1  = iHigh(Symbol(), PERIOD_M1, 1);
   double low1   = iLow(Symbol(), PERIOD_M1, 1);

   double fullRange = high1 - low1;
   if(fullRange <= 0) return false;

   // アクティブ帯の取得
   double bandUpper, bandLower;
   GetActiveBand(bandUpper, bandLower);

   if(g_impulseDir == DIR_LONG)
   {
      // 下ヒゲ比率 >= WickRatioMin
      double lowerWick = MathMin(open1, close1) - low1;
      double wickRatio = lowerWick / fullRange;
      if(wickRatio < g_profile.wickRatioMin) return false;

      // 終値が押し帯の内側〜上側で確定
      if(close1 >= bandLower) return true;
   }
   else
   {
      // 上ヒゲ比率 >= WickRatioMin
      double upperWick = high1 - MathMax(open1, close1);
      double wickRatio = upperWick / fullRange;
      if(wickRatio < g_profile.wickRatioMin) return false;

      // 終値が押し帯の内側〜下側で確定
      if(close1 <= bandUpper) return true;
   }

   return false;
}

// B) Engulfing（包み足）
bool CheckEngulfing()
{
   double open1  = iOpen(Symbol(), PERIOD_M1, 1);
   double close1 = iClose(Symbol(), PERIOD_M1, 1);
   double open2  = iOpen(Symbol(), PERIOD_M1, 2);
   double close2 = iClose(Symbol(), PERIOD_M1, 2);

   double body1_upper = MathMax(open1, close1);
   double body1_lower = MathMin(open1, close1);
   double body2_upper = MathMax(open2, close2);
   double body2_lower = MathMin(open2, close2);

   if(g_impulseDir == DIR_LONG)
   {
      // Bullish Engulfing: 現足実体が前足実体を包む & 陽線
      if(close1 > open1 &&
         body1_upper > body2_upper &&
         body1_lower < body2_lower)
         return true;
   }
   else
   {
      // Bearish Engulfing: 現足実体が前足実体を包む & 陰線
      if(close1 < open1 &&
         body1_upper > body2_upper &&
         body1_lower < body2_lower)
         return true;
   }

   return false;
}

// C) MicroBreak（ミクロ構造ブレイク）
bool CheckMicroBreak()
{
   double close1 = iClose(Symbol(), PERIOD_M1, 1);

   switch(g_resolvedMarketMode)
   {
      case MARKET_MODE_FX:
      case MARKET_MODE_GOLD:
      {
         // フラクタル固定型（左右2本）
         UpdateFractalMicroLevels();

         if(g_impulseDir == DIR_LONG)
         {
            if(g_microHighValid && close1 > g_microHigh)
               return true;
         }
         else
         {
            if(g_microLowValid && close1 < g_microLow)
               return true;
         }
         break;
      }
      case MARKET_MODE_CRYPTO:
      {
         // スイング抽出型（LookbackMicroBars=3固定）
         double microHigh = 0, microLow = 999999;
         for(int i = 1; i <= g_profile.lookbackMicroBars; i++)
         {
            double h = iHigh(Symbol(), PERIOD_M1, i);
            double l = iLow(Symbol(), PERIOD_M1, i);
            if(h > microHigh) microHigh = h;
            if(l < microLow)  microLow = l;
         }

         if(g_impulseDir == DIR_LONG)
         {
            if(close1 > microHigh) return true;
         }
         else
         {
            if(close1 < microLow) return true;
         }
         break;
      }
   }

   return false;
}

// フラクタルMicroHigh/MicroLow更新（FX/GOLD用）
void UpdateFractalMicroLevels()
{
   // 左右2本型フラクタル: 確定足[3]を中心に[4],[5]と[2],[1]を比較
   // i=3 が最直近の確定候補（[1],[2]が右側、[4],[5]が左側）

   // MicroHighチェック（shift=3を中心）
   for(int i = 3; i < 20; i++)
   {
      double h_i   = iHigh(Symbol(), PERIOD_M1, i);
      double h_im1 = iHigh(Symbol(), PERIOD_M1, i - 1);
      double h_im2 = iHigh(Symbol(), PERIOD_M1, i - 2);
      double h_ip1 = iHigh(Symbol(), PERIOD_M1, i + 1);
      double h_ip2 = iHigh(Symbol(), PERIOD_M1, i + 2);

      if(h_i > h_im1 && h_i > h_im2 && h_i > h_ip1 && h_i > h_ip2)
      {
         g_microHigh = h_i;
         g_microHighValid = true;
         break;
      }
   }

   // MicroLowチェック
   for(int i = 3; i < 20; i++)
   {
      double l_i   = iLow(Symbol(), PERIOD_M1, i);
      double l_im1 = iLow(Symbol(), PERIOD_M1, i - 1);
      double l_im2 = iLow(Symbol(), PERIOD_M1, i - 2);
      double l_ip1 = iLow(Symbol(), PERIOD_M1, i + 1);
      double l_ip2 = iLow(Symbol(), PERIOD_M1, i + 2);

      if(l_i < l_im1 && l_i < l_im2 && l_i < l_ip1 && l_i < l_ip2)
      {
         g_microLow = l_i;
         g_microLowValid = true;
         break;
      }
   }
}

// 市場別Confirm判定（第7.3章）
ENUM_CONFIRM_TYPE EvaluateConfirm()
{
   switch(g_resolvedMarketMode)
   {
      case MARKET_MODE_FX:
      {
         // FX: Engulfing OR MicroBreak（Engulfing優先）
         if(CheckEngulfing())    return CONFIRM_ENGULFING;
         if(CheckMicroBreak())   return CONFIRM_MICRO_BREAK;
         break;
      }
      case MARKET_MODE_GOLD:
      {
         // GOLD: WickRejection OR MicroBreak (CHANGE-007: AND→OR)
         // WickRejection を引き続きトラッキング（ログ用）
         if(CheckWickRejection())
         {
            g_wickRejectionSeen = true;
            return CONFIRM_WICK_REJECTION;   // WickRejectのみで許可
         }
         if(CheckMicroBreak())
         {
            return CONFIRM_MICRO_BREAK;      // MicroBreakのみで許可
         }
         break;
      }
      case MARKET_MODE_CRYPTO:
      {
         // CRYPTO: MicroBreakのみ
         if(CheckMicroBreak()) return CONFIRM_MICRO_BREAK;
         break;
      }
   }

   return CONFIRM_NONE;
}

// アクティブ帯の取得
void GetActiveBand(double &bandUpper, double &bandLower)
{
   switch(g_touch2BandId)
   {
      case 0:
         bandUpper = g_primaryBandUpper;
         bandLower = g_primaryBandLower;
         break;
      case 1:
         bandUpper = g_deepBandUpper;
         bandLower = g_deepBandLower;
         break;
      case 2:
         bandUpper = g_optBand38Upper;
         bandLower = g_optBand38Lower;
         break;
      default:
         bandUpper = g_primaryBandUpper;
         bandLower = g_primaryBandLower;
         break;
   }
}

//+------------------------------------------------------------------+
//| Execution（第8章）                                                 |
//+------------------------------------------------------------------+
bool ExecuteEntry()
{
   // ガードチェック
   if(!IsSpreadOK())
   {
      WriteLog(LOG_REJECT, "", "SpreadExceeded", "SpreadPts=" + DoubleToString(GetCurrentSpreadPts(), 1));
      return false;
   }

   double price = 0;
   ENUM_ORDER_TYPE orderType;

   if(UseLimitEntry)
   {
      // 指値エントリー
      g_entryType = ENTRY_LIMIT;
      if(g_impulseDir == DIR_LONG)
      {
         price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         orderType = ORDER_TYPE_BUY;
      }
      else
      {
         price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         orderType = ORDER_TYPE_SELL;
      }
   }
   else if(UseMarketFallback)
   {
      // 成行エントリー
      g_entryType = ENTRY_MARKET;
      if(g_impulseDir == DIR_LONG)
      {
         price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         orderType = ORDER_TYPE_BUY;
      }
      else
      {
         price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         orderType = ORDER_TYPE_SELL;
      }
   }
   else
   {
      WriteLog(LOG_REJECT, "", "NoEntryMethodEnabled");
      return false;
   }

   // SL/TP計算（第9章）
   CalculateSLTP(price);

   // 注文実行
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = Symbol();
   request.volume    = FixedLot;
   request.type      = orderType;
   request.price     = price;
   request.sl        = g_sl;
   request.tp        = g_tp;
   request.deviation = (ulong)(g_profile.maxSlippagePts / Point());
   request.magic     = 20260101; // Magic Number固定
   request.comment   = EA_NAME + " " + g_tradeUUID;

   if(!OrderSend(request, result))
   {
      WriteLog(LOG_REJECT, "", "OrderSendFailed",
               "error=" + IntegerToString(result.retcode));
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
   {
      WriteLog(LOG_REJECT, "", "OrderRetcodeFailed",
               "retcode=" + IntegerToString(result.retcode));
      return false;
   }

   g_ticket = result.order;
   g_entryPrice = result.price;

   // 約定後乖離チェック（第8.2章）
   double fillDeviation = MathAbs(result.price - price) / Point();
   if(fillDeviation > g_profile.maxFillDeviationPts)
   {
      // 即撤退（保険）
      ClosePosition("FillDeviationExceeded");
      WriteLog(LOG_REJECT, "", "FillDeviationExceeded",
               "deviation=" + DoubleToString(fillDeviation, 1));
      return false;
   }

   WriteLog(LOG_ENTRY, "", "", "ticket=" + IntegerToString(g_ticket),
            0, fillDeviation);

   return true;
}

//+------------------------------------------------------------------+
//| TP算出（CHANGE-006: TP Extension対応）                              |
//| TP = ImpulseEnd ± ImpulseRange × tpExtensionRatio                |
//| tpExtensionRatio=0 のとき従来どおり ImpulseEnd そのまま              |
//+------------------------------------------------------------------+
double GetExtendedTP()
{
   double impulseRange = MathAbs(g_impulseEnd - g_impulseStart);
   double ext = g_profile.tpExtensionRatio;
   if(g_impulseDir == DIR_LONG)
      return g_impulseEnd + impulseRange * ext;
   else
      return g_impulseEnd - impulseRange * ext;
}

//+------------------------------------------------------------------+
//| SL/TP計算（第9章）CHANGE-008: TP=0（EMAクロス決済のためサーバーTP不使用）|
//+------------------------------------------------------------------+
void CalculateSLTP(double entryPrice)
{
   // SL: 構造（Impulse起点/直近スイング外）で決める
   // 第9.1章: 市場別パラメータ → g_profile.slATRMult
   double atr = GetATR_M1(0);
   double mult = g_profile.slATRMult;

   if(g_impulseDir == DIR_LONG)
   {
      g_sl = g_impulseStart - atr * mult;
   }
   else
   {
      g_sl = g_impulseStart + atr * mult;
   }

   // CHANGE-008: サーバーTP=0（EMAクロスで決済するため指値TPを使用しない）
   g_tp = 0;
}

// === CHANGE-002 === EntryGate用: SL/TPのプレビュー算出（グローバル非書き換え）
void PreviewSLTP(double entryPrice, double &outSL, double &outTP)
{
   double atr = GetATR_M1(0);
   double mult = g_profile.slATRMult;
   outTP = GetExtendedTP();   // CHANGE-006
   outSL = (g_impulseDir == DIR_LONG) ? (g_impulseStart - atr * mult) : (g_impulseStart + atr * mult);
}

//+------------------------------------------------------------------+
//| ポジション管理（第9章）                                             |
//+------------------------------------------------------------------+
void ClosePosition(string reason, string extraInfo = "")
{
   if(!PositionSelectByTicket(g_ticket))
      return;

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = Symbol();
   request.volume   = PositionGetDouble(POSITION_VOLUME);
   request.deviation = (ulong)(g_profile.maxSlippagePts / Point());

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      request.type  = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   }
   else
   {
      request.type  = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   }

   if(OrderSend(request, result))
   {
      string logExtra = "closePrice=" + DoubleToString(result.price,
               (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
      if(extraInfo != "")
         logExtra += ";" + extraInfo;
      WriteLog(LOG_EXIT, reason, "", logExtra);
   }
}

// === CHANGE-008 === Exit EMA値取得ヘルパー
double GetExitEMA(int handle, int shift)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0)
      return 0.0;
   return buf[0];
}

// ポジション管理：CHANGE-008 EMAクロス決済（確定足＋1本確認）
void ManagePosition()
{
   if(!PositionSelectByTicket(g_ticket))
   {
      // ポジションなし → 決済済み
      g_stats.FinalState = "PositionClosed";
      ChangeState(STATE_COOLDOWN, "PositionClosed");
      return;
   }

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

   // =====================================================================
   // Exit優先順位1: 構造破綻（Fib0 = ImpulseStart 終値割れ/超え：確定足）
   // =====================================================================
   {
      double close1 = iClose(Symbol(), PERIOD_M1, 1);  // 直近確定足
      bool structBreak = false;

      if(g_impulseDir == DIR_LONG && close1 < g_impulseStart)
         structBreak = true;
      else if(g_impulseDir == DIR_SHORT && close1 > g_impulseStart)
         structBreak = true;

      if(structBreak)
      {
         g_stats.FinalState = "StructBreak_Fib0";
         ClosePosition("StructBreak_Fib0",
                  "ExitReason=STRUCT_BREAK;Fib0=" + DoubleToString(g_impulseStart, digits) +
                  ";Close1=" + DoubleToString(close1, digits));
         ChangeState(STATE_COOLDOWN, "StructBreak_Fib0");
         return;
      }
   }

   // =====================================================================
   // Exit優先順位2: 時間撤退（Entry後N本以内に伸びない）
   // =====================================================================
   g_positionBars++;
   if(g_positionBars >= g_profile.timeExitBars)
   {
      double posProfit = PositionGetDouble(POSITION_PROFIT);
      if(posProfit <= 0)
      {
         g_stats.FinalState = "TimeExit";
         ClosePosition("TimeExit",
                  "ExitReason=TIMEOUT;Bars=" + IntegerToString(g_positionBars));
         ChangeState(STATE_COOLDOWN, "TimeExit");
         return;
      }
   }

   // =====================================================================
   // 建値移動: RR >= 1.0で建値（維持）
   // =====================================================================
   {
      double risk = MathAbs(openPrice - g_sl);
      double reward = 0;
      double currentPrice;
      if(g_impulseDir == DIR_LONG)
      {
         currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         reward = currentPrice - openPrice;
      }
      else
      {
         currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         reward = openPrice - currentPrice;
      }

      if(risk > 0 && (reward / risk) >= 1.0)
      {
         if(g_impulseDir == DIR_LONG && currentSL < openPrice)
            ModifySL(openPrice);
         else if(g_impulseDir == DIR_SHORT && (currentSL > openPrice || currentSL == 0))
            ModifySL(openPrice);
      }
   }

   // =====================================================================
   // Exit優先順位3: EMAクロス（確定足＋1本確認）
   // =====================================================================
   {
      // EMA値取得（確定足: shift=1, 1本前: shift=2）
      double emaFast1 = GetExitEMA(g_exitEMAFastHandle, 1);  // 直近確定足
      double emaSlow1 = GetExitEMA(g_exitEMASlowHandle, 1);
      double emaFast2 = GetExitEMA(g_exitEMAFastHandle, 2);  // 1つ前の確定足
      double emaSlow2 = GetExitEMA(g_exitEMASlowHandle, 2);

      if(emaFast1 == 0.0 || emaSlow1 == 0.0 || emaFast2 == 0.0 || emaSlow2 == 0.0)
      {
         // EMA取得失敗時はスキップ
         return;
      }

      if(g_exitPending)
      {
         // --- 確認フェーズ: クロス状態が維持されているか ---
         g_exitPendingBars++;

         bool crossMaintained = false;
         string crossDir = "";

         if(g_impulseDir == DIR_LONG)
         {
            // Long保有中: デッドクロス維持 = EMA_Fast < EMA_Slow
            if(emaFast1 < emaSlow1)
            {
               crossMaintained = true;
               crossDir = "DEAD";
            }
         }
         else
         {
            // Short保有中: ゴールデンクロス維持 = EMA_Fast > EMA_Slow
            if(emaFast1 > emaSlow1)
            {
               crossMaintained = true;
               crossDir = "GOLDEN";
            }
         }

         if(crossMaintained && g_exitPendingBars >= ExitConfirmBars)
         {
            // クロス確認完了 → 成行決済
            g_stats.FinalState = "EMACross_Exit";
            ClosePosition("EMACross",
                     "ExitReason=EMA_CROSS;CrossDir=" + crossDir +
                     ";EMA" + IntegerToString(ExitMAFastPeriod) + "=" + DoubleToString(emaFast1, digits) +
                     ";EMA" + IntegerToString(ExitMASlowPeriod) + "=" + DoubleToString(emaSlow1, digits) +
                     ";ConfirmBars=" + IntegerToString(g_exitPendingBars));
            ChangeState(STATE_COOLDOWN, "EMACross_Exit");
            return;
         }
         else if(!crossMaintained)
         {
            // クロス未維持 → ExitPending解除
            g_exitPending     = false;
            g_exitPendingBars = 0;
         }
      }
      else
      {
         // --- 検出フェーズ: 新たなクロス発生をチェック ---
         bool crossDetected = false;

         if(g_impulseDir == DIR_LONG)
         {
            // Long保有中: デッドクロス = EMA_Fast がEMA_Slow を下抜け
            if(emaFast2 >= emaSlow2 && emaFast1 < emaSlow1)
               crossDetected = true;
         }
         else
         {
            // Short保有中: ゴールデンクロス = EMA_Fast がEMA_Slow を上抜け
            if(emaFast2 <= emaSlow2 && emaFast1 > emaSlow1)
               crossDetected = true;
         }

         if(crossDetected)
         {
            g_exitPending     = true;
            g_exitPendingBars = 0;
         }
      }
   }
}

void ModifySL(double newSL)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action   = TRADE_ACTION_SLTP;
   request.symbol   = Symbol();
   request.position = g_ticket;
   request.sl       = newSL;
   request.tp       = g_tp;

   if(!OrderSend(request, result))
   {
      Print("[WARN] ModifySL failed: retcode=", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| Notification（第14章）                                             |
//+------------------------------------------------------------------+
void SendImpulseNotification()
{
   string sideStr = DirectionToString(g_impulseDir);

   if(!EnableDialogNotification && !EnablePushNotification && !EnableMailNotification && !EnableSoundNotification)
      return;

   string subject = "[" + EA_NAME + "] " + Symbol() + " " + sideStr + " IMPULSE";
   string body =
      "EA      : " + EA_NAME + " " + EA_VERSION + "\n" +
      "Symbol  : " + Symbol() + "\n" +
      "Event   : IMPULSE\n" +
      "Side    : " + sideStr + "\n" +
      "State   : IMPULSE_FOUND\n" +
      "Time    : " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);

   // 1) ダイアログ通知（MT5端末）
   if(EnableDialogNotification)
      Alert(body);

   // 2) プッシュ通知（MT5）
   if(EnablePushNotification)
      SendNotification(subject + "\n" + body);

   // 3) メール通知
   if(EnableMailNotification)
      SendMail(subject, body);

   // 4) サウンド通知
   if(EnableSoundNotification)
   {
      if(!PlaySound(SoundFileName))
         Print("[NOTIFY] Sound file not found: ", SoundFileName);
   }
}

//+------------------------------------------------------------------+
//| 全State変数リセット                                                |
//+------------------------------------------------------------------+
void ResetAllState()
{
   g_impulseDir       = DIR_NONE;
   g_impulseStart     = 0;
   g_impulseEnd       = 0;
   g_impulseHigh      = 0;
   g_impulseLow       = 0;
   g_startAdjusted    = false;
   g_impulseBarIndex  = -1;
   g_impulseBarTime   = 0;

   g_frozen           = false;
   g_frozen100        = 0;
   g_freezeBarIndex   = -1;
   g_freezeBarTime    = 0;
   g_freezeCancelCount = 0;
   g_freezeCancelled  = false;

   g_fib382 = 0; g_fib500 = 0; g_fib618 = 0; g_fib786 = 0;
   g_bandWidthPts = 0;
   g_effectiveBandWidthPts = 0;  // === IMPROVEMENT === 帯幅残存による次サイクルへの影響を防止

   g_primaryBandUpper = 0; g_primaryBandLower = 0;
   g_deepBandUpper = 0;    g_deepBandLower = 0;
   g_optBand38Upper = 0;   g_optBand38Lower = 0;

   g_touchCount_Primary = 0; g_touchCount_Deep = 0; g_touchCount_Opt38 = 0;
   g_inBand_Primary = false; g_inBand_Deep = false; g_inBand_Opt38 = false;
   g_leaveEstablished_Primary = false; g_leaveEstablished_Deep = false; g_leaveEstablished_Opt38 = false;
   g_leaveBarCount_Primary = 0; g_leaveBarCount_Deep = 0; g_leaveBarCount_Opt38 = 0;
   g_touch2BandId = -1;

   g_confirmType      = CONFIRM_NONE;
   g_confirmWaitBars  = 0;
   g_wickRejectionSeen = false;

   g_microHigh = 0; g_microLow = 0;
   g_microHighValid = false; g_microLowValid = false;

   g_entryType  = ENTRY_NONE;
   g_entryPrice = 0;
   g_sl = 0; g_tp = 0;
   g_ticket = 0;
   g_positionBars = 0;

   g_barsAfterFreeze = 0;
   g_barsAfterTouch2 = 0;

   g_goldDeepBandON   = false;
   g_riskGateSoftPass = false;

   // === CHANGE-008 === ExitPendingリセット
   g_exitPending     = false;
   g_exitPendingBars = 0;
   
   g_tradeUUID = "";
}

//+------------------------------------------------------------------+
//| MA Confluence 解析（第13.9.6章）                                    |
//| ロジックへの影響なし。ImpulseSummary用の純粋なログ機能                  |
//+------------------------------------------------------------------+

// MA期間の初期化（MarketProfile内部定義・SMA固定）
void InitMAPeriods()
{
   switch(g_resolvedMarketMode)
   {
      case MARKET_MODE_FX:
      case MARKET_MODE_GOLD:
         g_maPeriodsCount = 5;
         ArrayResize(g_maPeriods, 5);
         g_maPeriods[0] = 5;
         g_maPeriods[1] = 13;
         g_maPeriods[2] = 21;
         g_maPeriods[3] = 100;
         g_maPeriods[4] = 200;
         break;

      case MARKET_MODE_CRYPTO:
         g_maPeriodsCount = 6;
         ArrayResize(g_maPeriods, 6);
         g_maPeriods[0] = 5;
         g_maPeriods[1] = 13;
         g_maPeriods[2] = 21;
         g_maPeriods[3] = 100;
         g_maPeriods[4] = 200;
         g_maPeriods[5] = 365;
         break;

      default:
         g_maPeriodsCount = 5;
         ArrayResize(g_maPeriods, 5);
         g_maPeriods[0] = 5;
         g_maPeriods[1] = 13;
         g_maPeriods[2] = 21;
         g_maPeriods[3] = 100;
         g_maPeriods[4] = 200;
         break;
   }
}

// SMA値取得ヘルパー（shift=1: 確定足）
double GetSMAValue(int handleIndex, int shift)
{
   if(handleIndex < 0 || handleIndex >= g_maPeriodsCount) return 0.0;
   if(g_smaHandles[handleIndex] == INVALID_HANDLE) return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_smaHandles[handleIndex], 0, shift, 1, buf) <= 0)
      return 0.0;
   return buf[0];
}

// MA Confluence評価（IMPULSE_CONFIRMED時点で1回だけ呼ぶ）
void EvaluateMAConfluence()
{
   // 条件チェック: ANALYZE + LogMAConfluence のみ
   if(LogLevel != LOG_LEVEL_ANALYZE || !LogMAConfluence)
      return;

   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

   // 評価価格: IMPULSE_CONFIRMED成立足のClose（shift=1）
   double evalPrice = iClose(Symbol(), PERIOD_M1, 1);
   g_stats.MA_Eval_Price = evalPrice;
   g_stats.MA_Evaluated = true;

   // アクティブ帯のUpper/Lower取得
   double bandUpper = g_primaryBandUpper;
   double bandLower = g_primaryBandLower;
   // GOLD DeepBandがONの場合はDeepBandを使用
   if(g_resolvedMarketMode == MARKET_MODE_GOLD && g_goldDeepBandON &&
      g_deepBandUpper > 0 && g_deepBandLower > 0)
   {
      bandUpper = g_deepBandUpper;
      bandLower = g_deepBandLower;
   }

   double bandCenter = (bandUpper + bandLower) / 2.0;
   double bandWidth  = g_effectiveBandWidthPts;
   double nearRange  = bandWidth * 1.0; // 近傍定義: 帯外BandWidthPts×1.0以内

   // TightPts定義（市場別・固定: SpreadBasePts × 2.0）
   // g_spreadBasePts は SYMBOL_SPREAD（ポイント整数）由来 → 価格単位に変換
   double tightPts = g_spreadBasePts * SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 2.0;

   // 0-100幅（Fib%算出用）
   double fib0   = g_impulseStart;
   double fib100 = g_impulseEnd;
   double fibRange = MathAbs(fib100 - fib0);

   // 各MA値の取得と分類
   int    confluenceCount = 0;
   int    tightHitCount   = 0;
   string inBandList      = "";
   string inBandFibPct    = "";
   string tightHitList    = "";
   string nearBandList    = "";
   string maValues        = "";
   double nearestDist     = 999999.0;

   // 短期群・長期群（DirectionAligned用）
   double shortMAvals[];  // {5, 13, 21}
   double longMAvals[];   // {100, 200} or {100, 200, 365}
   ArrayResize(shortMAvals, 0);
   ArrayResize(longMAvals, 0);

   for(int i = 0; i < g_maPeriodsCount; i++)
   {
      double maVal = GetSMAValue(i, 1); // shift=1: 確定足
      if(maVal <= 0) continue;

      int period = g_maPeriods[i];

      // MA_Values記録
      if(maValues != "") maValues += ";";
      maValues += IntegerToString(period) + "=" + DoubleToString(maVal, digits);

      // 短期/長期分類
      if(period <= 21)
      {
         int sz = ArraySize(shortMAvals);
         ArrayResize(shortMAvals, sz + 1);
         shortMAvals[sz] = maVal;
      }
      else
      {
         int sz = ArraySize(longMAvals);
         ArrayResize(longMAvals, sz + 1);
         longMAvals[sz] = maVal;
      }

      // 帯中心からの距離
      double distFromCenter = maVal - bandCenter;
      // 符号: Impulse方向側=正、起点方向側=負
      if(g_impulseDir == DIR_SHORT)
         distFromCenter = -distFromCenter; // Short時は反転

      if(MathAbs(maVal - bandCenter) < MathAbs(nearestDist))
      {
         // nearestDistは符号つきで記録
         nearestDist = distFromCenter;
      }

      // 帯内判定
      bool inBand = (maVal >= bandLower && maVal <= bandUpper);

      // TightHit判定（evalPriceとの距離）
      bool tightHit = (MathAbs(maVal - evalPrice) <= tightPts);

      if(inBand)
      {
         confluenceCount++;

         if(inBandList != "") inBandList += ",";
         inBandList += IntegerToString(period);

         // Fib%算出
         double fibPct = 0.0;
         if(fibRange > 0)
         {
            if(g_impulseDir == DIR_LONG)
               fibPct = (maVal - fib0) / fibRange * 100.0;
            else
               fibPct = (fib0 - maVal) / fibRange * 100.0;
         }
         if(inBandFibPct != "") inBandFibPct += ",";
         inBandFibPct += IntegerToString(period) + ":" + DoubleToString(fibPct, 1);
      }

      if(tightHit)
      {
         tightHitCount++;
         if(tightHitList != "") tightHitList += ",";
         tightHitList += IntegerToString(period);
      }

      // 近傍判定（帯外だが近い）
      if(!inBand)
      {
         double distFromBand = 0.0;
         if(maVal > bandUpper)
            distFromBand = maVal - bandUpper;
         else if(maVal < bandLower)
            distFromBand = bandLower - maVal;

         if(distFromBand <= nearRange && distFromBand > 0)
         {
            if(nearBandList != "") nearBandList += ",";
            nearBandList += IntegerToString(period);
         }
      }
   }

   // DirectionAligned判定
   int dirAligned = -1; // -1 = 評価不能
   if(ArraySize(shortMAvals) > 0 && ArraySize(longMAvals) > 0)
   {
      // 中央値算出
      ArraySort(shortMAvals);
      ArraySort(longMAvals);
      double shortMed = shortMAvals[ArraySize(shortMAvals) / 2];
      double longMed  = longMAvals[ArraySize(longMAvals) / 2];

      if(g_impulseDir == DIR_LONG)
         dirAligned = (shortMed > longMed) ? 1 : 0;
      else if(g_impulseDir == DIR_SHORT)
         dirAligned = (shortMed < longMed) ? 1 : 0;
   }

   // 結果をg_statsに格納
   g_stats.MA_ConfluenceCount = confluenceCount;
   g_stats.MA_InBand_List     = inBandList;
   g_stats.MA_InBand_FibPct   = inBandFibPct;
   g_stats.MA_TightHitCount   = tightHitCount;
   g_stats.MA_TightHit_List   = tightHitList;
   g_stats.MA_NearBand_List   = nearBandList;
   g_stats.MA_NearestDistance  = (nearestDist < 999999.0) ? nearestDist : 0.0;
   g_stats.MA_DirectionAligned = dirAligned;
   g_stats.MA_Values          = maValues;
}

//+------------------------------------------------------------------+
//| メインStateMachine処理                                            |
//+------------------------------------------------------------------+
void ProcessStateMachine()
{
   // EnableTrading=false でもStateMachineは稼働する（ログ・描画・監視は継続）
   // Entry禁止制御はProcess_TOUCH_2_WAIT_CONFIRM内で行う

   switch(g_currentState)
   {
      case STATE_IDLE:
         Process_IDLE();
         break;

      case STATE_IMPULSE_FOUND:
         Process_IMPULSE_FOUND();
         break;

      case STATE_IMPULSE_CONFIRMED:
         Process_IMPULSE_CONFIRMED();
         break;

      case STATE_FIB_ACTIVE:
         Process_FIB_ACTIVE();
         break;

      case STATE_TOUCH_1:
         Process_TOUCH_1();
         break;

      case STATE_TOUCH_2_WAIT_CONFIRM:
         Process_TOUCH_2_WAIT_CONFIRM();
         break;

      case STATE_ENTRY_PLACED:
         Process_ENTRY_PLACED();
         break;

      case STATE_IN_POSITION:
         Process_IN_POSITION();
         break;

      case STATE_COOLDOWN:
         Process_COOLDOWN();
         break;
   }
}

//--- State処理関数群 ---

void Process_IDLE()
{
   if(!g_newBar) return;

   // Impulse検出
   if(DetectImpulse())
   {
      // TradeUUID発行（第13.7章）
      g_tradeUUID = GenerateTradeUUID();
      g_freezeCancelCount = 0;

      // === ANALYZE追加 === 新Impulse開始時にg_statsリセット
      g_stats.Reset();
      g_stats.TradeUUID = g_tradeUUID;
      g_stats.StartTime = TimeCurrent();

      // ADAPTIVE Spread更新（第12.3章: IMPULSE_FOUND発生時のみ）
      UpdateAdaptiveSpread();

      string rejectStage = "NONE";
      if(!EvaluateTrendFilterAndGuard(rejectStage))
      {
         g_stats.FinalState  = "TREND_FILTER_REJECT";
         g_stats.RejectStage = rejectStage;

         WriteLog(LOG_REJECT, "", rejectStage);
         DumpImpulseSummary();

         g_stats.Reset();
         g_tradeUUID = "";
         return;
      }

      ChangeState(STATE_IMPULSE_FOUND, "ImpulseDetected");
      WriteLog(LOG_IMPULSE, "", "", "dir=" + DirectionToString(g_impulseDir));

      // === NOTIFY === Impulse検出時に1回だけ通知（仕様：Impulse only）
      SendImpulseNotification();
   }
}

void Process_IMPULSE_FOUND()
{
   if(!g_newBar) return;

   // Freeze判定
   if(CheckFreeze())
   {
      g_frozen    = true;
      g_frozen100 = g_impulseEnd;
      g_freezeBarIndex = 1;
      g_freezeBarTime  = iTime(Symbol(), PERIOD_M1, 1);
      g_barsAfterFreeze = 0;

      ChangeState(STATE_IMPULSE_CONFIRMED, "FreezeEstablished");
      WriteLog(LOG_IMPULSE, "", "", "Frozen100=" + DoubleToString(g_frozen100,
               (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)));
   }
}

void Process_IMPULSE_CONFIRMED()
{
   // 即座にFIB_ACTIVEへ遷移（Fib算出＋BandWidth確定）

   // 第6章: GOLD DeepBand判定（FIB_ACTIVE遷移直前に評価）
   if(g_resolvedMarketMode == MARKET_MODE_GOLD)
   {
      g_goldDeepBandON = EvaluateGoldDeepBand();
      g_profile.deepBandEnabled = g_goldDeepBandON;
   }
   else if(g_resolvedMarketMode == MARKET_MODE_CRYPTO)
   {
      g_goldDeepBandON = false; // CRYPTOは50-61.8がPrimary
   }

   // BandWidth確定（第10章: IMPULSE_CONFIRMED → FIB_ACTIVE遷移時）
   CalculateBandWidth();

   // Fib算出
   CalculateFibLevels();

   // 押し帯計算
   CalculateBands();

   // === 13.9.6 MA Confluence === IMPULSE_CONFIRMED時点で1回だけ評価
   // RiskGateの前に配置: RiskGateFail時もMA状況を残すため
   EvaluateMAConfluence();

   // === 統計記録（Pass/Fail共通：RiskGate分岐前に確定） ===
   g_stats.RangePts         = MathAbs(g_impulseEnd - g_impulseStart);
   g_stats.BandWidthPts     = g_effectiveBandWidthPts;
   g_stats.LeaveDistancePts = g_effectiveBandWidthPts * g_profile.leaveDistanceMult;
   g_stats.SpreadBasePts    = g_spreadBasePts;
   {
      // RR / RangeCostMult のプレビュー値を記録
      double _atr = GetATR_M1(0);
      double _entry = g_fib500;
      double _sl = 0.0;
      double _tp = GetExtendedTP();   // CHANGE-006
      double _point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
      double _spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);

      _sl = (g_impulseDir == DIR_LONG)
            ? (g_impulseStart - _atr * g_profile.slATRMult)
            : (g_impulseStart + _atr * g_profile.slATRMult);

      double _risk   = MathAbs(_entry - _sl);
      double _reward = MathAbs(_tp - _entry);
      g_stats.RR_Actual = (_risk > _point * 0.5) ? (_reward / _risk) : 0.0;
      g_stats.RR_Min    = g_profile.minRR_EntryGate;

      double _cost = (_spread * g_profile.spreadMult) + (g_effectiveBandWidthPts * 2.0) + (g_stats.LeaveDistancePts * 2.0);
      double _rangeP = g_stats.RangePts;
      g_stats.RangeCostMult_Actual = (_cost > 0.0) ? (_rangeP / _cost) : 0.0;
      g_stats.RangeCostMult_Min    = g_profile.minRangeCostMult;
   }

   // === RiskGate判定（DOC-CORE 3.2 / 9.4.1） ===
   if(CheckNoEntryRiskGate())
   {
      // --- Fail: 統計フラグを正しく記録 ---
      g_stats.RiskGatePass = false;
      g_stats.RejectStage  = "RISK_GATE_FAIL";
      g_stats.FinalState   = "RiskGateFail";

      int _d = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
      double _range  = g_stats.RangePts;
      double _leave  = g_stats.LeaveDistancePts;
      double _spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
      double _ratio  = (_range > 0.0 ? (g_effectiveBandWidthPts * 2.0) / _range : 999.0);

      WriteLog(LOG_REJECT, "", "RISK_GATE_FAIL",
               "range=" + DoubleToString(_range, _d) +
               ";bw=" + DoubleToString(g_effectiveBandWidthPts, _d) +
               ";leave=" + DoubleToString(_leave, _d) +
               ";spread=" + DoubleToString(_spread, _d) +
               ";band_dom_ratio=" + DoubleToString(_ratio, 3));

      // DOC-CORE 3.2: LogLevel≠ANALYZE → IDLE（即終了）
      if(LogLevel != LOG_LEVEL_ANALYZE)
      {
         ChangeState(STATE_IDLE, "RiskGateFail");
         ResetAllState();
         return;
      }

      // DOC-CORE 3.2: ANALYZE → FIB_ACTIVEへ継続（SoftPass）
      // Confirm成立時に RISK_GATE_SOFT_BLOCK で止める
      g_riskGateSoftPass = true;
   }
   else
   {
      // --- Pass ---
      g_stats.RiskGatePass = true;
      g_riskGateSoftPass   = false;
   }

   // 第16章: Fib描写（IMPULSE_CONFIRMED遷移時に開始）
   CreateFibVisualization();
   ChangeState(STATE_FIB_ACTIVE, "FibCalculated");

   if(DumpFibValues)
   {
      Print("[FIB] 0=", g_impulseStart, " 100=", g_impulseEnd,
            " 38.2=", g_fib382, " 50=", g_fib500,
            " 61.8=", g_fib618, " 78.6=", g_fib786,
            " BW=", g_bandWidthPts,
            " DeepBandON=", g_goldDeepBandON);
   }
}

void Process_FIB_ACTIVE()
{
   if(!g_newBar) return;

   g_barsAfterFreeze++;

   // 構造無効チェック（FreezeCancelより優先：STRUCTURE_BREAKは最上位でIDLEへ）
   string br; int pr; string rl; double rp, ap, dp; int sh;
   if(CheckStructureInvalid_Detail(br, pr, rl, rp, ap, dp, sh))
   {
      g_stats.RejectStage         = "STRUCTURE_BREAK";
      g_stats.StructBreakReason   = br;
      g_stats.StructBreakPriority = pr;
      g_stats.StructBreakRefLevel = rl;
      g_stats.StructBreakRefPrice = rp;
      g_stats.StructBreakAtPrice  = ap;
      g_stats.StructBreakDistPts  = dp;
      g_stats.StructBreakBarShift = sh;

      g_stats.StructBreakSide     = (dp < 0.0 ? "UNDER" : (dp > 0.0 ? "OVER" : "ON"));
      g_stats.StructBreakAtKind   = "CLOSE";

      if(g_impulseDir == DIR_LONG)
      {
         double w = iLow(Symbol(), PERIOD_M1, 1);
         g_stats.StructBreakWickCross   = (w < rp) ? 1 : 0;
         g_stats.StructBreakWickDistPts = (w - rp) / _Point;
      }
      else
      {
         double w = iHigh(Symbol(), PERIOD_M1, 1);
         g_stats.StructBreakWickCross   = (w > rp) ? 1 : 0;
         g_stats.StructBreakWickDistPts = (w - rp) / _Point;
      }

      ChangeState(STATE_IDLE, "StructureInvalid");
      ResetAllState();
      return;
   }

   // FreezeCancel判定（CancelWindow内 ＆ まだTouchが一度も発生していない場合のみ）
   if(g_frozen &&
      g_barsAfterFreeze <= g_profile.freezeCancelWindowBars &&
      g_touchCount_Primary == 0 &&
      g_touchCount_Deep == 0 &&
      g_touchCount_Opt38 == 0)
   {
      if(CheckFreezeCancel())
      {
         g_frozen = false;
         g_freezeCancelCount++;
         g_freezeCancelled = true;

         g_stats.FreezeCancelCount = g_freezeCancelCount;

         WriteLog(LOG_IMPULSE, "", "", "FreezeCancel;count=" + IntegerToString(g_freezeCancelCount));

         ChangeState(STATE_IMPULSE_FOUND, "FreezeCancelled");
         return;
      }
   }

   // RetouchTimeLimit（第5.3.5章）
   if(g_barsAfterFreeze > g_profile.retouchTimeLimitBars)
   {
      g_stats.RejectStage = "RETOUCH_TIMEOUT";
      ChangeState(STATE_IDLE, "RetouchTimeLimitExpired");
      ResetAllState();
      return;
   }

   // タッチ判定
   int touch1BandId = ProcessTouchesForState();

   if(touch1BandId >= 0)
   {
      ChangeState(STATE_TOUCH_1, "Touch1Reached");
      return;
   }
}

// FIB_ACTIVEからのTouch1検出用
int ProcessTouchesForState()
{
   // 各帯のTouch1をチェック
   if(g_primaryBandUpper > 0 && g_primaryBandLower > 0)
   {
      if(CheckBandEntry(g_primaryBandUpper, g_primaryBandLower))
      {
         if(g_touchCount_Primary == 0 && !g_inBand_Primary)
         {
            g_inBand_Primary = true;
            g_touchCount_Primary = 1;
            RecordTouch1(0);
            return 0;
         }
      }
      else
      {
         if(g_inBand_Primary) g_inBand_Primary = false;
      }
   }

   if(g_deepBandUpper > 0 && g_deepBandLower > 0 && g_goldDeepBandON)
   {
      if(CheckBandEntry(g_deepBandUpper, g_deepBandLower))
      {
         if(g_touchCount_Deep == 0 && !g_inBand_Deep)
         {
            g_inBand_Deep = true;
            g_touchCount_Deep = 1;
            RecordTouch1(1);
            return 1;
         }
      }
      else
      {
         if(g_inBand_Deep) g_inBand_Deep = false;
      }
   }

   if(g_optBand38Upper > 0 && g_optBand38Lower > 0 && g_profile.optionalBand38)
   {
      if(CheckBandEntry(g_optBand38Upper, g_optBand38Lower))
      {
         if(g_touchCount_Opt38 == 0 && !g_inBand_Opt38)
         {
            g_inBand_Opt38 = true;
            g_touchCount_Opt38 = 1;
            RecordTouch1(2);
            return 2;
         }
      }
      else
      {
         if(g_inBand_Opt38) g_inBand_Opt38 = false;
      }
   }

   return -1;
}

void Process_TOUCH_1()
{
   if(!g_newBar) return;

   // Freeze後の経過本数を全Stateで前進させる（FreezeCancelWindow / RetouchTimeLimitの基準）
   g_barsAfterFreeze++;

   // Spreadチェック（第5.3.3章）
   if(!IsSpreadOK())
   {
      g_stats.RejectStage = "SPREAD_TOO_WIDE";
      ChangeState(STATE_IDLE, "SpreadTooWide");
      ResetAllState();
      return;
   }

   // RiskGate（第5.3.4章）: true=NoEntry（失効）なので反転
   if(CheckNoEntryRiskGate())
   {
      g_stats.RejectStage = "RISK_GATE_FAIL";
      ChangeState(STATE_IDLE, "RiskGateFail");
      ResetAllState();
      return;
   }

   // 構造無効チェック
   string br; int pr; string rl; double rp, ap, dp; int sh;
   if(CheckStructureInvalid_Detail(br, pr, rl, rp, ap, dp, sh))
   {
      g_stats.RejectStage         = "STRUCTURE_BREAK";
      g_stats.StructBreakReason   = br;
      g_stats.StructBreakPriority = pr;
      g_stats.StructBreakRefLevel = rl;
      g_stats.StructBreakRefPrice = rp;
      g_stats.StructBreakAtPrice  = ap;
      g_stats.StructBreakDistPts  = dp;
      g_stats.StructBreakBarShift = sh;

      g_stats.StructBreakSide     = (dp < 0.0 ? "UNDER" : (dp > 0.0 ? "OVER" : "ON"));
      g_stats.StructBreakAtKind   = "CLOSE";

      if(g_impulseDir == DIR_LONG)
      {
         double w = iLow(Symbol(), PERIOD_M1, 1);
         g_stats.StructBreakWickCross   = (w < rp) ? 1 : 0;
         g_stats.StructBreakWickDistPts = (w - rp) / _Point;
      }
      else
      {
         double w = iHigh(Symbol(), PERIOD_M1, 1);
         g_stats.StructBreakWickCross   = (w > rp) ? 1 : 0;
         g_stats.StructBreakWickDistPts = (w - rp) / _Point;
      }

      ChangeState(STATE_IDLE, "StructureInvalid");
      ResetAllState();
      return;
   }

   // RetouchTimeLimit（第5.3.5章）
   if(g_barsAfterFreeze > g_profile.retouchTimeLimitBars)
   {
      g_stats.RejectStage = "RETOUCH_TIMEOUT";
      ChangeState(STATE_IDLE, "RetouchTimeLimitExpired");
      ResetAllState();
      return;
   }

   // タッチ判定（Leave→Touch2 を含む正規ロジック）
   int touch2BandId = ProcessTouches();
   if(touch2BandId >= 0)
   {
      ChangeState(STATE_TOUCH_2_WAIT_CONFIRM, "Touch2Reached");
      return;
   }
}

void CheckAdditionalTouch1()
{
   // まだTouch1未達の帯をチェック
   if(g_primaryBandUpper > 0 && g_touchCount_Primary == 0)
   {
      if(CheckBandEntry(g_primaryBandUpper, g_primaryBandLower) && !g_inBand_Primary)
      {
         g_inBand_Primary = true;
         g_touchCount_Primary = 1;
         WriteLog(LOG_TOUCH, "", "", "Touch1;BandId=0;LateDetect");
         g_stats.Touch1Count++;  // === ANALYZE追加 ===
      }
   }

   if(g_deepBandUpper > 0 && g_goldDeepBandON && g_touchCount_Deep == 0)
   {
      if(CheckBandEntry(g_deepBandUpper, g_deepBandLower) && !g_inBand_Deep)
      {
         g_inBand_Deep = true;
         g_touchCount_Deep = 1;
         WriteLog(LOG_TOUCH, "", "", "Touch1;BandId=1;LateDetect");
         g_stats.Touch1Count++;  // === ANALYZE追加 ===
      }
   }

   if(g_optBand38Upper > 0 && g_profile.optionalBand38 && g_touchCount_Opt38 == 0)
   {
      if(CheckBandEntry(g_optBand38Upper, g_optBand38Lower) && !g_inBand_Opt38)
      {
         g_inBand_Opt38 = true;
         g_touchCount_Opt38 = 1;
         WriteLog(LOG_TOUCH, "", "", "Touch1;BandId=2;LateDetect");
         g_stats.Touch1Count++;  // === ANALYZE追加 ===
      }
   }
}

void Process_TOUCH_2_WAIT_CONFIRM()
{
   if(!g_newBar) return;

   // Freeze後の経過本数を全Stateで前進させる（RetouchTimeLimitの基準）
   g_barsAfterFreeze++;

   // Spreadチェック（第5.3.3章）
   if(!IsSpreadOK())
   {
      g_stats.RejectStage = "SPREAD_TOO_WIDE";
      ChangeState(STATE_IDLE, "SpreadTooWide");
      ResetAllState();
      return;
   }

   // RiskGate（第5.3.4章）
   if(CheckNoEntryRiskGate())
   {
      g_stats.RejectStage = "RISK_GATE_FAIL";
      ChangeState(STATE_IDLE, "RiskGateFail");
      ResetAllState();
      return;
   }

   // 構造無効チェック
   string br; int pr; string rl; double rp, ap, dp; int sh;
   if(CheckStructureInvalid_Detail(br, pr, rl, rp, ap, dp, sh))
   {
      g_stats.RejectStage         = "STRUCTURE_BREAK";
      g_stats.StructBreakReason   = br;
      g_stats.StructBreakPriority = pr;
      g_stats.StructBreakRefLevel = rl;
      g_stats.StructBreakRefPrice = rp;
      g_stats.StructBreakAtPrice  = ap;
      g_stats.StructBreakDistPts  = dp;
      g_stats.StructBreakBarShift = sh;

      g_stats.StructBreakSide     = (dp < 0.0 ? "UNDER" : (dp > 0.0 ? "OVER" : "ON"));
      g_stats.StructBreakAtKind   = "CLOSE";

      if(g_impulseDir == DIR_LONG)
      {
         double w = iLow(Symbol(), PERIOD_M1, 1);
         g_stats.StructBreakWickCross   = (w < rp) ? 1 : 0;
         g_stats.StructBreakWickDistPts = (w - rp) / _Point;
      }
      else
      {
         double w = iHigh(Symbol(), PERIOD_M1, 1);
         g_stats.StructBreakWickCross   = (w > rp) ? 1 : 0;
         g_stats.StructBreakWickDistPts = (w - rp) / _Point;
      }

      ChangeState(STATE_IDLE, "StructureInvalid");
      ResetAllState();
      return;
   }

   // RetouchTimeLimit（第5.3.5章）
   if(g_barsAfterFreeze > g_profile.retouchTimeLimitBars)
   {
      g_stats.RejectStage = "RETOUCH_TIMEOUT";
      ChangeState(STATE_IDLE, "RetouchTimeLimitExpired");
      ResetAllState();
      return;
   }

   // ConfirmTimeLimit（第5.3.6章）
   if(g_confirmWaitBars > g_profile.confirmTimeLimitBars)
   {
      g_stats.RejectStage = "CONFIRM_TIMEOUT";
      ChangeState(STATE_IDLE, "ConfirmTimeLimitExpired");
      ResetAllState();
      return;
   }

   // Confirm判定（第5.3.7章）
   if(g_resolvedMarketMode == MARKET_MODE_FX || g_resolvedMarketMode == MARKET_MODE_GOLD)
      UpdateFractalMicroLevels();

   ENUM_CONFIRM_TYPE ct = EvaluateConfirm();
   if(ct != CONFIRM_NONE)
   {
      g_confirmType = ct;
      g_stats.ConfirmCount++;
      g_stats.ConfirmReached = true;

      WriteLog(LOG_CONFIRM, "", "ConfirmOK", "ConfirmType=" + ConfirmTypeToString(ct));

      // DOC-CORE 3.2: SoftGate経由（ANALYZE時RiskGateFail継続分）→ Entryせず終了
      if(g_riskGateSoftPass)
      {
         g_stats.RejectStage = "RISK_GATE_SOFT_BLOCK";
         g_stats.FinalState  = "RiskGateSoftBlock";
         WriteLog(LOG_REJECT, "", "RISK_GATE_SOFT_BLOCK", "SoftPass=1;ConfirmType=" + ConfirmTypeToString(ct));
         ChangeState(STATE_IDLE, "RiskGateSoftBlock");
         ResetAllState();
         return;
      }

      // === EntryGate: RR / RangeCost チェック（DOC-CORE 9.5） ===
      {
         double _egAtr = GetATR_M1(0);
         double _egEntry = (g_impulseDir == DIR_LONG)
                           ? SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                           : SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double _egTP = GetExtendedTP();   // CHANGE-006: RangeCost評価用（理論TP）
         double _egSL = (g_impulseDir == DIR_LONG)
                        ? (g_impulseStart - _egAtr * g_profile.slATRMult)
                        : (g_impulseStart + _egAtr * g_profile.slATRMult);

         double _egRisk   = MathAbs(_egEntry - _egSL);
         double _egReward = MathAbs(_egTP - _egEntry);
         double _egPoint  = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
         double _egRR     = (_egRisk > _egPoint * 0.5) ? (_egReward / _egRisk) : 0.0;

         // (a) CHANGE-008: MinRR check 廃止（RR Gate無効化）
         // RR値は記録のみ行い、Rejectしない
         g_stats.RR_Actual = _egRR;

         // (b) MinRangeCostMult check（維持）
         double _egSpread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double _egRangeCost = (_egSpread > 0.0) ? (_egReward / _egSpread) : 999.0;
         if(_egRangeCost < g_profile.minRangeCostMult)
         {
            g_stats.RangeCostMult_Actual = _egRangeCost;
            g_stats.RejectStage = "RANGE_COST_FAIL";
            g_stats.FinalState  = "EntryGate_RangeCost_Fail";
            WriteLog(LOG_REJECT, "", "RANGE_COST_FAIL",
                     "RangeCost=" + DoubleToString(_egRangeCost, 2) +
                     ";MinRangeCost=" + DoubleToString(g_profile.minRangeCostMult, 2) +
                     ";Reward=" + DoubleToString(_egReward, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) +
                     ";Spread=" + DoubleToString(_egSpread, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)));
            ChangeState(STATE_IDLE, "EntryGate_RangeCost_Fail");
            ResetAllState();
            return;
         }

         // EntryGate Pass → RR/RangeCostを記録
         g_stats.RangeCostMult_Actual = _egRangeCost;
      }

      // Entry実行
      if(!ExecuteEntry())
      {
         ChangeState(STATE_IDLE, "EntryRejected");
         ResetAllState();
         return;
      }

      g_stats.EntryGatePass = true;
      ChangeState(STATE_ENTRY_PLACED, "EntryPlaced");
      return;
   }
   g_confirmWaitBars++;
}

void Process_ENTRY_PLACED()
{
   // 通常は即約定のため、この状態は一瞬
   // 指値の場合のみ滞留する可能性あり
   if(!g_newBar) return;

   // 指値未約定チェック
   // （成行の場合はTOUCH_2_WAIT_CONFIRMからIN_POSITIONへ直接遷移済み）
   // ここに来るのは指値が未約定の場合のみ

   // 約定確認
   if(PositionSelectByTicket(g_ticket))
   {
      ChangeState(STATE_IN_POSITION, "OrderFilled");
      g_positionBars = 0;
   }
}

void Process_IN_POSITION()
{
   if(!g_newBar) return;

   ManagePosition();
}

void Process_COOLDOWN()
{
   if(!g_newBar) return;

   g_cooldownBars++;
   if(g_cooldownBars >= g_cooldownDuration)
   {
      g_cooldownBars = 0;
      ChangeState(STATE_IDLE, "CooldownExpired");
      ResetAllState();
   }
}

bool CheckDirectionOK()
{
   return true;
}

bool CheckSpreadOK()
{
   return IsSpreadOK();
}

bool CheckRiskGate()
{
   return !CheckNoEntryRiskGate();
}

bool CheckConfirm()
{
   if(g_resolvedMarketMode == MARKET_MODE_FX || g_resolvedMarketMode == MARKET_MODE_GOLD)
      UpdateFractalMicroLevels();

   ENUM_CONFIRM_TYPE ct = EvaluateConfirm();
   if(ct == CONFIRM_NONE) return false;

   g_confirmType = ct;
   g_stats.ConfirmCount++;

   WriteLog(LOG_CONFIRM, "", "ConfirmOK", "ConfirmType=" + ConfirmTypeToString(ct));

   if(!ExecuteEntry())
   {
      g_stats.RejectStage = "EXECUTION_REJECTED";
      ChangeState(STATE_IDLE, "ExecutionRejected");
      ResetAllState();
      return false;
   }

   return true;
}

string TrendDirFromSlope(double slope, double slopeMin)
{
   if(slope >= slopeMin)  return "LONG";
   if(slope <= -slopeMin) return "SHORT";
   return "FLAT";
}

bool IsAlignedWithImpulse(string trendDir)
{
   if(g_impulseDir == DIR_LONG  && trendDir == "LONG")  return true;
   if(g_impulseDir == DIR_SHORT && trendDir == "SHORT") return true;
   return false;
}

bool IsBearishEngulfing(string sym, ENUM_TIMEFRAMES tf)
{
   double o1 = iOpen(sym, tf, 1);
   double c1 = iClose(sym, tf, 1);
   double o2 = iOpen(sym, tf, 2);
   double c2 = iClose(sym, tf, 2);

   if(c1 >= o1) return false;

   double bodyHi1 = MathMax(o1, c1);
   double bodyLo1 = MathMin(o1, c1);
   double bodyHi2 = MathMax(o2, c2);
   double bodyLo2 = MathMin(o2, c2);

   return (bodyHi1 >= bodyHi2 && bodyLo1 <= bodyLo2);
}

bool IsBullishEngulfing(string sym, ENUM_TIMEFRAMES tf)
{
   double o1 = iOpen(sym, tf, 1);
   double c1 = iClose(sym, tf, 1);
   double o2 = iOpen(sym, tf, 2);
   double c2 = iClose(sym, tf, 2);

   if(c1 <= o1) return false;

   double bodyHi1 = MathMax(o1, c1);
   double bodyLo1 = MathMin(o1, c1);
   double bodyHi2 = MathMax(o2, c2);
   double bodyLo2 = MathMin(o2, c2);

   return (bodyHi1 >= bodyHi2 && bodyLo1 <= bodyLo2);
}

bool WickRejectOpposite_GOLD(bool impulseLong)
{
   double o = iOpen(Symbol(), PERIOD_H1, 1);
   double c = iClose(Symbol(), PERIOD_H1, 1);
   double h = iHigh(Symbol(), PERIOD_H1, 1);
   double l = iLow(Symbol(), PERIOD_H1, 1);

   double range = h - l;
   if(range <= 0) return false;

   double upper = h - MathMax(o, c);
   double lower = MathMin(o, c) - l;

   if(impulseLong)
      return (upper / range) >= ReversalWickRatioMin_GOLD;
   else
      return (lower / range) >= ReversalWickRatioMin_GOLD;
}

bool EvaluateTrendFilterAndGuard(string &rejectStageOut)
{
   rejectStageOut = "NONE";

   g_stats.TrendFilterEnable = TrendFilter_Enable ? 1 : 0;
   g_stats.TrendTF           = "M15";
   g_stats.TrendMethod       = "";
   g_stats.TrendDir          = "";
   g_stats.TrendSlope        = 0.0;
   g_stats.TrendSlopeMin     = 0.0;
   g_stats.TrendSlopeSet     = false;
   g_stats.TrendATRFloor     = 0.0;
   g_stats.TrendATRFloorSet  = false;
   g_stats.TrendAligned      = -1;

   g_stats.ReversalGuardEnable     = ReversalGuard_Enable ? 1 : 0;
   g_stats.ReversalTF             = "H1";
   g_stats.ReversalGuardTriggered = -1;
   g_stats.ReversalReason         = "";

   if(!TrendFilter_Enable)
      return true;

   string sym = Symbol();

   double ema50_1 = GetMAValue(sym, PERIOD_M15, 50, MODE_EMA, PRICE_CLOSE, 1);
   double ema50_2 = GetMAValue(sym, PERIOD_M15, 50, MODE_EMA, PRICE_CLOSE, 2);
   double atr15   = GetATRValue(sym, PERIOD_M15, 14, 1);

   if(ema50_1 == EMPTY_VALUE || ema50_2 == EMPTY_VALUE || atr15 == EMPTY_VALUE)
   {
      g_stats.TrendDir = "FLAT";
      g_stats.TrendAligned = 0;
      rejectStageOut = "TREND_FLAT";
      return false;
   }

   double slope    = ema50_1 - ema50_2;
   double slopeMin = 0.0;
   string trendDir = "FLAT";

   if(g_resolvedMarketMode == MARKET_MODE_CRYPTO)
   {
      double ema21_1 = GetMAValue(sym, PERIOD_M15, 21, MODE_EMA, PRICE_CLOSE, 1);
      if(ema21_1 == EMPTY_VALUE)
      {
         g_stats.TrendDir = "FLAT";
         g_stats.TrendAligned = 0;
         rejectStageOut = "TREND_FLAT";
         return false;
      }

      g_stats.TrendMethod = "EMA21x50_SLOPE";
      slopeMin = atr15 * TrendSlopeMult_CRYPTO;

      g_stats.TrendSlope       = slope;
      g_stats.TrendSlopeMin    = slopeMin;
      g_stats.TrendSlopeSet    = true;

      if(ema21_1 > ema50_1 && slope >= slopeMin)       trendDir = "LONG";
      else if(ema21_1 < ema50_1 && slope <= -slopeMin) trendDir = "SHORT";
      else                                             trendDir = "FLAT";
   }
   else if(g_resolvedMarketMode == MARKET_MODE_GOLD)
   {
      g_stats.TrendMethod = "EMA50_SLOPE";
      slopeMin = atr15 * TrendSlopeMult_GOLD;

      g_stats.TrendSlope       = slope;
      g_stats.TrendSlopeMin    = slopeMin;
      g_stats.TrendSlopeSet    = true;

      double atrPts = (atr15 / _Point);
      g_stats.TrendATRFloor    = TrendATRFloorPts_GOLD;
      g_stats.TrendATRFloorSet = true;

      if(atrPts < TrendATRFloorPts_GOLD)
         trendDir = "FLAT";
      else
         trendDir = TrendDirFromSlope(slope, slopeMin);
   }
   else
   {
      g_stats.TrendMethod = "EMA50_SLOPE";
      slopeMin = atr15 * TrendSlopeMult_FX;

      g_stats.TrendSlope       = slope;
      g_stats.TrendSlopeMin    = slopeMin;
      g_stats.TrendSlopeSet    = true;

      trendDir = TrendDirFromSlope(slope, slopeMin);
   }

   g_stats.TrendDir = trendDir;

   if(trendDir == "FLAT")
   {
      g_stats.TrendAligned = 0;
      rejectStageOut = "TREND_FLAT";
      return false;
   }

   bool aligned = IsAlignedWithImpulse(trendDir);
   g_stats.TrendAligned = aligned ? 1 : 0;

   if(!aligned)
   {
      rejectStageOut = "TREND_MISMATCH";
      return false;
   }

   if(!ReversalGuard_Enable)
   {
      g_stats.ReversalGuardTriggered = 0;
      return true;
   }

   bool impulseLong = (g_impulseDir == DIR_LONG);

   double o1 = iOpen(sym, PERIOD_H1, 1);
   double c1 = iClose(sym, PERIOD_H1, 1);
   double atr1= GetATRValue(sym, PERIOD_H1, 14, 1);

   if(atr1 == EMPTY_VALUE)
   {
      g_stats.ReversalGuardTriggered = 0;
      return true;
   }

   double body= MathAbs(c1 - o1);

   double bigBodyMult = ReversalBigBodyMult_FX;
   if(g_resolvedMarketMode == MARKET_MODE_GOLD)   bigBodyMult = ReversalBigBodyMult_GOLD;
   if(g_resolvedMarketMode == MARKET_MODE_CRYPTO) bigBodyMult = ReversalBigBodyMult_CRYPTO;

   bool oppositeBigBody = (body >= (atr1 * bigBodyMult)) &&
                          ((impulseLong && (c1 < o1)) || (!impulseLong && (c1 > o1)));

   if(oppositeBigBody)
   {
      g_stats.ReversalGuardTriggered = 1;
      g_stats.ReversalReason = "BIG_BODY";
      rejectStageOut = "REVERSAL_GUARD";
      return false;
   }

   if(ReversalEngulfing_Enable)
   {
      bool oppEng = impulseLong ? IsBearishEngulfing(sym, PERIOD_H1) : IsBullishEngulfing(sym, PERIOD_H1);
      if(oppEng)
      {
         g_stats.ReversalGuardTriggered = 1;
         g_stats.ReversalReason = "ENGULFING";
         rejectStageOut = "REVERSAL_GUARD";
         return false;
      }
   }

   if(g_resolvedMarketMode == MARKET_MODE_GOLD && ReversalWickReject_Enable_GOLD)
   {
      if(WickRejectOpposite_GOLD(impulseLong))
      {
         g_stats.ReversalGuardTriggered = 1;
         g_stats.ReversalReason = "WICK_REJECT";
         rejectStageOut = "REVERSAL_GUARD";
         return false;
      }
   }

   g_stats.ReversalGuardTriggered = 0;
   return true;
}

double GetMAValue(const string sym, ENUM_TIMEFRAMES tf, int period, ENUM_MA_METHOD method, int applied_price, int shift)
{
   int h = iMA(sym, tf, period, 0, method, applied_price);
   if(h == INVALID_HANDLE) return EMPTY_VALUE;

   double buf[];
   ArraySetAsSeries(buf, true);

   if(CopyBuffer(h, 0, shift, 1, buf) != 1)
   {
      IndicatorRelease(h);
      return EMPTY_VALUE;
   }

   IndicatorRelease(h);
   return buf[0];
}

double GetATRValue(const string sym, ENUM_TIMEFRAMES tf, int period, int shift)
{
   int h = iATR(sym, tf, period);
   if(h == INVALID_HANDLE) return EMPTY_VALUE;

   double buf[];
   ArraySetAsSeries(buf, true);

   if(CopyBuffer(h, 0, shift, 1, buf) != 1)
   {
      IndicatorRelease(h);
      return EMPTY_VALUE;
   }

   IndicatorRelease(h);
   return buf[0];
}

// Touchログ/統計カウント（Touch1）
void RecordTouch1(const int bandId)
{
   g_stats.Touch1Count++;
   WriteLog(LOG_TOUCH, "", "", "Touch1;BandId=" + IntegerToString(bandId));
}

// Touchログ/統計カウント（Leave）
void RecordLeave(const int bandId)
{
   g_stats.LeaveCount++;
   WriteLog(LOG_TOUCH, "", "", "Leave;BandId=" + IntegerToString(bandId));
}

// Touchログ/統計カウント（Touch2）
void RecordTouch2(const int bandId)
{
   g_stats.Touch2Count++;
   g_stats.Touch2Reached = true;
   WriteLog(LOG_TOUCH, "", "", "Touch2;BandId=" + IntegerToString(bandId));
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // MarketProfile初期化
   InitMarketProfile();

   if(DumpMarketProfile)
   {
      Print("[PROFILE] MarketMode=", MarketModeToString(g_resolvedMarketMode),
            " ImpulseATRMult=", g_profile.impulseATRMult,
            " SmallBodyRatio=", g_profile.smallBodyRatio,
            " FreezeCancelWindow=", g_profile.freezeCancelWindowBars,
            " ConfirmTimeLimit=", g_profile.confirmTimeLimitBars,
            " SpreadMult=", g_profile.spreadMult,
            " SLATRMult=", g_profile.slATRMult,
            " TPExtRatio=", g_profile.tpExtensionRatio);
   }

   // ATRハンドル作成
   g_atrHandleM1 = iATR(Symbol(), PERIOD_M1, 14);
   if(g_atrHandleM1 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR handle");
      return INIT_FAILED;
   }

   // === CHANGE-008 === Exit EMAハンドル作成（M1固定）
   g_exitEMAFastHandle = iMA(Symbol(), PERIOD_M1, ExitMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_exitEMASlowHandle = iMA(Symbol(), PERIOD_M1, ExitMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_exitEMAFastHandle == INVALID_HANDLE || g_exitEMASlowHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Exit EMA handles. Fast=", g_exitEMAFastHandle, " Slow=", g_exitEMASlowHandle);
      return INIT_FAILED;
   }

   // === 13.9.6 MA Confluence === SMAハンドル作成
   InitMAPeriods();
   for(int i = 0; i < MA_MAX_PERIODS; i++)
      g_smaHandles[i] = INVALID_HANDLE;

   for(int i = 0; i < g_maPeriodsCount; i++)
   {
      g_smaHandles[i] = iMA(Symbol(), PERIOD_M1, g_maPeriods[i], 0, MODE_SMA, PRICE_CLOSE);
      if(g_smaHandles[i] == INVALID_HANDLE)
      {
         Print("WARNING: Failed to create SMA handle for period=", g_maPeriods[i]);
      }
   }

   // Spread初期値
   if(MaxSpreadMode == SPREAD_MODE_FIXED)
   {
      g_maxSpreadPts = InputMaxSpreadPts;
   }
   else
   {
      // ADAPTIVE: 仮の初期値（IMPULSE_FOUND時に更新）
      g_maxSpreadPts = GetCurrentSpreadPts() * g_profile.spreadMult;
   }

   // Logger初期化
   LoggerInit();

   // 初期State
   g_currentState = STATE_IDLE;
   g_lastBarTime = 0;

   Print(EA_NAME, " initialized. Mode=", MarketModeToString(g_resolvedMarketMode));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Logger解放
   LoggerDeinit();

   // TF変更(チャート変更)等ではオブジェクトを残す（視認性維持）
   bool keep_visuals = (reason == REASON_CHARTCHANGE);

   if(!keep_visuals)
   {
      // Fib Visualization削除（第16.8章）
      DeleteCurrentFibVisualization();
   }

   // ATRハンドル解放
   if(g_atrHandleM1 != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandleM1);
      g_atrHandleM1 = INVALID_HANDLE;
   }

   // === CHANGE-008 === Exit EMAハンドル解放
   if(g_exitEMAFastHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_exitEMAFastHandle);
      g_exitEMAFastHandle = INVALID_HANDLE;
   }
   if(g_exitEMASlowHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_exitEMASlowHandle);
      g_exitEMASlowHandle = INVALID_HANDLE;
   }

   // === 13.9.6 MA Confluence === SMAハンドル解放
   for(int i = 0; i < g_maPeriodsCount; i++)
   {
      if(g_smaHandles[i] != INVALID_HANDLE)
      {
         IndicatorRelease(g_smaHandles[i]);
         g_smaHandles[i] = INVALID_HANDLE;
      }
   }

   Print(EA_NAME, " deinitialized. Reason=", reason);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // 新しいバー検出
   g_newBar = IsNewBar();

   // Spread/Slippage超過チェック（State維持、エントリー禁止のみ）
   // これは取引禁止フラグとして機能し、構造無効とはしない（第9.4章）

   // FreezeCancel チェック（Tick単位：CancelWindowBars内のリアルタイム監視）
   if(g_frozen && g_currentState >= STATE_IMPULSE_CONFIRMED &&
      g_currentState <= STATE_TOUCH_1)
   {
      if(g_barsAfterFreeze <= g_profile.freezeCancelWindowBars)
      {
         if(CheckFreezeCancel())
         {
            g_frozen = false;
            g_freezeCancelCount++;

            g_stats.FreezeCancelCount = g_freezeCancelCount;  // === ANALYZE追加 ===

            WriteLog(LOG_IMPULSE, "", "", "FreezeCancel;count=" + IntegerToString(g_freezeCancelCount));
            ChangeState(STATE_IMPULSE_FOUND, "FreezeCancelled_Tick");
         }
      }
   }

   // メインStateMachine処理
   ProcessStateMachine();
   
   // 状態がアクティブな間、帯の右端を常に最新の時間に更新する（微修正案）
   if(g_currentState >= STATE_FIB_ACTIVE && g_currentState <= STATE_IN_POSITION)
   {
      if(g_bandObjName != "" && ObjectFind(0, g_bandObjName) >= 0)
      {
         ObjectSetInteger(0, g_bandObjName, OBJPROP_TIME, 1,
                          TimeCurrent() + (datetime)(PeriodSeconds(PERIOD_M1) * 10));
      }
   }
}

//+------------------------------------------------------------------+