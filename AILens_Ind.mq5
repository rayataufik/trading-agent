//+------------------------------------------------------------------+
//|  AILens_Ind.mq5                                                   |
//|  AI Agent Lens - MT5 indicator (visual readout).                  |
//|                                                                   |
//|  This file draws. It contains NO strategy logic: every number it  |
//|  shows comes from AILens.mqh, the same file the EA includes.      |
//|  That is what makes the chart and the signals impossible to       |
//|  disagree.                                                        |
//+------------------------------------------------------------------+
#property copyright "AI Agent Lens"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0        // everything is drawn with objects

#include "AILens.mqh"

//==================================================================//
//  INPUTS                                                          //
//==================================================================//
input group "Signals"
input int    InpScoreThreshold   = 70;      // Setup score threshold
input bool   InpBlockHighVol     = true;    // Block setups in HIGH_VOLATILITY
input ENUM_TIMEFRAMES InpHtfTf   = PERIOD_H4; // Higher timeframe
input int    InpHtfEmaLen        = 50;      // Higher timeframe EMA length
input bool   InpRequireHtfAlign  = true;    // Require HTF alignment
input double InpMinAdxEntry      = 20.0;    // Minimum ADX to enter
input double InpMaxExtAtr        = 1.5;     // Anti-chase: max distance from fast EMA (xATR)
input int    InpMinBarsBetween   = 6;       // Cooldown between setups (bars)
input string InpStructGate       = "Off";   // Market structure gate
input string InpHtfUnavailable   = "Redistribute"; // When HTF data is unavailable

input group "Trend and momentum"
input int    InpEmaFastLen       = 20;
input int    InpEmaMidLen        = 50;
input int    InpEmaSlowLen       = 200;
input int    InpSlopeLen         = 5;
input int    InpRsiLen           = 14;
input double InpRsiOB            = 75.0;
input double InpRsiOS            = 25.0;
input int    InpAdxLen           = 14;
input double InpAdxTrend         = 20.0;

input group "Volume and volatility"
input int    InpVolLen           = 20;
input int    InpAtrLen           = 14;
input int    InpAtrPctLen        = 100;
input double InpHighVolPct       = 90.0;
input string InpVolumeMode       = "Range proxy";  // Tick volume | Range proxy | Neutralize

input group "Structure"
input int    InpSwingLen         = 5;

input group "Risk and exits"
input double InpStopAtr          = 2.0;
input string InpStopMode         = "ATR";   // ATR | Structure (swing)
input double InpMaxStopAtr       = 2.5;
input double InpT1R              = 1.0;
input double InpT2R              = 2.0;
input double InpPartialT1Pct     = 0.0;
input bool   InpMoveBeAfterT1    = false;
input bool   InpUseTrailing      = false;
input double InpTrailAtr         = 1.5;
input bool   InpTrailFromStart   = false;
input int    InpMaxBarsInTrade   = 0;

input group "Session filter"
input bool   InpUseSessionFilter = true;
input int    InpSesTzOffsetHours = 0;       // Session clock offset from broker time (hours)
input bool   InpTradeAsia        = false;
input int    InpAsiaStart        = 0;
input int    InpAsiaEnd          = 8;
input bool   InpTradeLondon      = true;
input int    InpLondonStart      = 7;
input int    InpLondonEnd        = 16;
input bool   InpTradeNy          = true;
input int    InpNyStart          = 12;
input int    InpNyEnd            = 21;
input int    InpSesBufferMin     = 15;
input int    InpBlockFriLateHours = 3;

input group "Display"
input bool   InpShowPanel        = true;
input bool   InpShowLevels       = true;
input int    InpMaxBarsToDraw    = 3000;    // Bars to load and draw

//==================================================================//
//  GLOBALS                                                         //
//==================================================================//
CAILensCore g_core;
SAILensConfig g_cfg;
bool g_ready = false;
datetime g_lastBarTime = 0;

// object name prefix, so removal can never touch the user's own objects
#define PFX "AIL_"

//==================================================================//
string TfStr(ENUM_TIMEFRAMES tf) { return AILens_TfToString(tf); }

//------------------------------------------------------------------//
SAILensConfig BuildConfig(void)
{
   SAILensConfig c;
   // Every field is assigned below, so no ZeroMemory (illegal on structs with strings).
   c.structGate = InpStructGate;
   c.htfUnavailable = InpHtfUnavailable;
   c.volumeMode = InpVolumeMode;
   c.stopMode = InpStopMode;

   c.scoreThreshold   = InpScoreThreshold;
   c.blockHighVol     = InpBlockHighVol;
   c.htfTf            = InpHtfTf;
   c.htfEmaLen        = InpHtfEmaLen;
   c.requireHtfAlign  = InpRequireHtfAlign;
   c.minAdxEntry      = InpMinAdxEntry;
   c.maxExtAtr        = InpMaxExtAtr;
   c.minBarsBetween   = InpMinBarsBetween;
   c.structGate       = InpStructGate;
   c.htfUnavailable   = InpHtfUnavailable;

   c.emaFastLen       = InpEmaFastLen;
   c.emaMidLen        = InpEmaMidLen;
   c.emaSlowLen       = InpEmaSlowLen;
   c.slopeLen         = InpSlopeLen;
   c.rsiLen           = InpRsiLen;
   c.rsiOB            = InpRsiOB;
   c.rsiOS            = InpRsiOS;
   c.adxLen           = InpAdxLen;
   c.adxTrend         = InpAdxTrend;

   c.volLen           = InpVolLen;
   c.atrLen           = InpAtrLen;
   c.atrPctLen        = InpAtrPctLen;
   c.highVolPct       = InpHighVolPct;
   c.volumeMode       = InpVolumeMode;

   c.swingLen         = InpSwingLen;

   c.stopAtr          = InpStopAtr;
   c.stopMode         = InpStopMode;
   c.maxStopAtr       = InpMaxStopAtr;
   c.t1R              = InpT1R;
   c.t2R              = InpT2R;
   c.partialT1Pct     = InpPartialT1Pct;
   c.moveBeAfterT1    = InpMoveBeAfterT1;
   c.useTrailing      = InpUseTrailing;
   c.trailAtr         = InpTrailAtr;
   c.trailFromStart   = InpTrailFromStart;
   c.maxBarsInTrade   = InpMaxBarsInTrade;

   c.useSessionFilter = InpUseSessionFilter;
   c.sesTzOffsetHours = InpSesTzOffsetHours;
   c.tradeAsia        = InpTradeAsia;
   c.asiaStart        = InpAsiaStart;
   c.asiaEnd          = InpAsiaEnd;
   c.tradeLondon      = InpTradeLondon;
   c.londonStart      = InpLondonStart;
   c.londonEnd        = InpLondonEnd;
   c.tradeNy          = InpTradeNy;
   c.nyStart          = InpNyStart;
   c.nyEnd            = InpNyEnd;
   c.sesBufferMin     = InpSesBufferMin;
   c.blockFriLateHours = InpBlockFriLateHours;
   return c;
}

//------------------------------------------------------------------//
void WipeObjects(void)
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, PFX) == 0)
         ObjectDelete(0, nm);
   }
}

//------------------------------------------------------------------//
// Panel rows are OBJ_LABELs, not OBJ_TEXTs. OBJ_TEXT is anchored to a time/price
// coordinate, so a pixel offset like (10, 20) places the text in 1970. Labels are
// anchored to a chart corner and positioned in pixels, which is what a panel needs.
void DrawRow(const string nm, const int x, const int y, const string txt,
             const color clr, const int size = 8)
{
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, nm, OBJPROP_TEXT, txt);
   ObjectSetString (0, nm, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
}

//------------------------------------------------------------------//
void DrawLevel(const string nm, const double price, const color clr,
               const ENUM_LINE_STYLE style = STYLE_SOLID, const int width = 1)
{
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, nm, OBJPROP_PRICE, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
}

//------------------------------------------------------------------//
void DrawHLine(const string nm, const int shift1, const int shift2, const double price,
               const color clr, const ENUM_LINE_STYLE style = STYLE_SOLID,
               const int width = 1)
{
   // Both arguments are SHIFTS into the core's own series, so no translation is needed.
   datetime t1 = g_core.TimeAt(shift1);
   datetime t2 = g_core.TimeAt(shift2);
   if(t1 == 0 || t2 == 0)
      return;
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price);
   ObjectMove(0, nm, 0, t1, price);
   ObjectMove(0, nm, 1, t2, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
}

//==================================================================//
//  DRAWING                                                         //
//==================================================================//
//------------------------------------------------------------------//
void DrawPanel(void)
{
   if(!InpShowPanel) { ObjectDelete(0, PFX "panel"); return; }

   SAILensOut o = g_core.Out();
   SAILensTrade t = g_core.Trade();

   int x = 12, y = 22, dy = 16;
   color cKey = clrSilver, cVal = clrWhiteSmoke;
   color cBull = C'0,230,118', cBear = C'255,82,82', cCy = C'0,229,255', cWarn = C'255,215,64';

   string lead = (t.side == 1 ? "LONG" : (t.side == -1 ? "SHORT" : "WAIT"));
   color  leadC = (t.side == 1 ? cBull : (t.side == -1 ? cBear : cVal));

   int line = 0;
   DrawRow(PFX "p_title", x, y + dy * line++, "AI AGENT LENS +  " + _Symbol + " " + TfStr(PERIOD_CURRENT), cCy, 9);
   DrawRow(PFX "p_hero",  x, y + dy * line++, lead + "   " + IntegerToString(t.side == 1 ? o.longScore : (t.side == -1 ? o.shortScore : 0)), leadC, 12);

   DrawRow(PFX "p_regime", x, y + dy * line++, "Regime      " + o.regime, cVal, 8);
   DrawRow(PFX "p_sess",   x, y + dy * line++, "Session     " + o.sesLabel + (o.inSession ? "" : " (blocked)"),
            (o.inSession ? cCy : cWarn), 8);
   DrawRow(PFX "p_scores", x, y + dy * line++, "Long/Short  " + IntegerToString(o.longScore) + " / " + IntegerToString(o.shortScore),
            (o.longScore > o.shortScore ? cBull : (o.shortScore > o.longScore ? cBear : cVal)), 8);

   int aligned = (o.longScore >= o.shortScore
                  ? (o.lTrend >= 12) + (o.lMom >= 12) + (o.lStr >= 12) + (o.lVol >= 12) + (o.lHtf >= 12)
                  : (o.sTrend >= 12) + (o.sMom >= 12) + (o.sStr >= 12) + (o.sVol >= 12) + (o.sHtf >= 12));
   DrawRow(PFX "p_conf", x, y + dy * line++,
            "Confluence  " + IntegerToString(aligned) + " of " + IntegerToString(o.activeFactors) + " aligned",
            (aligned >= o.activeFactors - 1 ? cBull : cVal), 8);

   if(t.side != 0)
   {
      DrawRow(PFX "p_entry", x, y + dy * line++, "Entry       " + DoubleToString(t.entry, _Digits), cVal, 8);
      DrawRow(PFX "p_stop",  x, y + dy * line++, "Stop        " + DoubleToString(t.stop, _Digits) + (t.beMoved ? "  (BE)" : ""), cBear, 8);
      DrawRow(PFX "p_tgts",  x, y + dy * line++, "Targets     " + DoubleToString(t.t1, _Digits) + " / " + DoubleToString(t.t2, _Digits), cBull, 8);
      string rTxt = (o.openR == EMPTY_VALUE ? "n/a" : (o.openR >= 0 ? "+" : "") + DoubleToString(o.openR, 2) + "R");
      DrawRow(PFX "p_openr", x, y + dy * line++, "Open P&L    " + rTxt, (o.openR >= 0 ? cBull : cBear), 8);
   }

   // EMPTY_VALUE is DBL_MAX: printing it raw shows 1.797e308. Format through a guard.
   string rsiTxt = (o.rsiV == EMPTY_VALUE ? "--" : DoubleToString(o.rsiV, 0));
   string adxTxt = (o.adxV == EMPTY_VALUE ? "--" : DoubleToString(o.adxV, 0));
   DrawRow(PFX "p_ctx", x, y + dy * line++,
            "HTF " + o.htfBiasStr + "   RSI " + rsiTxt + "   ADX " + adxTxt, cVal, 8);
   DrawRow(PFX "p_struct", x, y + dy * line++, "Structure   " + o.structBias + (o.structEvent == "NONE" ? "" : "  " + o.structEvent),
            (o.structBias == "BULLISH" ? cBull : (o.structBias == "BEARISH" ? cBear : cVal)), 8);

   // Remove rows left over from an earlier run that drew more of them.
   static int lastRows = 0;
   for(int extra = line; extra < lastRows; extra++)
      ObjectDelete(0, PFX "p_row" + IntegerToString(extra));
   lastRows = line;
}

//------------------------------------------------------------------//
void DrawTradeBoxes(void)
{
   SAILensTrade t = g_core.Trade();
   if(t.side == 0)
   {
      ObjectDelete(0, PFX "risk");
      ObjectDelete(0, PFX "reward");
      ObjectDelete(0, PFX "t1line");
      return;
   }

   // Locate the entry bar by TIME. t.bar is only a display value: it is the shift the
   // engine saw when the trade opened, and shifts move with every new bar.
   int entryShift = 0;
   for(int s = 0; s < g_core.Bars(); s++)
   {
      if(g_core.TimeAt(s) == t.entryTime) { entryShift = s; break; }
   }

   datetime t1 = g_core.TimeAt(entryShift);
   datetime t2 = g_core.TimeAt(0);
   if(t1 == 0 || t2 == 0)
      return;

   if(ObjectFind(0, PFX "risk") < 0)
      ObjectCreate(0, PFX "risk", OBJ_RECTANGLE, 0, t1, t.stop, t2, t.entry);
   ObjectMove(0, PFX "risk", 0, t1, t.stop);
   ObjectMove(0, PFX "risk", 1, t2, t.entry);
   ObjectSetInteger(0, PFX "risk", OBJPROP_COLOR, C'255,82,82');
   ObjectSetInteger(0, PFX "risk", OBJPROP_FILL, true);
   ObjectSetInteger(0, PFX "risk", OBJPROP_BACK, true);
   ObjectSetInteger(0, PFX "risk", OBJPROP_SELECTABLE, false);

   if(ObjectFind(0, PFX "reward") < 0)
      ObjectCreate(0, PFX "reward", OBJ_RECTANGLE, 0, t1, t.entry, t2, t.t2);
   ObjectMove(0, PFX "reward", 0, t1, t.entry);
   ObjectMove(0, PFX "reward", 1, t2, t.t2);
   ObjectSetInteger(0, PFX "reward", OBJPROP_COLOR, C'0,230,118');
   ObjectSetInteger(0, PFX "reward", OBJPROP_FILL, true);
   ObjectSetInteger(0, PFX "reward", OBJPROP_BACK, true);
   ObjectSetInteger(0, PFX "reward", OBJPROP_SELECTABLE, false);

   DrawHLine(PFX "t1line", entryShift, 0, t.t1, C'0,230,118', STYLE_DASH);
}

//==================================================================//
//  LIFECYCLE                                                       //
//==================================================================//
int OnInit()
{
   g_cfg = BuildConfig();

   if(!g_core.Init(g_cfg, _Symbol, (ENUM_TIMEFRAMES)Period()))
   {
      Print("AILens_Ind: core init failed");
      return INIT_FAILED;
   }
   if(!g_core.Warmup(InpMaxBarsToDraw))
   {
      Print("AILens_Ind: warmup failed - not enough history yet");
      return INIT_FAILED;
   }

   WipeObjects();
   g_ready = true;
   g_lastBarTime = 0;

   IndicatorSetString(INDICATOR_SHORTNAME, "AI Lens+");
   return INIT_SUCCEEDED;
}

//------------------------------------------------------------------//
void OnDeinit(const int reason)
{
   WipeObjects();
   g_core.Deinit();
   ChartRedraw();
}

//------------------------------------------------------------------//
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(!g_ready)
      return 0;

   // The core decides whether a closed bar is new; the indicator only decides when to
   // repaint. OnCalculate fires per tick, so a cheap guard saves a full redraw.
   datetime cur = time[rates_total - 1];

   if(cur != g_lastBarTime)
   {
      g_lastBarTime = cur;
      // Step() returning false just means no bar has closed yet; the panel still needs
      // to exist on first attach, so do not bail out early.
      g_core.Step();

      if(InpShowLevels)
      {
         SAILensOut o = g_core.Out();
         if(o.pdh != EMPTY_VALUE) DrawLevel(PFX "pdh", o.pdh, clrGray, STYLE_DOT);
         if(o.pdl != EMPTY_VALUE) DrawLevel(PFX "pdl", o.pdl, clrGray, STYLE_DOT);
         if(o.vwapV != EMPTY_VALUE) DrawLevel(PFX "vwap", o.vwapV, clrDimGray, STYLE_DOT);
      }

      DrawTradeBoxes();
      DrawPanel();
      ChartRedraw();
   }

   return rates_total;
}
//+------------------------------------------------------------------+
