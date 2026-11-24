//+------------------------------------------------------------------+
//|  AILens.mqh                                                       |
//|  AI Agent Lens - shared core logic for the indicator and the EA.  |
//|                                                                   |
//|  THIS FILE IS THE ONLY IMPLEMENTATION OF THE STRATEGY.            |
//|  Both AILens_Ind.mq5 (drawing) and AILens_EA.mq5 (signals) include |
//|  it, so they cannot drift apart. That is the whole point of       |
//|  moving the strategy off Pine: one implementation, one feed.      |
//|                                                                   |
//|  Ported from ai-agent-lens-optimized.pine. When the two disagree,  |
//|  this file is the one that has to be fixed - there is no other    |
//|  copy of the logic to consult.                                    |
//+------------------------------------------------------------------+
#ifndef __AILENS_MQH__
#define __AILENS_MQH__

//==================================================================//
//  CONFIG                                                          //
//==================================================================//
struct SAILensConfig
{
   // ---- signals ----
   int      scoreThreshold;      // 70
   bool     blockHighVol;        // true
   ENUM_TIMEFRAMES htfTf;        // PERIOD_H4
   int      htfEmaLen;           // 50
   bool     requireHtfAlign;     // true
   double   minAdxEntry;         // 15
   double   maxExtAtr;           // 2.0
   int      minBarsBetween;      // 3
   // "Off" | "Block opposite" | "Require aligned"
   string   structGate;
   // "Redistribute" | "Neutral 10"
   string   htfUnavailable;

   // ---- trend ----
   int      emaFastLen, emaMidLen, emaSlowLen, slopeLen;
   int      rsiLen;
   double   rsiOB, rsiOS;
   int      adxLen;
   double   adxTrend;

   // ---- volume / volatility ----
   int      volLen, atrLen, atrPctLen;
   double   highVolPct;
   // "Tick volume" | "Range proxy" | "Neutralize"
   string   volumeMode;

   // ---- structure ----
   int      swingLen;

   // ---- risk ----
   double   stopAtr;             // 1.5
   // "ATR" | "Structure (swing)"
   string   stopMode;
   double   maxStopAtr;          // 2.5
   double   t1R, t2R;            // 1.5 / 3.0
   double   partialT1Pct;        // 50
   bool     moveBeAfterT1;       // true
   bool     useTrailing;         // true
   double   trailAtr;            // 1.5
   bool     trailFromStart;      // false
   int      maxBarsInTrade;      // 0 = off

   // ---- session ----
   bool     useSessionFilter;
   int      sesTzOffsetHours;    // hours added to broker time to reach the session clock
   bool     tradeAsia, tradeLondon, tradeNy;
   int      asiaStart,   asiaEnd;
   int      londonStart, londonEnd;
   int      nyStart,     nyEnd;
   int      sesBufferMin;
   int      blockFriLateHours;
};

//==================================================================//
//  PER-BAR OUTPUT                                                  //
//==================================================================//
struct SAILensOut
{
   int      longScore, shortScore;
   string   regime;
   int      regimeCode;          // 1 up, -1 down, 0 range, 2 high vol
   bool     inSession;
   string   sesLabel;
   string   structBias, structEvent;

   int      lTrend, lMom, lStr, lVol, lHtf;
   int      sTrend, sMom, sStr, sVol, sHtf;

   int      denom, activeFactors;
   double   rescale;

   int      htfBias;
   bool     htfValid;
   string   htfBiasStr;

   double   emaF, emaM, emaS;
   double   rsiV, adxV, diPlus, diMinus;
   double   macdHist;
   double   atrV, atrPct;
   double   relVol, relRng;
   double   vwapV, pdh, pdl;

   string   eventStr;            // LONG_SETUP | SHORT_SETUP | TRADE_UPDATE | BAR_CLOSE
   int      tradeSide;           // 1 / -1 / 0
   string   tradeStatus;
   double   entry, stop, t1, t2;
   double   openR, realizedR;
};

//==================================================================//
//  TRADE STATE                                                     //
//==================================================================//
struct SAILensTrade
{
   int      side;                // 1 long, -1 short, 0 flat
   string   sideStr;
   string   status;
   double   entry, stop, stop0, risk, t1, t2;
   datetime entryTime;           // identity of the entry bar. A shift is NOT stable:
                                 // every new bar renumbers all of them.
   int      bar;                 // entry shift as of the last processing pass (display only)
   bool     t1Taken, beMoved;
   double   partial;
   double   realizedR, peakR;
   double   runHigh, runLow;
   string   stopModeUsed;
};

//==================================================================//
//  HELPERS                                                         //
//==================================================================//
string AILens_TfToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
   }
   // Never fall back to a specific timeframe: a wrong label in the log would send you
   // looking at data for a chart you are not even on. Name the unknown instead.
   return "TF" + IntegerToString((int)tf);
}

// Window test. start == end means never, matching the Pine helper.
bool AILens_InWindow(int h, int s, int e)
{
   if(s == e)  return false;
   if(s <  e)  return (h >= s && h < e);
   return (h >= s || h < e);          // wraps past midnight
}

int AILens_MinsSinceOpen(int h, int m, int s)
{
   int d = h * 60 + m - s * 60;
   return (d < 0 ? d + 1440 : d);
}

//==================================================================//
//  CORE ENGINE                                                     //
//==================================================================//
class CAILensCore
{
private:
   SAILensConfig  m_cfg;
   string         m_symbol;
   ENUM_TIMEFRAMES m_tf;

   // indicator handles
   int  m_hEmaF, m_hEmaM, m_hEmaS;
   int  m_hRsi, m_hMacd, m_hAdx, m_hAtr;
   int  m_hHtfEma;

   // series, indexed by SHIFT (0 = current bar), and set as series arrays so that
   // index semantics stay uniform: higher index = older bar.
   int      m_n;                 // number of bars loaded
   double   m_open[], m_high[], m_low[], m_close[];
   long     m_volRaw[];          // CopyTickVolume only writes long[]
   double   m_vol[];             // converted copy, used by the score
   datetime m_time[];
   double   m_emaF[], m_emaM[], m_emaS[];
   double   m_rsi[], m_macd[], m_sig[], m_adx[], m_dip[], m_dim[];
   double   m_atr[];
   // history-derived series (computed once per load)
   int      m_htfBiasArr[];      // per chart shift: -1 / 0 / +1
   bool     m_htfValidArr[];     // per chart shift
   double   m_vwap[];
   double   m_pdh[], m_pdl[];

   // higher timeframe raw series
   double   m_htfEma[];          // EMA on the HTF series, indexed by HTF shift
   datetime m_htfTime[];
   double   m_htfClose[];

   // state
   SAILensTrade m_trade;
   SAILensOut   m_out;
   datetime     m_lastSigTime;   // entry time of the last setup (shift is unstable)
   string       m_lastSigSide;
   double       m_swingH1, m_swingH2, m_swingL1, m_swingL2;
   string       m_structBias;
   datetime     m_lastBarTime;   // newest CLOSED bar time processed
   datetime     m_formingTime;   // time of the bar still forming, i.e. m_time[0]
   string       m_lastError;     // why the last load failed; "" when it succeeded
   uint         m_lastLoadAttempt; // GetTickCount() of the last LoadSeries attempt

   // ---- internals ----
   bool  LoadSeries(const int want);
   void  StepBar(const int shift);
   void  Publish(const int shift, const string eventStr, const string regime,
                 const int regimeCode, const bool inSession, const string sesLabel,
                 const string structEvent, const int longScore, const int shortScore,
                 const int lT, const int lM, const int lS, const int lV, const int lH,
                 const int sT, const int sM, const int sS, const int sV, const int sH,
                 const double atrPct);
   void  ComputePivots(const int shift);
   void  ManageTrade(const int shift);
   void  OpenTrade(const int shift, const int side, const double atrV);
   double StopFor(const double price, const int side, const double atrV) const;
   int   ScoreAt(const int shift, const int side, int &fTrend, int &fMom,
                 int &fStr, int &fVol, int &fHtf) const;
   bool  SessionOk(const datetime t, bool &inSession, string &label) const;
   void  FillHtfBias(const int shift, bool &valid, int &bias) const;
   void  BuildHtfArrays(void);
   int   ShiftOfTime(const datetime t) const;
   int   WarmupBars(void) const;
   void  ResetState(void);

public:
                     CAILensCore(void);
                    ~CAILensCore(void);

   bool              Init(const SAILensConfig &cfg, const string symbol,
                          const ENUM_TIMEFRAMES tf);
   void              Deinit(void);

   // Load history and replay every closed bar so the state matches a full backtest.
   bool              Warmup(const int maxBars = 4000);
   // Process bars that closed since the last call. Returns true if anything advanced.
   bool              Step(void);
   // Build the per-bar output for one arbitrary shift without touching trade state.
   // Used by the indicator to report the bar under the cursor.
   bool              Inspect(const int shift);

   SAILensOut        Out(void)   const { return m_out; }
   SAILensTrade      Trade(void) const { return m_trade; }
   SAILensConfig     Cfg(void)   const { return m_cfg; }
   double            SwingH1(void) const { return m_swingH1; }
   double            SwingL1(void) const { return m_swingL1; }
   int               LoadedBars(void) const { return m_n; }
   // Minimum history the engine can actually work with: WarmupBars() of indicator context
   // plus the forming bar, the newest closed bar, and a few spare. Checking a single
   // number here means the gates and the log messages cannot disagree about what "enough
   // history" means. Defined out-of-line because it calls WarmupBars().
   int               MinBars(void) const;
   // Human-readable reason the last LoadSeries/Warmup failed, for logs and the
   // on-chart waiting label. Empty string when the last attempt succeeded.
   string            LastError(void) const { return m_lastError; }
   double            AtrAt(const int shift) const
                     { return (shift >= 0 && shift < m_n ? m_atr[shift] : EMPTY_VALUE); }
   double            CloseAt(const int shift) const
                     { return (shift >= 0 && shift < m_n ? m_close[shift] : EMPTY_VALUE); }
   datetime          TimeAt(const int shift) const
                     { return (shift >= 0 && shift < m_n ? m_time[shift] : 0); }
   // Reverse lookup. Binary search over the series array (descending times).
};

//------------------------------------------------------------------//
CAILensCore::CAILensCore(void)
{
   m_hEmaF = m_hEmaM = m_hEmaS = INVALID_HANDLE;
   m_hRsi  = m_hMacd = m_hAdx  = INVALID_HANDLE;
   m_hAtr  = INVALID_HANDLE;
   m_hHtfEma = INVALID_HANDLE;
   m_n = 0;
   m_formingTime = 0;
   m_lastBarTime = 0;
   m_lastError = "";
   m_lastLoadAttempt = 0;

   m_trade.side = 0;
   m_trade.status = "NONE";
   m_trade.sideStr = "NONE";
   m_lastSigTime  = 0;
   m_lastSigSide = "NONE";
   m_swingH1 = m_swingH2 = m_swingL1 = m_swingL2 = EMPTY_VALUE;
   m_structBias = "MIXED";
   // NOTE: ZeroMemory() is NOT legal on a struct containing strings, so every string
   // field of SAILensOut is assigned explicitly here.
   m_out.longScore = 0;  m_out.shortScore = 0;
   m_out.regime = "RANGE";
   m_out.sesLabel = "OFF";
   m_out.structBias = "MIXED";
   m_out.structEvent = "NONE";
   m_out.eventStr = "BAR_CLOSE";
   m_out.tradeSide = 0;
   m_out.tradeStatus = "NONE";
   m_out.sesLabel = "OFF";
   m_out.htfBiasStr = "N/A";
   m_out.denom = 100;  m_out.rescale = 1.0;  m_out.activeFactors = 5;
   m_out.htfValid = false;  m_out.htfBias = 0;
   m_out.lTrend = 0; m_out.lMom = 0; m_out.lStr = 0; m_out.lVol = 0; m_out.lHtf = 0;
   m_out.sTrend = 0; m_out.sMom = 0; m_out.sStr = 0; m_out.sVol = 0; m_out.sHtf = 0;
   m_out.emaF = 0; m_out.emaM = 0; m_out.emaS = 0;
   m_out.rsiV = 0; m_out.adxV = 0; m_out.diPlus = 0; m_out.diMinus = 0; m_out.macdHist = 0;
   m_out.atrV = 0; m_out.atrPct = 0; m_out.vwapV = 0; m_out.pdh = 0; m_out.pdl = 0;
   m_out.relVol = 0; m_out.relRng = 0;
   m_out.entry = 0; m_out.stop = 0; m_out.t1 = 0; m_out.t2 = 0;
   m_out.realizedR = 0; m_out.openR = 0;
}

//------------------------------------------------------------------//
CAILensCore::~CAILensCore(void)
{
   Deinit();
}

//------------------------------------------------------------------//
void CAILensCore::Deinit(void)
{
   if(m_hEmaF   != INVALID_HANDLE) IndicatorRelease(m_hEmaF);
   if(m_hEmaM   != INVALID_HANDLE) IndicatorRelease(m_hEmaM);
   if(m_hEmaS   != INVALID_HANDLE) IndicatorRelease(m_hEmaS);
   if(m_hRsi    != INVALID_HANDLE) IndicatorRelease(m_hRsi);
   if(m_hMacd   != INVALID_HANDLE) IndicatorRelease(m_hMacd);
   if(m_hAdx    != INVALID_HANDLE) IndicatorRelease(m_hAdx);
   if(m_hAtr    != INVALID_HANDLE) IndicatorRelease(m_hAtr);
   if(m_hHtfEma != INVALID_HANDLE) IndicatorRelease(m_hHtfEma);

   m_hEmaF = m_hEmaM = m_hEmaS = INVALID_HANDLE;
   m_hRsi  = m_hMacd = m_hAdx  = INVALID_HANDLE;
   m_hAtr  = INVALID_HANDLE;
   m_hHtfEma = INVALID_HANDLE;
}

//------------------------------------------------------------------//
bool CAILensCore::Init(const SAILensConfig &cfg, const string symbol,
                       const ENUM_TIMEFRAMES tf)
{
   // Release any handles from a previous Init on this object. OnInit runs again on a
   // timeframe switch while the global core object is reused, and creating a second set
   // of handles without releasing the first leaks them (MT5 keeps a limited pool).
   Deinit();

   m_cfg    = cfg;
   m_symbol = (symbol == "" ? _Symbol : symbol);
   m_tf     = tf;

   // State from the previous timeframe must not survive: the bars changed, so every
   // stored shift, price and trade reference is meaningless now. ResetState() clears the
   // simulated trade too. The HTF arrays are dropped as well, because a timeframe above
   // the HTF leaves m_hHtfEma invalid, in which case LoadSeries never rewrites them and
   // BuildHtfArrays would happily read the previous timeframe's bias.
   ResetState();
   // ResetState deliberately keeps m_n (Warmup needs it after LoadSeries), so the bar
   // count from the previous timeframe has to be cleared here.
   m_n = 0;
   m_lastError = "";
   m_lastLoadAttempt = 0;
   // Stale HTF bias must go too. A timeframe ABOVE the HTF leaves m_hHtfEma invalid, so
   // LoadSeries would never rewrite these arrays and BuildHtfArrays would read the
   // previous timeframe's prices as the current one's bias.
   ArrayResize(m_htfTime,  0);
   ArrayResize(m_htfClose, 0);
   ArrayResize(m_htfEma,   0);
   ArrayResize(m_htfBiasArr,  0);
   ArrayResize(m_htfValidArr, 0);

   m_hEmaF = iMA(m_symbol, m_tf, m_cfg.emaFastLen, 0, MODE_EMA, PRICE_CLOSE);
   m_hEmaM = iMA(m_symbol, m_tf, m_cfg.emaMidLen,  0, MODE_EMA, PRICE_CLOSE);
   m_hEmaS = iMA(m_symbol, m_tf, m_cfg.emaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   m_hRsi  = iRSI(m_symbol, m_tf, m_cfg.rsiLen, PRICE_CLOSE);
   m_hMacd = iMACD(m_symbol, m_tf, 12, 26, 9, PRICE_CLOSE);
   m_hAdx  = iADX(m_symbol, m_tf, m_cfg.adxLen);
   m_hAtr  = iATR(m_symbol, m_tf, m_cfg.atrLen);

   if(m_hEmaF == INVALID_HANDLE || m_hEmaM == INVALID_HANDLE ||
      m_hEmaS == INVALID_HANDLE || m_hRsi  == INVALID_HANDLE ||
      m_hMacd == INVALID_HANDLE || m_hAdx  == INVALID_HANDLE ||
      m_hAtr  == INVALID_HANDLE)
   {
      Print("AILens: indicator handle creation failed, err=", GetLastError());
      return false;
   }

   // HTF is only valid when it is strictly above the chart timeframe.
   if((int)m_cfg.htfTf > (int)m_tf)
      m_hHtfEma = iMA(m_symbol, m_cfg.htfTf, m_cfg.htfEmaLen, 0, MODE_EMA, PRICE_CLOSE);

   return true;
}

//------------------------------------------------------------------//
//  Load all series once, indexed by shift (0 = newest).            //
//                                                                  //
//  Two things make this more delicate than it looks:               //
//                                                                  //
//  1. Partial copies. Every array is resized as soon as it is      //
//     copied, so a failure halfway through would leave the engine  //
//     holding n-long arrays with a stale bar count. m_n is only    //
//     published after the last copy succeeds, so a failure leaves  //
//     the engine empty instead of reading past the end.            //
//                                                                  //
//  2. Retry cost. A caller in a tick loop retries every tick, and  //
//     re-copying ~15 arrays per tick is exactly what the Step gate  //
//     exists to avoid. Worse, hammering CopyBuffer while MT5 is    //
//     still calculating can restart the work and delay the data it  //
//     is waiting for. A short real-time throttle fixes both. It    //
//     uses GetTickCount(), never server time: server time freezes   //
//     when the market is closed, which is exactly when a late       //
//     attach happens.                                              //
//------------------------------------------------------------------//
#define AILENS_LOAD_RETRY_MS 500

bool CAILensCore::LoadSeries(const int want)
{
   if(m_lastLoadAttempt != 0 && (GetTickCount() - m_lastLoadAttempt) < AILENS_LOAD_RETRY_MS)
      return false;
   m_lastLoadAttempt = GetTickCount();

   // The builtin is Bars(symbol, tf). The accessor used to be named Bars() too,
   // which made MQL5 resolve the bare name to the member (method hiding) and fail.
   // The accessor is LoadedBars() now, so the two can never be confused again.
   int avail = Bars(m_symbol, m_tf);

   // Minimum that can actually be SCORED, not a raw bar count. WarmupBars() of context
   // must sit behind the oldest bar the engine evaluates, so loading exactly WarmupBars()
   // would leave essentially nothing scoreable: the engine would come up "live" and draw
   // an empty panel, the half-state a timeframe switch produces while the buffers are
   // still filling. MinBars() carries the extra margin; a single number keeps the gates
   // and the messages consistent.
   int minimum = MinBars();

   // Check the chart before the buffers. "Not enough chart history" and "the indicator
   // buffers are not ready" are different problems with different fixes, and reporting
   // the wrong one hides the real cause.
   if(avail < minimum)
   {
      m_lastError = StringFormat("chart history %d bars, need %d", avail, minimum);
      return false;
   }

   // CRITICAL: a handle is not a data source until MT5 has finished calculating it.
   // Right after iMA()/iRSI()/... are created - which is exactly what happens on every
   // timeframe switch, because OnInit creates a fresh core - BarsCalculated() is 0 or
   // small, and CopyBuffer for more bars than that returns FEWER than requested.
   //
   // The old code used `avail` (chart bars) as the copy count, so on a timeframe switch
   // it asked for thousands of buffer values that did not exist yet and failed every
   // single time, forever, while reporting "not enough history" - which was misleading:
   // the history was there, the indicator buffers were not.
   //
   // So the copyable window is the SMALLEST BarsCalculated among all handles, and
   // loading is simply retried until that window is big enough.
   int calc = BarsCalculated(m_hEmaF);
   int h;
   h = BarsCalculated(m_hEmaM); if(h < calc) calc = h;
   h = BarsCalculated(m_hEmaS); if(h < calc) calc = h;
   h = BarsCalculated(m_hRsi);  if(h < calc) calc = h;
   h = BarsCalculated(m_hMacd); if(h < calc) calc = h;
   h = BarsCalculated(m_hAdx);  if(h < calc) calc = h;
   h = BarsCalculated(m_hAtr);  if(h < calc) calc = h;

   if(calc <= 0)
   {
      m_lastError = (calc < 0
                     ? "indicator buffer unavailable (BarsCalculated returned -1)"
                     : "indicator buffers still calculating (0 bars ready)");
      return false;
   }

   // Only copy what BOTH the chart and every indicator buffer can provide.
   int usable = (calc < avail ? calc : avail);
   if(usable < minimum)
   {
      m_lastError = StringFormat("indicators calculated %d of %d bars (chart has %d)",
                                 usable, minimum, avail);
      return false;
   }

   int n = (want > 0 && want < usable ? want : usable);
   if(n < minimum)
      n = minimum;        // a too-small "want" is a misconfiguration, not a reason to stay dark

   // CopyBuffer/CopyTime fill arrays in chronological order by default (index 0 = oldest).
   // Every index in this file is a SHIFT (0 = current bar), so every destination array
   // must be marked as a series array first. Forgetting this silently reverses every
   // indicator read - the arrays still have the right contents, in the wrong order.
   //
   // m_n is cleared for the whole copy phase and published only at the very end.
   // CopyTime resizes the arrays to n as its first action, so if a later CopyBuffer
   // fails, the arrays are already n long while an older m_n could still be larger, and
   // every later read would index past the end. Zeroing it first makes the "no data"
   // state explicit: every reader is bounds-checked against m_n, so a failed load leaves
   // the engine safely empty until a later retry succeeds.
   m_n = 0;

   ArraySetAsSeries(m_time,  true);
   ArraySetAsSeries(m_open,  true);
   ArraySetAsSeries(m_high,  true);
   ArraySetAsSeries(m_low,   true);
   ArraySetAsSeries(m_close, true);
   ArraySetAsSeries(m_emaF,  true);
   ArraySetAsSeries(m_emaM,  true);
   ArraySetAsSeries(m_emaS,  true);
   ArraySetAsSeries(m_rsi,   true);
   ArraySetAsSeries(m_macd,  true);
   ArraySetAsSeries(m_sig,   true);
   ArraySetAsSeries(m_adx,   true);
   ArraySetAsSeries(m_dip,   true);
   ArraySetAsSeries(m_dim,   true);
   ArraySetAsSeries(m_atr,   true);

   // m_n is published only AFTER every copy succeeds. Setting it first would leave the
   // engine claiming N bars while the arrays hold none, and every later index would
   // read out of range.
   if(CopyTime(m_symbol, m_tf, 0, n, m_time) != n) { m_lastError = "CopyTime failed"; return false; }
   if(CopyOpen(m_symbol, m_tf, 0, n, m_open) != n) { m_lastError = "CopyOpen failed"; return false; }
   if(CopyHigh(m_symbol, m_tf, 0, n, m_high) != n) { m_lastError = "CopyHigh failed"; return false; }
   if(CopyLow (m_symbol, m_tf, 0, n, m_low ) != n) { m_lastError = "CopyLow failed";  return false; }
   if(CopyClose(m_symbol, m_tf, 0, n, m_close) != n) { m_lastError = "CopyClose failed"; return false; }
   ArraySetAsSeries(m_volRaw, true);
   if(CopyTickVolume(m_symbol, m_tf, 0, n, m_volRaw) != n) { m_lastError = "CopyTickVolume failed"; return false; }
   ArrayResize(m_vol, n);
   for(int i = 0; i < n; i++)
      m_vol[i] = (double)m_volRaw[i];

   if(CopyBuffer(m_hEmaF, 0, 0, n, m_emaF) != n) { m_lastError = "EMA fast buffer not ready"; return false; }
   if(CopyBuffer(m_hEmaM, 0, 0, n, m_emaM) != n) { m_lastError = "EMA mid buffer not ready";  return false; }
   if(CopyBuffer(m_hEmaS, 0, 0, n, m_emaS) != n) { m_lastError = "EMA slow buffer not ready"; return false; }
   if(CopyBuffer(m_hRsi,  0, 0, n, m_rsi ) != n) { m_lastError = "RSI buffer not ready";  return false; }
   if(CopyBuffer(m_hMacd, 0, 0, n, m_macd) != n) { m_lastError = "MACD main buffer not ready"; return false; }
   if(CopyBuffer(m_hMacd, 1, 0, n, m_sig ) != n) { m_lastError = "MACD signal buffer not ready"; return false; }
   if(CopyBuffer(m_hAdx,  0, 0, n, m_adx ) != n) { m_lastError = "ADX main buffer not ready"; return false; }
   if(CopyBuffer(m_hAdx,  1, 0, n, m_dip ) != n) { m_lastError = "ADX +DI buffer not ready"; return false; }
   if(CopyBuffer(m_hAdx,  2, 0, n, m_dim ) != n) { m_lastError = "ADX -DI buffer not ready"; return false; }
   if(CopyBuffer(m_hAtr,  0, 0, n, m_atr ) != n) { m_lastError = "ATR buffer not ready"; return false; }

   m_n = n;
   m_lastError = "";

   // ---- session VWAP, reset at each broker day change ----
   // Walk OLDEST -> NEWEST. In a series array the oldest bar is at index n-1 and the
   // newest at 0, which is what the loop below steps through.
   ArrayResize(m_vwap, n);
   double cumPV = 0.0, cumV = 0.0;
   MqlDateTime d;
   int prevDay = -1;
   for(int i = n - 1; i >= 0; i--)          // oldest -> newest
   {
      TimeToStruct(m_time[i], d);
      int dayKey = d.year * 10000 + d.mon * 100 + d.day;
      if(dayKey != prevDay)
      {
         prevDay = dayKey;
         cumPV = 0.0;
         cumV  = 0.0;
      }
      double typical = (m_high[i] + m_low[i] + m_close[i]) / 3.0;
      cumPV += typical * m_vol[i];
      cumV  += m_vol[i];
      m_vwap[i] = (cumV > 0.0 ? cumPV / cumV : EMPTY_VALUE);
   }

   // ---- previous day high / low ----
   // D1 data is loaded chronologically (oldest first), so the walk below can compare
   // day keys directly without any series flag on d1.
   MqlRates d1[];
   int gotD1 = CopyRates(m_symbol, PERIOD_D1, 0, 400, d1);
   ArrayResize(m_pdh, n);
   ArrayResize(m_pdl, n);
   for(int i = 0; i < n; i++)
   {
      m_pdh[i] = EMPTY_VALUE;
      m_pdl[i] = EMPTY_VALUE;
   }
   if(gotD1 > 1)
   {
      // For each chart bar, scan the D1 series from the end (newest first) to the first
      // COMPLETED day before that bar's day.
      for(int i = 0; i < n; i++)
      {
         TimeToStruct(m_time[i], d);
         int dayKey = d.year * 10000 + d.mon * 100 + d.day;
         for(int k = gotD1 - 1; k >= 0; k--)
         {
            MqlDateTime dd;
            TimeToStruct(d1[k].time, dd);
            int dk = dd.year * 10000 + dd.mon * 100 + dd.day;
            if(dk < dayKey)
            {
               m_pdh[i] = d1[k].high;
               m_pdl[i] = d1[k].low;
               break;
            }
         }
      }
   }

   // ---- HTF series ----
   // The HTF EMA handle has the same "not calculated yet" problem as the chart ones.
   // Not fatal: BuildHtfArrays() treats a short/empty HTF series as "bias unavailable",
   // and the score already handles that case (Redistribute or Neutral 10).
   if(m_hHtfEma != INVALID_HANDLE)
   {
      ArraySetAsSeries(m_htfTime,  true);
      ArraySetAsSeries(m_htfClose, true);
      ArraySetAsSeries(m_htfEma,   true);

      int htfCalc  = BarsCalculated(m_hHtfEma);
      int htfAvail = Bars(m_symbol, m_cfg.htfTf);
      int hn = 400;
      if(htfAvail < hn) hn = htfAvail;
      if(htfCalc  < hn) hn = htfCalc;          // copy only what actually exists

      if(hn > 5)
      {
         // Only accept a fully copied set; a partial copy would leave stale values in
         // the tail of the arrays and invent a bias for bars that have none.
         if(CopyTime  (m_symbol, m_cfg.htfTf, 0, hn, m_htfTime)  != hn ||
            CopyClose (m_symbol, m_cfg.htfTf, 0, hn, m_htfClose) != hn ||
            CopyBuffer(m_hHtfEma, 0, 0, hn, m_htfEma)            != hn)
         {
            ArrayResize(m_htfTime,  0);
            ArrayResize(m_htfClose, 0);
            ArrayResize(m_htfEma,   0);
         }
      }
      else
      {
         ArrayResize(m_htfTime,  0);
         ArrayResize(m_htfClose, 0);
         ArrayResize(m_htfEma,   0);
      }
   }

   // Precompute the per-bar HTF bias in one pass (see BuildHtfArrays).
   BuildHtfArrays();
   return true;
}

//------------------------------------------------------------------//
//  HTF bias precomputation.                                        //
//  Doing the search per bar per call is O(chartBars * htfBars),    //
//  which on 3000 x 400 is 1.2M iterations EVERY bar. It is computed //
//  once here instead: a single backward walk fills both arrays.     //
//------------------------------------------------------------------//
void CAILensCore::BuildHtfArrays(void)
{
   ArrayResize(m_htfBiasArr,  m_n);
   ArrayResize(m_htfValidArr, m_n);
   for(int i = 0; i < m_n; i++)
   {
      m_htfBiasArr[i]  = 0;
      m_htfValidArr[i] = false;
   }

   // HTF must be strictly above the chart timeframe, else the factor is unavailable.
   if((int)m_cfg.htfTf <= (int)m_tf)
      return;
   if(m_hHtfEma == INVALID_HANDLE)
      return;

   int hn = ArraySize(m_htfTime);
   if(hn < m_cfg.htfEmaLen + 3)
      return;

   // Both arrays are series (index 0 = newest), so walk from the newest chart bar
   // downward and advance the HTF pointer in lockstep.
   int h = 0;
   for(int i = 0; i < m_n; i++)          // i = chart shift, 0 -> oldest
   {
      datetime t = m_time[i];

      // advance while the HTF bar is still NEWER than this chart bar
      while(h < hn && m_htfTime[h] > t)
         h++;

      if(h >= hn)
         break;                          // no HTF bar left at or before this chart bar

      // h is now the newest HTF bar with time <= t. The [1] shift reads one further back.
      int use = h + 1;
      if(use >= hn)
         continue;
      if(m_htfEma[use] == EMPTY_VALUE || m_htfClose[use] == EMPTY_VALUE)
         continue;

      m_htfValidArr[i] = true;
      double c = m_htfClose[use];
      double e = m_htfEma[use];
      m_htfBiasArr[i] = (c > e ? 1 : (c < e ? -1 : 0));
   }
}

//------------------------------------------------------------------//
//  HTF bias lookup: O(1) via the precomputed arrays.               //
//------------------------------------------------------------------//
void CAILensCore::FillHtfBias(const int shift, bool &valid, int &bias) const
{
   valid = false;
   bias  = 0;
   if(shift < 0 || shift >= m_n)
      return;
   valid = m_htfValidArr[shift];
   bias  = m_htfBiasArr[shift];
}

//------------------------------------------------------------------//
//  Structure: confirmed pivots, value placed at the confirmation   //
//  bar exactly like Pine's ta.pivothigh/low.                       //
//------------------------------------------------------------------//
void CAILensCore::ComputePivots(const int shift)
{
   int L = m_cfg.swingLen;
   int center = shift + L;                       // pivot is L bars before confirmation
   if(center + L >= m_n)
      return;

   double vH = m_high[center];
   bool isHigh = true;
   for(int k = center - L; k <= center + L; k++)
   {
      if(k == center) continue;
      if(m_high[k] >= vH) { isHigh = false; break; }
   }
   if(isHigh)
   {
      m_swingH2 = m_swingH1;
      m_swingH1 = vH;
   }

   double vL = m_low[center];
   bool isLow = true;
   for(int k = center - L; k <= center + L; k++)
   {
      if(k == center) continue;
      if(m_low[k] <= vL) { isLow = false; break; }
   }
   if(isLow)
   {
      m_swingL2 = m_swingL1;
      m_swingL1 = vL;
   }

   if(m_swingH1 != EMPTY_VALUE && m_swingH2 != EMPTY_VALUE &&
      m_swingL1 != EMPTY_VALUE && m_swingL2 != EMPTY_VALUE)
   {
      if(m_swingH1 > m_swingH2 && m_swingL1 > m_swingL2)
         m_structBias = "BULLISH";
      else if(m_swingH1 < m_swingH2 && m_swingL1 < m_swingL2)
         m_structBias = "BEARISH";
      else
         m_structBias = "MIXED";
   }
}

//------------------------------------------------------------------//
//  Session gate. Broker time + offset = session clock.             //
//------------------------------------------------------------------//
bool CAILensCore::SessionOk(const datetime t, bool &inSession, string &label) const
{
   MqlDateTime d;
   TimeToStruct(t, d);

   int h = (d.hour + m_cfg.sesTzOffsetHours) % 24;
   if(h < 0) h += 24;
   int m = d.min;

   bool inA = m_cfg.tradeAsia   && AILens_InWindow(h, m_cfg.asiaStart,   m_cfg.asiaEnd);
   bool inL = m_cfg.tradeLondon && AILens_InWindow(h, m_cfg.londonStart, m_cfg.londonEnd);
   bool inN = m_cfg.tradeNy     && AILens_InWindow(h, m_cfg.nyStart,     m_cfg.nyEnd);

   bool readyA = inA && AILens_MinsSinceOpen(h, m, m_cfg.asiaStart)   >= m_cfg.sesBufferMin;
   bool readyL = inL && AILens_MinsSinceOpen(h, m, m_cfg.londonStart) >= m_cfg.sesBufferMin;
   bool readyN = inN && AILens_MinsSinceOpen(h, m, m_cfg.nyStart)     >= m_cfg.sesBufferMin;

   bool weekend = (d.day_of_week == 0 || d.day_of_week == 6);
   bool friLate = (m_cfg.blockFriLateHours > 0 && d.day_of_week == 5 &&
                   h >= m_cfg.nyEnd - m_cfg.blockFriLateHours);

   inSession = (readyA || readyL || readyN) && !weekend && !friLate;

   if(inL && inN)         label = "OVERLAP";
   else if(inL)           label = "LONDON";
   else if(inN)           label = "NY";
   else if(inA)           label = "ASIA";
   else if(weekend)       label = "CLOSED";
   else                   label = "OFF";

   return (m_cfg.useSessionFilter ? inSession : true);
}

//------------------------------------------------------------------//
//  Score for one side on one bar, with the same factor split as    //
//  the Pine file. Returns 0-100.                                   //
//------------------------------------------------------------------//
int CAILensCore::ScoreAt(const int shift, const int side,
                         int &fTrend, int &fMom, int &fStr,
                         int &fVol, int &fHtf) const
{
   fTrend = fMom = fStr = fVol = fHtf = 0;

   if(shift < 0 || shift >= m_n)
      return 0;

   double emaF = m_emaF[shift], emaM = m_emaM[shift], emaS = m_emaS[shift];
   double rsiV = m_rsi[shift], adxV = m_adx[shift];
   double diP  = m_dip[shift], diM  = m_dim[shift];
   double hist = (m_macd[shift] == EMPTY_VALUE || m_sig[shift] == EMPTY_VALUE
                  ? EMPTY_VALUE : m_macd[shift] - m_sig[shift]);
   double c = m_close[shift], o = m_open[shift];

   if(emaF == EMPTY_VALUE || emaM == EMPTY_VALUE || emaS == EMPTY_VALUE)
      return 0;

   bool bull = (c > o);
   bool bear = (c < o);

   // ---- trend: 7 + 7 + 6 ----
   if(side == 1)
   {
      fTrend += (emaF > emaM ? 7 : 0);
      fTrend += (emaM > emaS ? 7 : 0);
      fTrend += (c > emaF ? 6 : 0);
   }
   else
   {
      fTrend += (emaF < emaM ? 7 : 0);
      fTrend += (emaM < emaS ? 7 : 0);
      fTrend += (c < emaF ? 6 : 0);
   }

   // ---- momentum: 10/4 + 5 + 5 ----
   if(rsiV != EMPTY_VALUE)
   {
      if(side == 1 && rsiV > 50.0)
         fMom += (rsiV >= m_cfg.rsiOB ? 4 : 10);
      if(side == -1 && rsiV < 50.0)
         fMom += (rsiV <= m_cfg.rsiOS ? 4 : 10);
   }
   if(hist != EMPTY_VALUE && shift + 1 < m_n)
   {
      double histPrev = (m_macd[shift + 1] == EMPTY_VALUE || m_sig[shift + 1] == EMPTY_VALUE
                         ? EMPTY_VALUE : m_macd[shift + 1] - m_sig[shift + 1]);
      if(side == 1)
      {
         fMom += (hist > 0.0 ? 5 : 0);
         if(histPrev != EMPTY_VALUE) fMom += (hist > histPrev ? 5 : 0);
      }
      else
      {
         fMom += (hist < 0.0 ? 5 : 0);
         if(histPrev != EMPTY_VALUE) fMom += (hist < histPrev ? 5 : 0);
      }
   }

   // ---- strength: 10 + 10 ----
   if(diP != EMPTY_VALUE && diM != EMPTY_VALUE)
   {
      bool dom = (side == 1 ? diP > diM : diM > diP);
      fStr += (dom ? 10 : 0);
      if(dom && adxV != EMPTY_VALUE && adxV >= m_cfg.adxTrend)
         fStr += 10;
   }

   // ---- volume / participation: 20 / 12 / 6 ----
   bool volUsed = (m_cfg.volumeMode != "Neutralize");
   if(volUsed)
   {
      double part = EMPTY_VALUE;
      if(m_cfg.volumeMode == "Tick volume")
      {
         double sum = 0.0;
         int cnt = 0;
         for(int k = shift; k < m_n && cnt < m_cfg.volLen; k++, cnt++)
         {
            sum += m_vol[k];
         }
         if(cnt > 0 && sum / cnt > 0.0)
            part = m_vol[shift] / (sum / cnt);
      }
      else   // Range proxy
      {
         double sum = 0.0;
         int cnt = 0;
         for(int k = shift; k < m_n && cnt < m_cfg.volLen; k++, cnt++)
            sum += (m_high[k] - m_low[k]);
         if(cnt > 0 && sum / cnt > 0.0)
            part = (m_high[shift] - m_low[shift]) / (sum / cnt);
      }
      if(part != EMPTY_VALUE)
      {
         if(side == 1 && bull)
            fVol = (part >= 1.5 ? 20 : (part >= 1.0 ? 12 : 6));
         if(side == -1 && bear)
            fVol = (part >= 1.5 ? 20 : (part >= 1.0 ? 12 : 6));
      }
   }

   // ---- higher timeframe: 20 / 10 / 0 ----
   bool htfValid = false;
   int  htfBias  = 0;
   FillHtfBias(shift, htfValid, htfBias);

   bool grant = (!htfValid && m_cfg.htfUnavailable == "Neutral 10");
   if(htfValid)
   {
      if(side == 1) fHtf = (htfBias == 1 ? 20 : (htfBias == 0 ? 10 : 0));
      else          fHtf = (htfBias == -1 ? 20 : (htfBias == 0 ? 10 : 0));
   }
   else if(grant)
      fHtf = 10;

   // ---- composition ----
   int volMax = (volUsed ? 20 : 0);
   int htfMax = ((htfValid || grant) ? 20 : 0);
   int denom  = 60 + volMax + htfMax;
   double rescale = (denom > 0 ? 100.0 / denom : 1.0);

   int raw = fTrend + fMom + fStr + fVol + fHtf;
   int score = (int)MathRound(raw * rescale);
   if(score > 100) score = 100;
   return score;
}

//------------------------------------------------------------------//
double CAILensCore::StopFor(const double price, const int side,
                            const double atrV) const
{
   double chosen = (side == 1
                    ? price - m_cfg.stopAtr * atrV
                    : price + m_cfg.stopAtr * atrV);

   if(m_cfg.stopMode == "Structure (swing)")
   {
      double swing = (side == 1 ? m_swingL1 : m_swingH1);
      if(swing != EMPTY_VALUE)
      {
         double pad = 0.25 * atrV;
         double cand = (side == 1 ? swing - pad : swing + pad);
         double dist = (side == 1 ? price - cand : cand - price);
         bool okSide = (side == 1 ? cand < price : cand > price);
         if(okSide && dist <= m_cfg.maxStopAtr * atrV)
            chosen = cand;
      }
   }
   return chosen;
}

//------------------------------------------------------------------//
void CAILensCore::OpenTrade(const int shift, const int side, const double atrV)
{
   double price = m_close[shift];
   double stop  = StopFor(price, side, atrV);
   double risk  = (side == 1 ? price - stop : stop - price);

   m_trade.side       = side;
   m_trade.sideStr    = (side == 1 ? "LONG" : "SHORT");
   m_trade.entry      = price;
   m_trade.stop       = stop;
   m_trade.stop0      = stop;
   m_trade.risk       = risk;
   m_trade.t1         = (side == 1 ? price + m_cfg.t1R * risk : price - m_cfg.t1R * risk);
   m_trade.t2         = (side == 1 ? price + m_cfg.t2R * risk : price - m_cfg.t2R * risk);
   m_trade.bar        = shift;              // display value only; see entryTime
   m_trade.entryTime  = m_time[shift];
   m_trade.status     = "ACTIVE";
   m_trade.t1Taken    = false;
   m_trade.beMoved    = false;
   m_trade.partial    = 0.0;
   m_trade.realizedR  = 0.0;
   m_trade.peakR      = 0.0;
   m_trade.runHigh    = (side == 1 ? price : EMPTY_VALUE);
   m_trade.runLow     = (side == -1 ? price : EMPTY_VALUE);
   m_trade.stopModeUsed = m_cfg.stopMode;

   m_lastSigTime  = m_time[shift];
   m_lastSigSide  = m_trade.sideStr;
}

//------------------------------------------------------------------//
//  Trade management with this bar's range. Stop is checked first,  //
//  which is the conservative order Pine uses.                      //
//------------------------------------------------------------------//
void CAILensCore::ManageTrade(const int shift)
{
   if(m_trade.side == 0)
      return;
   // Do not manage on the entry bar itself. Compare TIMES: the stored shift is
   // meaningless the moment a new bar arrives and renumbers everything.
   if(m_time[shift] <= m_trade.entryTime)
      return;

   double hi = m_high[shift], lo = m_low[shift], cl = m_close[shift];
   double part = m_cfg.partialT1Pct / 100.0;

   if(m_trade.side == 1)
   {
      m_trade.runHigh = (m_trade.runHigh == EMPTY_VALUE
                         ? MathMax(hi, m_trade.entry)
                         : MathMax(m_trade.runHigh, hi));
      if(m_trade.risk > 0.0)
         m_trade.peakR = MathMax(m_trade.peakR, (hi - m_trade.entry) / m_trade.risk);

      if(lo <= m_trade.stop)
      {
         double rExit = (m_trade.risk > 0.0 ? (m_trade.stop - m_trade.entry) / m_trade.risk : 0.0);
         m_trade.realizedR += (m_trade.t1Taken ? 1.0 - m_trade.partial : 1.0) * rExit;
         m_trade.status = (!m_trade.t1Taken ? "STOPPED"
                          : (m_trade.stop > m_trade.entry ? "TRAIL_STOP" : "STOPPED_AFTER_T1"));
         m_trade.side = 0;
         return;
      }
      if(hi >= m_trade.t2)
      {
         if(m_trade.t1Taken)
            m_trade.realizedR += (1.0 - m_trade.partial) * m_cfg.t2R;
         else
         {
            m_trade.realizedR += part * m_cfg.t1R + (1.0 - part) * m_cfg.t2R;
            m_trade.t1Taken = true;
            m_trade.partial  = part;
         }
         m_trade.status = "TARGET_2_HIT";
         m_trade.side = 0;
         return;
      }
      if(!m_trade.t1Taken && hi >= m_trade.t1)
      {
         m_trade.t1Taken = true;
         m_trade.partial = part;
         m_trade.realizedR += m_trade.partial * m_cfg.t1R;
         m_trade.status = "TARGET_1_HIT";
         if(m_cfg.moveBeAfterT1)
         {
            m_trade.stop = MathMax(m_trade.stop, m_trade.entry);
            m_trade.beMoved = true;
         }
         if(m_trade.partial >= 1.0)
         {
            m_trade.status = "PARTIAL_FULL_EXIT";
            m_trade.side = 0;
            return;
         }
      }
      if(m_cfg.useTrailing && (m_cfg.trailFromStart || m_trade.t1Taken) &&
         m_trade.runHigh != EMPTY_VALUE)
      {
         double trailL = m_trade.runHigh - m_cfg.trailAtr * m_atr[shift];
         m_trade.stop = MathMax(m_trade.stop, trailL);
      }
   }
   else
   {
      m_trade.runLow = (m_trade.runLow == EMPTY_VALUE
                        ? MathMin(lo, m_trade.entry)
                        : MathMin(m_trade.runLow, lo));
      if(m_trade.risk > 0.0)
         m_trade.peakR = MathMax(m_trade.peakR, (m_trade.entry - lo) / m_trade.risk);

      if(hi >= m_trade.stop)
      {
         double rExit = (m_trade.risk > 0.0 ? (m_trade.entry - m_trade.stop) / m_trade.risk : 0.0);
         m_trade.realizedR += (m_trade.t1Taken ? 1.0 - m_trade.partial : 1.0) * rExit;
         m_trade.status = (!m_trade.t1Taken ? "STOPPED"
                          : (m_trade.stop < m_trade.entry ? "TRAIL_STOP" : "STOPPED_AFTER_T1"));
         m_trade.side = 0;
         return;
      }
      if(lo <= m_trade.t2)
      {
         if(m_trade.t1Taken)
            m_trade.realizedR += (1.0 - m_trade.partial) * m_cfg.t2R;
         else
         {
            m_trade.realizedR += part * m_cfg.t1R + (1.0 - part) * m_cfg.t2R;
            m_trade.t1Taken = true;
            m_trade.partial  = part;
         }
         m_trade.status = "TARGET_2_HIT";
         m_trade.side = 0;
         return;
      }
      if(!m_trade.t1Taken && lo <= m_trade.t1)
      {
         m_trade.t1Taken = true;
         m_trade.partial = part;
         m_trade.realizedR += m_trade.partial * m_cfg.t1R;
         m_trade.status = "TARGET_1_HIT";
         if(m_cfg.moveBeAfterT1)
         {
            m_trade.stop = MathMin(m_trade.stop, m_trade.entry);
            m_trade.beMoved = true;
         }
         if(m_trade.partial >= 1.0)
         {
            m_trade.status = "PARTIAL_FULL_EXIT";
            m_trade.side = 0;
            return;
         }
      }
      if(m_cfg.useTrailing && (m_cfg.trailFromStart || m_trade.t1Taken) &&
         m_trade.runLow != EMPTY_VALUE)
      {
         double trailS = m_trade.runLow + m_cfg.trailAtr * m_atr[shift];
         m_trade.stop = MathMin(m_trade.stop, trailS);
      }
   }

   // ---- time stop ----
   if(m_cfg.maxBarsInTrade > 0 && m_trade.status == "ACTIVE" &&
      (ShiftOfTime(m_trade.entryTime) - shift) >= m_cfg.maxBarsInTrade)
   {
      double rExit = (m_trade.risk > 0.0
                      ? (m_trade.side == 1 ? (cl - m_trade.entry) / m_trade.risk
                                           : (m_trade.entry - cl) / m_trade.risk)
                      : 0.0);
      m_trade.realizedR += (m_trade.t1Taken ? 1.0 - m_trade.partial : 1.0) * rExit;
      m_trade.status = "TIME_STOP";
      m_trade.side = 0;
   }
}

//------------------------------------------------------------------//
//  Warmup: replay every closed bar, oldest first, so the state     //
//  matches what a full backtest would produce.                     //
//------------------------------------------------------------------//
bool CAILensCore::Warmup(const int maxBars)
{
   if(!LoadSeries(maxBars))
      return false;

   ResetState();

   int warm = WarmupBars();

   // One chronological pass. `lastIndex` is the newest closed bar, which is what the
   // engine should treat as "current".
   int lastIndex = m_n - 1;
   for(int shift = m_n - 1; shift >= 1; shift--)
   {
      if(shift > lastIndex - warm)       // not enough history behind this bar yet
         continue;
      StepBar(shift);
   }

   m_lastBarTime = m_time[1];            // the newest CLOSED bar
   m_formingTime = m_time[0];            // the bar still forming
   return true;
}

//------------------------------------------------------------------//
//  ResetState: everything that has to be cleared before a replay.  //
//------------------------------------------------------------------//
void CAILensCore::ResetState(void)
{
   m_trade.side      = 0;
   m_trade.status    = "NONE";
   m_trade.sideStr   = "NONE";
   m_trade.entry     = 0.0;
   m_trade.stop      = 0.0;
   m_trade.stop0     = 0.0;
   m_trade.risk      = 0.0;
   m_trade.t1        = 0.0;
   m_trade.t2        = 0.0;
   m_trade.realizedR = 0.0;
   m_trade.peakR     = 0.0;
   m_trade.t1Taken   = false;
   m_trade.beMoved   = false;
   m_trade.partial   = 0.0;
   m_trade.runHigh   = EMPTY_VALUE;
   m_trade.runLow    = EMPTY_VALUE;

   m_lastSigTime  = 0;
   m_lastSigSide  = "NONE";
   m_swingH1 = m_swingH2 = m_swingL1 = m_swingL2 = EMPTY_VALUE;
   m_structBias   = "MIXED";
   m_lastBarTime  = 0;
   m_formingTime  = 0;
}

//------------------------------------------------------------------//
//  WarmupBars: how many bars the indicators need before a bar can  //
//  be evaluated. Bars older than this are skipped during a replay.  //
//------------------------------------------------------------------//
int CAILensCore::WarmupBars(void) const
{
   return m_cfg.emaSlowLen + m_cfg.atrPctLen + m_cfg.swingLen * 2 + 5;
}

//------------------------------------------------------------------//
//  MinBars: smallest chart size that still lets the newest closed   //
//  bar be scored. Anything less would leave the engine "loaded" with //
//  nothing it can evaluate. Must match the gate in LoadSeries.       //
//------------------------------------------------------------------//
int CAILensCore::MinBars(void) const
{
   // WarmupBars() of context, plus the forming bar, plus the newest closed bar, plus a
   // few spare bars so the newest closed bar is genuinely scoreable rather than the only
   // one. Using one number for "can start" everywhere (gates and messages) keeps the log
   // honest about what the engine actually waits for.
   return WarmupBars() + 6;
}

//------------------------------------------------------------------//
//  Publish the per-bar output struct.                              //
//------------------------------------------------------------------//
void CAILensCore::Publish(const int shift, const string eventStr,
                          const string regime, const int regimeCode,
                          const bool inSession, const string sesLabel,
                          const string structEvent,
                          const int longScore, const int shortScore,
                          const int lT, const int lM, const int lS, const int lV, const int lH,
                          const int sT, const int sM, const int sS, const int sV, const int sH,
                          const double atrPct)
{
   bool htfValid = false;
   int  htfBias  = 0;
   FillHtfBias(shift, htfValid, htfBias);

   bool volUsed = (m_cfg.volumeMode != "Neutralize");
   bool grant = (!htfValid && m_cfg.htfUnavailable == "Neutral 10");

   m_out.longScore  = longScore;
   m_out.shortScore = shortScore;
   m_out.regime     = regime;
   m_out.regimeCode = regimeCode;
   m_out.inSession  = inSession;
   m_out.sesLabel   = sesLabel;
   m_out.structBias = m_structBias;
   m_out.structEvent = structEvent;

   m_out.lTrend = lT; m_out.lMom = lM; m_out.lStr = lS; m_out.lVol = lV; m_out.lHtf = lH;
   m_out.sTrend = sT; m_out.sMom = sM; m_out.sStr = sS; m_out.sVol = sV; m_out.sHtf = sH;

   m_out.denom = 60 + (volUsed ? 20 : 0) + ((htfValid || grant) ? 20 : 0);
   m_out.rescale = (m_out.denom > 0 ? 100.0 / m_out.denom : 1.0);
   m_out.activeFactors = 3 + (volUsed ? 1 : 0) + ((htfValid || grant) ? 1 : 0);

   m_out.htfValid = htfValid;
   m_out.htfBias  = htfBias;
   m_out.htfBiasStr = (!htfValid ? "N/A" : (htfBias == 1 ? "UP" : (htfBias == -1 ? "DOWN" : "FLAT")));

   m_out.emaF = m_emaF[shift];
   m_out.emaM = m_emaM[shift];
   m_out.emaS = m_emaS[shift];
   m_out.rsiV = m_rsi[shift];
   m_out.adxV = m_adx[shift];
   m_out.diPlus = m_dip[shift];
   m_out.diMinus = m_dim[shift];
   m_out.macdHist = (m_macd[shift] == EMPTY_VALUE || m_sig[shift] == EMPTY_VALUE
                     ? EMPTY_VALUE : m_macd[shift] - m_sig[shift]);
   m_out.atrV = m_atr[shift];
   m_out.atrPct = atrPct;
   m_out.vwapV = m_vwap[shift];
   m_out.pdh = m_pdh[shift];
   m_out.pdl = m_pdl[shift];
   m_out.relVol = EMPTY_VALUE;
   m_out.relRng = EMPTY_VALUE;

   m_out.eventStr   = eventStr;
   m_out.tradeSide  = m_trade.side;
   m_out.tradeStatus = m_trade.status;
   m_out.entry = m_trade.entry;
   m_out.stop  = m_trade.stop;
   m_out.t1    = m_trade.t1;
   m_out.t2    = m_trade.t2;
   m_out.realizedR = m_trade.realizedR;
   m_out.openR = (m_trade.side != 0 && m_trade.risk > 0.0
                  ? (m_trade.side == 1 ? (m_close[shift] - m_trade.entry) / m_trade.risk
                                       : (m_trade.entry - m_close[shift]) / m_trade.risk)
                  : EMPTY_VALUE);
}

//------------------------------------------------------------------//
//  Process ONE closed bar.                                         //
//------------------------------------------------------------------//
void CAILensCore::StepBar(const int shift)
{
   ComputePivots(shift);

   double atrV = m_atr[shift];
   if(atrV == EMPTY_VALUE || atrV <= 0.0)
      return;

   int lT=0, lM=0, lS=0, lV=0, lH=0;
   int sT=0, sM=0, sS=0, sV=0, sH=0;
   int longScore  = ScoreAt(shift,  1, lT, lM, lS, lV, lH);
   int shortScore = ScoreAt(shift, -1, sT, sM, sS, sV, sH);

   // Separate variables for the previous bar: reusing the same refs would overwrite
   // the current bar's factor split, which the panel and the EA both report.
   int pT=0, pM=0, pS=0, pV=0, pH=0;
   int prevLong  = (shift + 1 < m_n ? ScoreAt(shift + 1,  1, pT, pM, pS, pV, pH) : 0);
   int prevShort = (shift + 1 < m_n ? ScoreAt(shift + 1, -1, pT, pM, pS, pV, pH) : 0);

   // ---- regime ----
   double emaS = m_emaS[shift];
   int slopeShift = shift + m_cfg.slopeLen;
   bool slopeOk = (emaS != EMPTY_VALUE && slopeShift < m_n && m_emaS[slopeShift] != EMPTY_VALUE);
   bool trendUp = false, trendDn = false;
   if(slopeOk)
   {
      bool adxEnough = (m_adx[shift] != EMPTY_VALUE && m_adx[shift] >= m_cfg.adxTrend);
      trendUp = (m_close[shift] > emaS && emaS > m_emaS[slopeShift] && adxEnough);
      trendDn = (m_close[shift] < emaS && emaS < m_emaS[slopeShift] && adxEnough);
   }

   // ATR percentile over the trailing window
   double atrPct = EMPTY_VALUE;
   {
      double cur = m_atr[shift];
      int cnt = 0, below = 0;
      for(int k = shift; k < m_n && cnt < m_cfg.atrPctLen; k++, cnt++)
      {
         double v = m_atr[k];
         if(v == EMPTY_VALUE) continue;
         if(k != shift && v < cur) below++;
      }
      if(cnt > 1)
         atrPct = 100.0 * below / (double)(cnt - 1);
   }
   bool highVol = (atrPct != EMPTY_VALUE && atrPct >= m_cfg.highVolPct);

   string regime = (highVol ? "HIGH_VOLATILITY"
                            : (trendUp ? "TREND_UP" : (trendDn ? "TREND_DOWN" : "RANGE")));
   int regimeCode = (highVol ? 2 : (trendUp ? 1 : (trendDn ? -1 : 0)));

   // ---- session ----
   bool inSession = false;
   string sesLabel = "OFF";
   bool sessOk = SessionOk(m_time[shift], inSession, sesLabel);

   // ---- structure event ----
   string structEvent = "NONE";
   if(m_swingH1 != EMPTY_VALUE && shift + 1 < m_n &&
      m_close[shift] > m_swingH1 && m_close[shift + 1] <= m_swingH1)
      structEvent = "BREAK_UP";
   else if(m_swingL1 != EMPTY_VALUE && shift + 1 < m_n &&
      m_close[shift] < m_swingL1 && m_close[shift + 1] >= m_swingL1)
      structEvent = "BREAK_DOWN";

   bool htfValid = false;
   int  htfBias  = 0;
   FillHtfBias(shift, htfValid, htfBias);

   // ---- entry gates ----
   bool htfLongOk  = (!m_cfg.requireHtfAlign || htfBias >= 0);
   bool htfShortOk = (!m_cfg.requireHtfAlign || htfBias <= 0);
   bool adxOk      = (m_adx[shift] != EMPTY_VALUE && m_adx[shift] >= m_cfg.minAdxEntry);

   double emaF = m_emaF[shift];
   double extAtr = (emaF != EMPTY_VALUE && atrV > 0.0 ? (m_close[shift] - emaF) / atrV : 0.0);
   bool noChaseL = (extAtr <= m_cfg.maxExtAtr);
   bool noChaseS = (-extAtr <= m_cfg.maxExtAtr);

   // Cooldown measured on the bar grid via TIME, never on the stored shift.
   bool cooldownOk = true;
   if(m_lastSigTime > 0)
   {
      int lastSigShift = ShiftOfTime(m_lastSigTime);
      cooldownOk = (lastSigShift < 0 || (lastSigShift - shift) >= m_cfg.minBarsBetween);
   }

   bool structLongOk, structShortOk;
   if(m_cfg.structGate == "Off")
   {
      structLongOk = true;  structShortOk = true;
   }
   else if(m_cfg.structGate == "Require aligned")
   {
      structLongOk  = (m_structBias == "BULLISH");
      structShortOk = (m_structBias == "BEARISH");
   }
   else   // Block opposite
   {
      structLongOk  = (m_structBias != "BEARISH");
      structShortOk = (m_structBias != "BULLISH");
   }

   bool longCond = (longScore >= m_cfg.scoreThreshold && prevLong < m_cfg.scoreThreshold &&
                    regime != "TREND_DOWN" &&
                    !(m_cfg.blockHighVol && regime == "HIGH_VOLATILITY") &&
                    htfLongOk && adxOk && noChaseL && cooldownOk && structLongOk && sessOk);
   bool shortCond = (shortScore >= m_cfg.scoreThreshold && prevShort < m_cfg.scoreThreshold &&
                     regime != "TREND_UP" &&
                     !(m_cfg.blockHighVol && regime == "HIGH_VOLATILITY") &&
                     htfShortOk && adxOk && noChaseS && cooldownOk && structShortOk && sessOk);

   // ---- manage, then open ----
   string statusBefore = m_trade.status;
   double realizedBefore = m_trade.realizedR;
   ManageTrade(shift);

   string eventStr = "BAR_CLOSE";
   bool openedLong = false, openedShort = false;

   if(longCond && !shortCond && m_trade.side != 1)
   {
      OpenTrade(shift, 1, atrV);
      openedLong = true;
      eventStr = "LONG_SETUP";
   }
   else if(shortCond && !longCond && m_trade.side != -1)
   {
      OpenTrade(shift, -1, atrV);
      openedShort = true;
      eventStr = "SHORT_SETUP";
   }
   else if((m_trade.status != statusBefore || m_trade.realizedR != realizedBefore) &&
           !openedLong && !openedShort)
      eventStr = "TRADE_UPDATE";


   Publish(shift, eventStr, regime, regimeCode, inSession, sesLabel, structEvent,
           longScore, shortScore, lT, lM, lS, lV, lH, sT, sM, sS, sV, sH, atrPct);
}

//------------------------------------------------------------------//
//  Inspect: report the score composition of one bar without         //
//  mutating trade state. The indicator uses this so the panel can   //
//  show the bar under the cursor, not only the live one.            //
//------------------------------------------------------------------//
bool CAILensCore::Inspect(const int shift)
{
   if(shift < 0 || shift >= m_n)
      return false;
   if(m_atr[shift] == EMPTY_VALUE || m_atr[shift] <= 0.0)
      return false;

   int lT=0, lM=0, lS=0, lV=0, lH=0;
   int sT=0, sM=0, sS=0, sV=0, sH=0;
   int longScore  = ScoreAt(shift,  1, lT, lM, lS, lV, lH);
   int shortScore = ScoreAt(shift, -1, sT, sM, sS, sV, sH);

   // ATR percentile, same window as StepBar.
   double atrPct = EMPTY_VALUE;
   {
      double cur = m_atr[shift];
      int cnt = 0, below = 0;
      for(int k = shift; k < m_n && cnt < m_cfg.atrPctLen; k++, cnt++)
      {
         double v = m_atr[k];
         if(v == EMPTY_VALUE) continue;
         if(k != shift && v < cur) below++;
      }
      if(cnt > 1)
         atrPct = 100.0 * below / (double)(cnt - 1);
   }

   double emaS = m_emaS[shift];
   int slopeShift = shift + m_cfg.slopeLen;
   bool slopeOk = (emaS != EMPTY_VALUE && slopeShift < m_n && m_emaS[slopeShift] != EMPTY_VALUE);
   bool adxEnough = (m_adx[shift] != EMPTY_VALUE && m_adx[shift] >= m_cfg.adxTrend);
   bool trendUp = (slopeOk && m_close[shift] > emaS && emaS > m_emaS[slopeShift] && adxEnough);
   bool trendDn = (slopeOk && m_close[shift] < emaS && emaS < m_emaS[slopeShift] && adxEnough);
   bool highVol = (atrPct != EMPTY_VALUE && atrPct >= m_cfg.highVolPct);
   string regime = (highVol ? "HIGH_VOLATILITY"
                            : (trendUp ? "TREND_UP" : (trendDn ? "TREND_DOWN" : "RANGE")));
   int regimeCode = (highVol ? 2 : (trendUp ? 1 : (trendDn ? -1 : 0)));

   bool inSession = false;
   string sesLabel = "OFF";
   SessionOk(m_time[shift], inSession, sesLabel);

   string structEvent = "NONE";
   if(m_swingH1 != EMPTY_VALUE && shift + 1 < m_n &&
      m_close[shift] > m_swingH1 && m_close[shift + 1] <= m_swingH1)
      structEvent = "BREAK_UP";
   else if(m_swingL1 != EMPTY_VALUE && shift + 1 < m_n &&
      m_close[shift] < m_swingL1 && m_close[shift + 1] >= m_swingL1)
      structEvent = "BREAK_DOWN";

   Publish(shift, "BAR_CLOSE", regime, regimeCode, inSession, sesLabel, structEvent,
           longScore, shortScore, lT, lM, lS, lV, lH, sT, sM, sS, sV, sH, atrPct);
   return true;
}

//------------------------------------------------------------------//
//  ShiftOfTime: binary search for a bar time in the series array.   //
//  Returns -1 when the time is not in the loaded window.            //
//------------------------------------------------------------------//
int CAILensCore::ShiftOfTime(const datetime t) const
{
   int lo = 0, hi = m_n - 1;
   while(lo <= hi)
   {
      int mid = (lo + hi) >> 1;   // integer midpoint; / on ints is fine but this is unambiguous
      if(m_time[mid] == t) return mid;
      if(m_time[mid] <  t) hi = mid - 1;    // series: newer times at lower indices
      else                 lo = mid + 1;
   }
   return -1;
}

//------------------------------------------------------------------//
//  Step: process bars that closed since the last call.             //
//                                                                  //
//  Progress is tracked by BAR TIME, not by shift. A shift is a     //
//  position in a moving window: the moment one new bar arrives,    //
//  every shift is renumbered and shift-based bookkeeping re-reads  //
//  the same bars forever while skipping others. Time never moves.  //
//------------------------------------------------------------------//
bool CAILensCore::Step(void)
{
   // CHEAP GATE, and the reason this EA is usable in the Strategy Tester.
   // OnTick fires on every tick, and a tick loop can run thousands of times per bar.
   // LoadSeries copies ~15 arrays of a few thousand bars; doing that per tick would
   // make a one-year tester run take days. iTime(...,0) is a single lookup, and if the
   // forming bar has not changed since the last successful load, no bar has closed and
   // there is nothing at all to do.
   //
   // The gate keys off m_formingTime, which LoadSeries never touches on a failed attempt,
   // so a retry costs nothing until the forming bar actually rolls over. That is the
   // property that keeps this cheap under a tick storm, and it survives the failure path.
   if(m_formingTime != 0)
   {
      datetime forming = iTime(m_symbol, m_tf, 0);
      if(forming == 0)                 // history not ready yet
         return false;
      if(forming == m_formingTime)
         return false;
   }

   if(!LoadSeries(m_n > 0 ? m_n : 0))
   {
      // Clear the gate so the next tick retries (LoadSeries throttles itself to twice a
      // second). Without this, one transient CopyBuffer failure during a new bar would
      // keep the gate closed until the bar AFTER it formed, delaying the alert for the
      // bar that just closed - which is the one signal that matters.
      m_formingTime = 0;
      return false;
   }

   m_formingTime = m_time[0];

   // The first CLOSED bar we have not processed yet. m_time[0] is the forming bar.
   int newestClosed = 1;
   int startShift = -1;

   if(m_lastBarTime == 0)
      startShift = m_n - 1;                 // nothing processed: full replay
   else
   {
      // find the last processed bar; everything older than it is new
      int lastDone = ShiftOfTime(m_lastBarTime);
      if(lastDone < 0)
         startShift = m_n - 1;              // it fell out of the window: full replay
      else if(lastDone <= newestClosed)
         return false;                      // no new closed bar yet
      else
         startShift = lastDone - 1;
   }

   int warm = WarmupBars();
   bool advanced = false;

   for(int shift = startShift; shift >= newestClosed; shift--)
   {
      if(shift > m_n - 1 - warm)
         continue;                          // not enough history behind this bar
      StepBar(shift);
      advanced = true;
   }

   if(advanced)
      m_lastBarTime = m_time[newestClosed];
   return advanced;
}

#endif // __AILENS_MQH__
