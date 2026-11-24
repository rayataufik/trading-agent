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
// OFF: setups are allowed at any hour. Set true to re-enable the windows below; the
// Python config has its own `enabled` key and the two are independent switches.
input bool   InpUseSessionFilter = false;
// Broker server is UTC+2, so 2 hours must be SUBTRACTED to reach the UTC clock the
// session windows below (and Pine) are written in: session hour = broker hour - 2.
// This is only a FALLBACK: the core measures the real gap at startup (TimeTradeServer
// minus TimeGMT) so a summer-time switch to UTC+3 is followed automatically. The value
// actually used is printed in the Experts log as "session clock".
input int    InpSesTzOffsetHours = -2;      // fallback: broker -> session clock (UTC+2 = -2)
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
input bool   InpPanelBackdrop    = true;    // dark box behind the panel text
input color  InpPanelBackColor   = C'10,14,20';  // backdrop colour
input int    InpPanelRowPx       = 16;      // px per row (raise if rows overlap)
input bool   InpShowLevels       = true;
input int    InpMaxBarsToDraw    = 3000;    // Bars to load and draw

//==================================================================//
//  GLOBALS                                                         //
//==================================================================//
CAILensCore g_core;
SAILensConfig g_cfg;
bool g_ready = false;
datetime g_lastBarTime = 0;
uint     g_lastAttempt = 0;   // GetTickCount() of the last retry (real time, not server time)

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
//
// DrawRow also records the widest row drawn since the last backdrop reset, so the
// background box can be sized to the actual text instead of a guessed constant. The
// width estimate is per-character and monospace-specific on purpose: Consolas is
// fixed-width, so len * size * 0.62 is accurate enough for a backdrop.
double g_panelW = 0.0;

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
   // ZORDER here only affects mouse-click priority in MT5, not what is painted on top.
   // Render order comes from creation order, which is why DrawPanel creates the backdrop
   // before the labels.
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 10);

   double w = StringLen(txt) * size * 0.62;
   if(w > g_panelW)
      g_panelW = w;
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
//  Forward declaration: DrawPanel calls this before it is defined below.
//------------------------------------------------------------------//
void DrawPanelBackdrop(const int x, const int y, const int rows, const int dy);

//------------------------------------------------------------------//
//  DrawPanel builds the whole panel as a list of rows first, then paints the
//  backdrop, then paints the text. That order is not cosmetic: MT5 renders
//  foreground objects in creation order, and OBJPROP_ZORDER only decides which
//  object receives a mouse click - it does NOT bring a label in front of a
//  rectangle. Drawing the box last therefore hid every row behind it, which is
//  exactly what happened when InpPanelBackdrop was turned on.
//------------------------------------------------------------------//
//------------------------------------------------------------------//
//  Delete every object the panel owns. Called before each rebuild so creation
//  order is always: backdrop first, then rows. MT5 paints foreground objects in
//  creation order, so only a clean rebuild guarantees the box stays behind the text.
//------------------------------------------------------------------//
void WipePanelObjects(void)
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, PFX "p_") == 0)
         ObjectDelete(0, nm);
   }
}

void DrawPanel(void)
{
   if(!InpShowPanel)
   {
      // Remove everything the panel owns, including the backdrop. Deleting only
      // "panel" (a name no object ever uses) left the whole panel on screen.
      WipePanelObjects();
      return;
   }

   // Rebuild from scratch, in order. Reusing label objects keeps their original
   // creation order, and any order other than "box, then text" hides the panel.
   WipePanelObjects();

   SAILensOut o = g_core.Out();
   SAILensTrade t = g_core.Trade();

   int x = 12, y = 22;
   // Row pitch is scaled to the terminal's DPI. A fixed 16 px is what made the rows
   // collide into an unreadable smear on a scaled display: the font grows with the
   // system scaling, the pitch did not. At 96 dpi nothing changes; at 150% the pitch
   // becomes ~24 px.
   int dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi < 96) dpi = 96;
   int dy = (int)MathRound((double)InpPanelRowPx * dpi / 96.0);
   if(dy < 8) dy = 8;

   color cVal = clrWhiteSmoke;
   color cBull = C'0,230,118', cBear = C'255,82,82', cCy = C'0,229,255', cWarn = C'255,215,64';

   string lead = (t.side == 1 ? "LONG" : (t.side == -1 ? "SHORT" : "WAIT"));
   color  leadC = (t.side == 1 ? cBull : (t.side == -1 ? cBear : cVal));

   // Row list. `slots` is how many row-pitches the row occupies: the 12pt hero needs
   // two, otherwise its descenders land on the Regime row.
   string nm[16], tx[16];
   color  cl[16];
   int    sz[16], slots[16];
   int    n = 0;

   nm[n]=PFX "p_title";  tx[n]="AI AGENT LENS +  " + _Symbol + " " + TfStr((ENUM_TIMEFRAMES)Period()); cl[n]=cCy;  sz[n]=9;  slots[n]=1; n++;
   nm[n]=PFX "p_hero";   tx[n]=lead + "   " + IntegerToString(t.side == 1 ? o.longScore : (t.side == -1 ? o.shortScore : 0)); cl[n]=leadC; sz[n]=12; slots[n]=2; n++;
   nm[n]=PFX "p_regime"; tx[n]="Regime      " + o.regime;                             cl[n]=cVal;  sz[n]=8; slots[n]=1; n++;
   nm[n]=PFX "p_sess";   tx[n]="Session     " + o.sesLabel + (o.inSession ? "" : " (blocked)"); cl[n]=(o.inSession ? cCy : cWarn); sz[n]=8; slots[n]=1; n++;
   nm[n]=PFX "p_scores"; tx[n]="Long/Short  " + IntegerToString(o.longScore) + " / " + IntegerToString(o.shortScore);
                         cl[n]=(o.longScore > o.shortScore ? cBull : (o.shortScore > o.longScore ? cBear : cVal)); sz[n]=8; slots[n]=1; n++;

   int aligned = (o.longScore >= o.shortScore
                  ? (o.lTrend >= 12) + (o.lMom >= 12) + (o.lStr >= 12) + (o.lVol >= 12) + (o.lHtf >= 12)
                  : (o.sTrend >= 12) + (o.sMom >= 12) + (o.sStr >= 12) + (o.sVol >= 12) + (o.sHtf >= 12));
   nm[n]=PFX "p_conf";   tx[n]="Confluence  " + IntegerToString(aligned) + " of " + IntegerToString(o.activeFactors) + " aligned";
                         cl[n]=(aligned >= o.activeFactors - 1 ? cBull : cVal); sz[n]=8; slots[n]=1; n++;

   if(t.side == 0)
   {
      // Flat: no trade rows. They cannot linger, because every DrawPanel rebuild starts
      // from a clean slate (WipePanelObjects) rather than reusing objects.
   }
   else
   {
      nm[n]=PFX "p_entry"; tx[n]="Entry       " + DoubleToString(t.entry, _Digits); cl[n]=cVal; sz[n]=8; slots[n]=1; n++;
      nm[n]=PFX "p_stop";  tx[n]="Stop        " + DoubleToString(t.stop, _Digits) + (t.beMoved ? "  (BE)" : ""); cl[n]=cBear; sz[n]=8; slots[n]=1; n++;
      nm[n]=PFX "p_tgts";  tx[n]="Targets     " + DoubleToString(t.t1, _Digits) + " / " + DoubleToString(t.t2, _Digits); cl[n]=cBull; sz[n]=8; slots[n]=1; n++;
      string rTxt = (o.openR == EMPTY_VALUE ? "n/a" : (o.openR >= 0 ? "+" : "") + DoubleToString(o.openR, 2) + "R");
      nm[n]=PFX "p_openr"; tx[n]="Open P&L    " + rTxt; cl[n]=(o.openR >= 0 ? cBull : cBear); sz[n]=8; slots[n]=1; n++;
   }

   // EMPTY_VALUE is DBL_MAX: printing it raw shows 1.797e308. Format through a guard.
   string rsiTxt = (o.rsiV == EMPTY_VALUE ? "--" : DoubleToString(o.rsiV, 0));
   string adxTxt = (o.adxV == EMPTY_VALUE ? "--" : DoubleToString(o.adxV, 0));
   nm[n]=PFX "p_ctx";    tx[n]="HTF " + o.htfBiasStr + "   RSI " + rsiTxt + "   ADX " + adxTxt; cl[n]=cVal; sz[n]=8; slots[n]=1; n++;
   nm[n]=PFX "p_struct"; tx[n]="Structure   " + o.structBias + (o.structEvent == "NONE" ? "" : "  " + o.structEvent);
                         cl[n]=(o.structBias == "BULLISH" ? cBull : (o.structBias == "BEARISH" ? cBear : cVal)); sz[n]=8; slots[n]=1; n++;

   // Pass 1: total height in row-pitches, and the widest row for the backdrop.
   g_panelW = 0.0;
   int rows = 0;
   for(int i = 0; i < n; i++)
   {
      rows += slots[i];
      double w = StringLen(tx[i]) * sz[i] * 0.62;
      if(w > g_panelW)
         g_panelW = w;
   }

   // Pass 2: the box. Painted BEFORE the labels so it cannot cover them.
   DrawPanelBackdrop(x, y, rows, dy);

   // Pass 3: the text.
   int line = 0;
   for(int i = 0; i < n; i++)
   {
      DrawRow(nm[i], x, y + dy * line, tx[i], cl[i], sz[i]);
      line += slots[i];
   }
}

//------------------------------------------------------------------//
// Dark box behind the panel text. Without it the labels sit straight on top of the
// candles, and on a busy chart the numbers become unreadable exactly when you need
// them. OBJ_RECTANGLE_LABEL draws in pixels from a chart corner, so it can be placed
// behind the text without touching time/price coordinates.
//------------------------------------------------------------------//
void DrawPanelBackdrop(const int x, const int y, const int rows, const int dy)
{
   if(!InpPanelBackdrop)
   {
      ObjectDelete(0, PFX "p_bg");
      return;
   }
   if(rows <= 0)
      return;

   // Pad on both sides; the width comes from the widest row DrawRow actually drew.
   int padX = 8, padY = 6;
   int boxW = (int)MathCeil(g_panelW) + padX * 2;
   int boxH = rows * dy + padY * 2;

   // Recreate the box on every draw instead of reusing it. MT5 paints foreground
   // objects in creation order, so a reused box keeps whatever order it was first
   // created in - and after toggling InpPanelBackdrop off and on again, that order is
   // "after the labels", which puts it straight back over the text. Delete + create
   // makes the order deterministic: the box is always created before the labels that
   // DrawPanel draws next. It is one object, on a path that only runs on a new bar.
   ObjectDelete(0, PFX "p_bg");
   ObjectCreate(0, PFX "p_bg", OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, PFX "p_bg", OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_XDISTANCE,   x - padX);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_YDISTANCE,   y - padY);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_XSIZE,       boxW);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_YSIZE,       boxH);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_BGCOLOR,     InpPanelBackColor);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_COLOR,       C'45,55,70');
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_WIDTH,       1);
   // BACK=false keeps the box in the foreground layer, where it is painted in creation
   // order relative to the labels: created first, so painted first, so behind the text.
   // Setting it to true would push the box behind the price chart entirely and it would
   // vanish. ZORDER is mouse-click priority only and does not decide what covers what.
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_BACK,        false);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_ZORDER,      0);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, PFX "p_bg", OBJPROP_HIDDEN,      true);
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
   for(int s = 0; s < g_core.LoadedBars(); s++)
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
      Print("AILens_Ind: indicator handle creation failed, err=", GetLastError());
      return INIT_FAILED;                 // genuinely fatal: nothing can work
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "AI Lens+");

   // Print the session clock once, so a shifted session can never be silent. If the broker
   // switches to summer time, "used" changes with it and this line changes too; if it
   // shows the fallback while the server is known to be UTC+2, the PC clock is wrong.
   PrintFormat("AILens_Ind: %s %s | session clock: broker%sh -> UTC (requested %sh)%s",
               _Symbol, AILens_TfToString((ENUM_TIMEFRAMES)Period()),
               AILens_SignedHours(g_core.TzOffsetUsed()),
               AILens_SignedHours(g_core.TzOffsetRequested()),
               (g_core.TzOffsetUsed() == g_core.TzOffsetRequested() ? "" : " [auto-detected]"));

   // Market hours the gate will actually use, straight from the broker. Printed so the
   // automatic weekend/Friday rule can be checked rather than trusted: if this reads
   // "Mon-Fri 01:00-23:59" on your symbol, the close is being handled. An empty value
   // means the symbol publishes no hours and the gate falls back to not blocking.
   string mh = g_core.MarketHoursSummary();
   PrintFormat("AILens_Ind: %s market hours (broker time): %s",
               _Symbol, (mh == "" ? "<none published - market assumed open>" : mh));

   // A failed warmup here is NOT fatal and must not return INIT_FAILED.
   // MT5 runs OnInit before it has necessarily downloaded the chart history: on a
   // symbol/timeframe you have not opened before, Bars() can be tiny or zero at this
   // moment even though the data arrives seconds later. Returning INIT_FAILED would
   // make MT5 delete the indicator from the chart permanently, so "not enough
   // history yet" would mean "never works", which is exactly what you saw.
   //
   // Instead the indicator stays attached and retries: OnCalculate on every tick, and
   // OnTimer every few seconds (including on a quiet market, where ticks are rare).
   g_ready = g_core.Warmup(InpMaxBarsToDraw);
   if(!g_ready)
      PrintFormat("AILens_Ind: not live yet on %s %s - %s. Keep the chart open; the "
                  "indicator goes live on its own when the terminal has the data.",
                  _Symbol, AILens_TfToString((ENUM_TIMEFRAMES)Period()), g_core.LastError());

   WipeObjects();
   g_lastBarTime = 0;
   g_lastAttempt = 0;

   EventSetTimer(3);                     // retry even when the market is quiet
   return INIT_SUCCEEDED;
}

//------------------------------------------------------------------//
void OnDeinit(const int reason)
{
   EventKillTimer();
   WipeObjects();
   g_core.Deinit();
   // Leaving this true would make TryWarmup() believe the core is live after a
   // timeframe change has already invalidated it, and the "waiting" label would never
   // appear even though nothing has been loaded for the new timeframe yet.
   g_ready = false;
   g_lastBarTime = 0;
   ChartRedraw();
}

//------------------------------------------------------------------//
//  Retry warmup. Called from OnCalculate (any tick) and OnTimer (quiet market).
//  Returns true once the core is live. The reload is not free (it copies ~15 series),
//  so attempts are throttled to once every couple of seconds.
//------------------------------------------------------------------//
bool TryWarmup(void)
{
   if(g_ready)
      return true;

   // Throttle on GetTickCount() - REAL elapsed time - not on TimeCurrent().
   // TimeCurrent() is the last known SERVER time and it freezes when the market is
   // closed. Using it here would mean that attaching the indicator on a Saturday
   // (exactly when there is no history being generated and none arriving) would
   // compute a delay of 0 forever and never retry.
   uint now = GetTickCount();
   if(g_lastAttempt != 0 && (now - g_lastAttempt) < 2000)
      return false;
   g_lastAttempt = now;

   if(!g_core.Warmup(InpMaxBarsToDraw))
   {
      // Say so ON THE CHART, and say WHY. A silent empty overlay looks like a broken
      // indicator, and the usual reaction is to remove and re-add it, which fixes
      // nothing. The reason text comes from the core, so it names the real failure
      // (chart history short, or indicator buffers still calculating) instead of
      // guessing "not enough history" for every possible cause.
      string why = g_core.LastError();
      if(why == "")
         why = "starting up";
      string msg = StringFormat("%s %s: waiting - %s",
                                _Symbol, AILens_TfToString((ENUM_TIMEFRAMES)Period()), why);
      if(ObjectFind(0, PFX "waiting") < 0)
         ObjectCreate(0, PFX "waiting", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PFX "waiting", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PFX "waiting", OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, PFX "waiting", OBJPROP_YDISTANCE, 22);
      ObjectSetString (0, PFX "waiting", OBJPROP_TEXT, msg);
      ObjectSetString (0, PFX "waiting", OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, PFX "waiting", OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, PFX "waiting", OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, PFX "waiting", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, PFX "waiting", OBJPROP_HIDDEN, true);
      ChartRedraw();
      return false;
   }

   ObjectDelete(0, PFX "waiting");

   g_ready = true;
   g_lastBarTime = 0;
   PrintFormat("AILens_Ind: history ready on %s %s (%d bars loaded). Indicator is live.",
               _Symbol, AILens_TfToString((ENUM_TIMEFRAMES)Period()), g_core.LoadedBars());
   return true;
}

//------------------------------------------------------------------//
//  Draw everything for the current state. One place, so the tick path and the
//  timer path can never diverge in what they paint.
//------------------------------------------------------------------//
void DrawAll(void)
{
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

//------------------------------------------------------------------//
void OnTimer(void)
{
   if(!TryWarmup())
      return;

   // The timer exists for two reasons only:
   //   1. get the panel onto the chart right after a late warmup, and
   //   2. pick up a closed bar on a market so quiet that no tick arrives.
   // Outside those cases it must do nothing: repainting a chart every 3 s forever is
   // pure CPU burn, and on a laptop that is a fan you can hear.
   bool panelMissing = (ObjectFind(0, PFX "p_title") < 0);
   bool advanced = g_core.Step();          // true only when a NEW bar was processed

   if(!panelMissing && !advanced)
      return;

   DrawAll();
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
   // Guard before any access: on the very first call MT5 can hand over an empty history.
   if(rates_total < 2)
      return 0;

   if(!g_ready && !TryWarmup())
      return 0;                          // still waiting for history; retry next tick

   // The core decides whether a closed bar is new; the indicator only decides when to
   // repaint. OnCalculate fires per tick, so a cheap guard saves a full redraw.
   //
   // The forming bar's open time is read with iTime() rather than from time[]: the
   // OnCalculate arrays follow the chart's own series direction, which the user can flip,
   // while iTime(...,0) is always the current bar. Reading time[rates_total-1] would
   // silently switch to the OLDEST bar if the chart is set to non-series order, and this
   // guard would then stop firing on new bars entirely.
   datetime cur = iTime(_Symbol, (ENUM_TIMEFRAMES)Period(), 0);
   if(cur == 0)
      return 0;                          // history not ready

   if(cur != g_lastBarTime)
   {
      g_lastBarTime = cur;
      // Step() returning false just means no bar has closed yet; the panel still needs
      // to exist on first attach, so do not bail out early.
      g_core.Step();

      DrawAll();
   }

   return rates_total;
}
//+------------------------------------------------------------------+
