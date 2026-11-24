//+------------------------------------------------------------------+
//|  AILens_EA.mq5                                                    |
//|  AI Agent Lens - signal EA (Telegram).                            |
//|                                                                   |
//|  SIGNAL-ONLY: it reads the same AILens.mqh core as the indicator  |
//|  and sends a Telegram message when a setup fires. It never opens  |
//|  an order in normal use.                                          |
//|                                                                   |
//|  All order-execution code sits behind InpEnableOrders, which is   |
//|  false by default and is meant to be true ONLY inside the         |
//|  Strategy Tester. Read the warning on that input before flipping  |
//|  it: there is no daily-loss or max-positions guard in this file.  |
//|                                                                   |
//|  Telegram requires two one-time setups:                           |
//|   1. @BotFather -> /newbot -> keep the token.                     |
//|   2. Allow the WebRequest URL in MT5:                             |
//|      Tools -> Options -> Expert Advisors ->                       |
//|      "Allow WebRequest for listed URL" -> add                     |
//|      https://api.telegram.org                                     |
//|      Without this every send fails with error 4014.               |
//+------------------------------------------------------------------+
#property copyright "AI Agent Lens"
#property version   "1.00"

#include "AILens.mqh"

//==================================================================//
//  INPUTS                                                          //
//==================================================================//
input group "Signals"
input int    InpScoreThreshold   = 70;
input bool   InpBlockHighVol     = true;
input ENUM_TIMEFRAMES InpHtfTf   = PERIOD_H4;
input int    InpHtfEmaLen        = 50;
input bool   InpRequireHtfAlign  = true;
input double InpMinAdxEntry      = 20.0;
input double InpMaxExtAtr        = 1.5;
input int    InpMinBarsBetween   = 6;
input string InpStructGate       = "Off";
input string InpHtfUnavailable   = "Redistribute";

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
input string InpVolumeMode       = "Range proxy";

input group "Structure"
input int    InpSwingLen         = 5;

input group "Risk and exits"
input double InpStopAtr          = 2.0;
input string InpStopMode         = "ATR";
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
input int    InpSesTzOffsetHours = 0;
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

input group "Telegram"
input string InpBotToken         = "";     // from @BotFather; leave empty to disable sending
input string InpChatId           = "";     // your chat id
input int    InpHistoryBars      = 4000;   // warmup depth

input group "Sizing (used in the message, and for orders if enabled)"
input double InpRiskUsd          = 50.0;   // fixed dollar risk per trade
input double InpRewardRisk       = 2.0;    // target as an R multiple for the message

input group "Order execution"
// DANGER, and the reason this defaults to false: this EA sets a stop-loss and a
// take-profit per order, but it has NO daily-loss limit, NO max-trades-per-day and
// NO max-concurrent-positions check. With it on, an unattended chart can keep
// opening trades all day. Treat it as a Strategy Tester switch, not a live switch.
input bool   InpEnableOrders     = false;  // OFF: signal-only. Read the notes before enabling.
input double InpMaxSpreadPoints  = 0;      // refuse entry above this spread (points, 0 = off)

//==================================================================//
//  GLOBALS                                                         //
//==================================================================//
CAILensCore g_core;
SAILensConfig g_cfg;

// Forward declaration: OnTick uses this, but it is defined at the bottom of the file.
void PlaceBracketOrder(void);
bool     g_ready = false;

//==================================================================//
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

   c.emaFastLen = InpEmaFastLen;  c.emaMidLen = InpEmaMidLen;
   c.emaSlowLen = InpEmaSlowLen;  c.slopeLen  = InpSlopeLen;
   c.rsiLen     = InpRsiLen;      c.rsiOB     = InpRsiOB;   c.rsiOS = InpRsiOS;
   c.adxLen     = InpAdxLen;      c.adxTrend  = InpAdxTrend;

   c.volLen = InpVolLen;  c.atrLen = InpAtrLen;  c.atrPctLen = InpAtrPctLen;
   c.highVolPct = InpHighVolPct;  c.volumeMode = InpVolumeMode;

   c.swingLen = InpSwingLen;

   c.stopAtr = InpStopAtr;  c.stopMode = InpStopMode;  c.maxStopAtr = InpMaxStopAtr;
   c.t1R = InpT1R;  c.t2R = InpT2R;
   c.partialT1Pct = InpPartialT1Pct;  c.moveBeAfterT1 = InpMoveBeAfterT1;
   c.useTrailing = InpUseTrailing;  c.trailAtr = InpTrailAtr;  c.trailFromStart = InpTrailFromStart;
   c.maxBarsInTrade = InpMaxBarsInTrade;

   c.useSessionFilter = InpUseSessionFilter;
   c.sesTzOffsetHours = InpSesTzOffsetHours;
   c.tradeAsia = InpTradeAsia;  c.asiaStart = InpAsiaStart;  c.asiaEnd = InpAsiaEnd;
   c.tradeLondon = InpTradeLondon;  c.londonStart = InpLondonStart;  c.londonEnd = InpLondonEnd;
   c.tradeNy = InpTradeNy;  c.nyStart = InpNyStart;  c.nyEnd = InpNyEnd;
   c.sesBufferMin = InpSesBufferMin;  c.blockFriLateHours = InpBlockFriLateHours;
   return c;
}

//==================================================================//
//  SIZING                                                          //
//==================================================================//
// Lot size from a fixed dollar risk, mirroring lib/sizing.py:
//   lots = risk_usd / (stop_distance / tick_size * tick_value)
// rounded DOWN to the broker's lot step, with a min-lot floor.
double LotsFor(const double entry, const double stop)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double stopDist = MathAbs(entry - stop);
   if(stopDist <= 0.0)
      return 0.0;

   double riskPerLot = stopDist / tickSize * tickValue;
   if(riskPerLot <= 0.0)
      return 0.0;

   double lots = InpRiskUsd / riskPerLot;
   lots = MathFloor(lots / step) * step;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   return lots;
}

//==================================================================//
//  TELEGRAM                                                        //
//==================================================================//
bool TgSend(const string textIn)
{
   if(InpBotToken == "" || InpChatId == "")
      return false;                       // not configured: silently skip

   // StringReplace works in place, so it needs a mutable copy - and the escapes must
   // be applied in an order that cannot re-escape its own output ("+" -> %2B before
   // anything that could introduce a '+').
   string text = textIn;
   StringReplace(text, "&", "%26");
   StringReplace(text, "+", "%2B");
   StringReplace(text, "#", "%23");
   StringReplace(text, "\n", "%0A");

   string url = "https://api.telegram.org/bot" + InpBotToken + "/sendMessage";
   string params = "chat_id=" + InpChatId + "&text=" + text;

   char post[];  char result[];  string headers;
   // StringToCharArray writes a terminating NUL; strip it or the POST body length lies.
   int n = StringToCharArray(params, post, 0, WHOLE_ARRAY);
   if(n > 0)
      ArrayResize(post, n - 1);
   int timeout = 8000;

   ResetLastError();
   int code = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n",
                         timeout, post, result, headers);
   if(code == -1)
   {
      Print("AILens_EA: WebRequest failed, err=", GetLastError(),
            " - add https://api.telegram.org to the allowed WebRequest URLs");
      return false;
   }
   if(code != 200)
   {
      Print("AILens_EA: telegram HTTP ", code, " resp=", CharArrayToString(result));
      return false;
   }
   return true;
}

//==================================================================//
//  SIGNAL MESSAGE                                                  //
//==================================================================//
void SendSetupMessage(void)
{
   SAILensOut  o = g_core.Out();
   SAILensTrade t = g_core.Trade();
   if(t.side == 0)
      return;

   double lots   = LotsFor(t.entry, t.stop);
   double riskUsd = lots * MathAbs(t.entry - t.stop) /
                    SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) *
                    SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   string arrow  = (t.side == 1 ? "\x2714 BUY " : "\x2716 SELL ");
   string side   = (t.side == 1 ? "LONG" : "SHORT");
   double target = (t.side == 1
                    ? t.entry + InpRewardRisk * MathAbs(t.entry - t.stop)
                    : t.entry - InpRewardRisk * MathAbs(t.entry - t.stop));

   string msg = arrow + side + "  " + _Symbol + "  " + AILens_TfToString(PERIOD_CURRENT) + "\n"
              + "Score      " + IntegerToString(t.side == 1 ? o.longScore : o.shortScore) + "\n"
              + "Entry      " + DoubleToString(t.entry, _Digits) + "\n"
              + "Stop       " + DoubleToString(t.stop, _Digits) + "\n"
              + "Target     " + DoubleToString(target, _Digits) + " (" + DoubleToString(InpRewardRisk, 1) + "R)\n"
              + "Lots       " + DoubleToString(lots, 2) + "   risk ~$" + DoubleToString(riskUsd, 2) + "\n"
              + "Regime     " + o.regime + "\n"
              + "Session    " + o.sesLabel + "\n"
              + "HTF        " + o.htfBiasStr + "\n"
              + "Structure  " + o.structBias;

   TgSend(msg);
   Print("AILens_EA: ", side, " setup on ", _Symbol,
          " score=", (t.side == 1 ? o.longScore : o.shortScore),
          " lots=", DoubleToString(lots, 2));
}

//==================================================================//
//  LIFECYCLE                                                       //
//==================================================================//
int OnInit()
{
   g_cfg = BuildConfig();

   if(!g_core.Init(g_cfg, _Symbol, (ENUM_TIMEFRAMES)Period()))
   {
      Print("AILens_EA: core init failed");
      return INIT_FAILED;
   }
   // Warmup may legitimately fail right after the terminal starts, or after a timeframe
   // change; OnTick/OnTimer retry. Log the real reason, not a guess.
   g_ready = g_core.Warmup(InpHistoryBars);
   if(!g_ready)
      PrintFormat("AILens_EA: warmup pending on %s %s - %s (will retry)",
                  _Symbol, AILens_TfToString((ENUM_TIMEFRAMES)Period()), g_core.LastError());

   if(InpEnableOrders && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("AILens_EA: WARNING - orders enabled but AutoTrading is off");

   EventSetTimer(30);          // heartbeat: re-try warmup / re-check the feed
   return INIT_SUCCEEDED;
}

//------------------------------------------------------------------//
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_core.Deinit();
   // OnInit runs again after a timeframe or symbol change, which invalidates everything
   // the core holds. Clearing the flag here means the next Warmup is not skipped on the
   // stale assumption that history is already loaded.
   g_ready = false;
}

//------------------------------------------------------------------//
// Throttled warmup retry. Warmup copies ~15 series, and while the terminal is still
// downloading history OnTick can fire thousands of times with nothing to do. Retrying
// on every tick would make the terminal crawl exactly when it is already busy.
bool TryWarmup(void)
{
   static uint lastAttempt = 0;
   uint now = GetTickCount();
   if(lastAttempt != 0 && (now - lastAttempt) < 2000)
      return false;
   lastAttempt = now;

   if(!g_core.Warmup(InpHistoryBars))
      return false;

   g_ready = true;
   PrintFormat("AILens_EA: warmup completed on %s %s (%d bars, %d required)",
               _Symbol, AILens_TfToString((ENUM_TIMEFRAMES)Period()),
               g_core.LoadedBars(), g_core.MinBars());
   return true;
}

//------------------------------------------------------------------//
void OnTick(void)
{
   if(!g_ready && !TryWarmup())
      return;

   // Step() owns the closed-bar bookkeeping and returns false when no new bar closed.
   // Tracking it here as well would mean two clocks that can disagree - and the one
   // that silently loses a bar is always the outer one.
   if(!g_core.Step())
      return;

   SAILensOut o = g_core.Out();
   if(o.eventStr == "LONG_SETUP" || o.eventStr == "SHORT_SETUP")
   {
      // spread guard
      long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(InpMaxSpreadPoints > 0 && spreadPts > InpMaxSpreadPoints)
      {
         Print("AILens_EA: setup skipped, spread ", spreadPts, " > ", InpMaxSpreadPoints, " points");
         return;
      }

      SendSetupMessage();

      if(InpEnableOrders)
         PlaceBracketOrder();
   }
}

//------------------------------------------------------------------//
void OnTimer(void)
{
   // Warmup retry while the terminal is still loading history, and a safety net for a
   // market quiet enough that no tick arrives and a closed bar would otherwise be
   // processed late (or not at all) while the EA is running live.
   if(!g_ready)
   {
      TryWarmup();
      return;
   }
   OnTick();
}

//==================================================================//
//  ORDER EXECUTION (only when InpEnableOrders = true)              //
//==================================================================//
// One EA instance per chart. Each instance stamps its orders with a magic derived
// from the symbol, so five charts running five symbols never touch each other's
// positions when counting or closing.
int MagicFor(void)
{
   int h = 20261124;
   for(int i = 0; i < StringLen(_Symbol); i++)
      h = (h * 31 + StringGetCharacter(_Symbol, i)) % 100000000;
   return h;
}


void PlaceBracketOrder(void)
{
   SAILensTrade t = g_core.Trade();
   if(t.side == 0)
      return;

   double lots = LotsFor(t.entry, t.stop);
   if(lots <= 0.0)
   {
      Print("AILens_EA: lot sizing failed, no order placed");
      return;
   }

   ENUM_ORDER_TYPE type = (t.side == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double price = (t.side == 1
                   ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                   : SymbolInfoDouble(_Symbol, SYMBOL_BID));

   MqlTradeRequest req;  MqlTradeResult res;
   ZeroMemory(req);  ZeroMemory(res);
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lots;
   req.type      = type;
   req.price     = price;
   req.sl        = t.stop;
   req.tp        = t.t2;
   req.deviation = 20;
   req.magic     = MagicFor();
   req.comment   = "AILens";
   req.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(req, res))
      Print("AILens_EA: OrderSend failed, retcode=", res.retcode, " err=", GetLastError());
   else
      Print("AILens_EA: order placed, ticket=", res.order,
            " lots=", DoubleToString(lots, 2),
            " sl=", DoubleToString(t.stop, _Digits),
            " tp=", DoubleToString(t.t2, _Digits));
}
//+------------------------------------------------------------------+
