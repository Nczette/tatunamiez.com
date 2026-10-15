//+------------------------------------------------------------------+
//|                                              FastReversal.mq5    |
//|   ATR trailing-stop reversal signals + multi-timeframe context   |
//|   panel + entry zone / risk / TP levels.                         |
//|   For educational purposes only - not financial advice.          |
//+------------------------------------------------------------------+
#property copyright   "tatunamiez.com"
#property version     "1.00"
#property description "Fast Reversal: ATR trailing reversal signals, context panel, zone/risk/TP levels."
#property description "For educational purposes only."
#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   3

#property indicator_label1  "Trail"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue,clrTomato
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDeepSkyBlue
#property indicator_width2  2

#property indicator_label3  "Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrOrangeRed
#property indicator_width3  2

enum ENUM_FR_MODE
  {
   FR_AGGRESSIVE   = 0, // Aggressive (every reversal)
   FR_CONSERVATIVE = 1  // Conservative (score filter)
  };

//--- inputs
input group "Signal"
input ENUM_FR_MODE    InpMode             = FR_AGGRESSIVE; // Mode
input int             InpATRPeriod        = 14;            // ATR period
input double          InpMultAggressive   = 2.0;           // ATR multiplier (aggressive)
input double          InpMultConservative = 3.0;           // ATR multiplier (conservative)
input double          InpMinScore         = 60.0;          // Min setup score (conservative)
input bool            InpConfirmedOnly    = true;          // Signals on closed bars only (no repaint)
input int             InpMaxBars          = 3000;          // Max bars to calculate

input group "Context"
input ENUM_TIMEFRAMES InpCtx1TF           = PERIOD_H1;     // Context 1 timeframe
input ENUM_TIMEFRAMES InpCtx2TF           = PERIOD_H4;     // Context 2 timeframe
input int             InpEmaFast          = 21;            // Context EMA fast
input int             InpEmaSlow          = 50;            // Context EMA slow
input int             InpSwingLen         = 5;             // Swing length (structure)
input int             InpADXPeriod        = 14;            // ADX period (momentum)
input int             InpVolLookback      = 100;           // Volatility lookback (ATR average)

input group "Levels"
input double          InpZoneATR          = 0.5;           // Entry zone depth (x ATR)
input double          InpTP1              = 1.0;           // TP1 (R multiple)
input double          InpTP2              = 1.5;           // TP2 (R multiple)
input double          InpTP3              = 2.0;           // END / TP3 (R multiple)
input int             InpExtendBars       = 12;            // Extend levels right (bars)
input bool            InpShowLevels       = true;          // Show levels

input group "Panel"
input bool            InpShowPanel        = true;          // Show panel
input int             InpPanelX           = 10;            // Panel X
input int             InpPanelY           = 25;            // Panel Y
input int             InpFontSize         = 9;             // Font size
input color           InpTitleBg          = C'70,40,150';  // Title background
input color           InpCellBg           = C'38,42,56';   // Cell background
input color           InpTextColor        = clrWhite;      // Text color

input group "Alerts"
input bool            InpAlertPopup       = true;          // Popup alert
input bool            InpAlertPush        = false;         // Push notification

//--- buffers
double TrailBuf[];
double TrailClr[];
double BuyBuf[];
double SellBuf[];
double DirBuf[];
double AtrBuf[];
double AdxBuf[];
double PdiBuf[];
double MdiBuf[];
double ScoreBuf[];

//--- handles
int hATR = INVALID_HANDLE, hADX = INVALID_HANDLE;
int hC1Fast = INVALID_HANDLE, hC1Slow = INVALID_HANDLE;
int hC2Fast = INVALID_HANDLE, hC2Slow = INVALID_HANDLE;

int      gFirst     = 0;
datetime gLastAlert = 0;

const string PFX = "FRV_";

const int COL1_W = 105;
const int COL2_W = 175;
const int ROW_H  = 19;

//+------------------------------------------------------------------+
double Mult()
  {
   return (InpMode == FR_AGGRESSIVE) ? InpMultAggressive : InpMultConservative;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, TrailBuf, INDICATOR_DATA);
   SetIndexBuffer(1, TrailClr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BuyBuf,   INDICATOR_DATA);
   SetIndexBuffer(3, SellBuf,  INDICATOR_DATA);
   SetIndexBuffer(4, DirBuf,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, AtrBuf,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, AdxBuf,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, PdiBuf,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, MdiBuf,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, ScoreBuf, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetInteger(2, PLOT_ARROW, 234);
   for(int p = 0; p < 3; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   hATR    = iATR(_Symbol, _Period, InpATRPeriod);
   hADX    = iADX(_Symbol, _Period, InpADXPeriod);
   hC1Fast = iMA(_Symbol, InpCtx1TF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hC1Slow = iMA(_Symbol, InpCtx1TF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hC2Fast = iMA(_Symbol, InpCtx2TF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hC2Slow = iMA(_Symbol, InpCtx2TF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   if(hATR == INVALID_HANDLE || hADX == INVALID_HANDLE ||
      hC1Fast == INVALID_HANDLE || hC1Slow == INVALID_HANDLE ||
      hC2Fast == INVALID_HANDLE || hC2Slow == INVALID_HANDLE)
     {
      Print("FastReversal: failed to create indicator handles");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "Fast Reversal");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   IndicatorRelease(hATR);
   IndicatorRelease(hADX);
   IndicatorRelease(hC1Fast);
   IndicatorRelease(hC1Slow);
   IndicatorRelease(hC2Fast);
   IndicatorRelease(hC2Slow);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Context bias from EMA fast/slow on the last CLOSED higher-TF bar |
//+------------------------------------------------------------------+
int ContextBias(const int hFast, const int hSlow, const ENUM_TIMEFRAMES tf, const datetime t)
  {
   int sh = iBarShift(_Symbol, tf, t, false);
   if(sh < 0)
      return 0;
   double f[1], s[1];
   if(CopyBuffer(hFast, 0, sh + 1, 1, f) != 1 || CopyBuffer(hSlow, 0, sh + 1, 1, s) != 1)
      return 0;
   double c = iClose(_Symbol, tf, sh + 1);
   if(c <= 0)
      return 0;
   if(f[0] > s[0] && c > s[0])
      return 1;
   if(f[0] < s[0] && c < s[0])
      return -1;
   return 0;
  }

//+------------------------------------------------------------------+
bool IsPivotHigh(const int j, const int L, const double &h[])
  {
   for(int k = 1; k <= L; k++)
      if(h[j - k] > h[j] || h[j + k] >= h[j])
         return false;
   return true;
  }

bool IsPivotLow(const int j, const int L, const double &l[])
  {
   for(int k = 1; k <= L; k++)
      if(l[j - k] < l[j] || l[j + k] <= l[j])
         return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Market structure using pivots confirmed up to bar i              |
//|  HH+HL = bullish, LH+LL = bearish, else break of last swing      |
//+------------------------------------------------------------------+
int StructureBias(const int i, const double &high[], const double &low[], const double &close[])
  {
   int L = InpSwingLen;
   double ph[2], pl[2];
   int nh = 0, nl = 0;
   int lim = MathMax(L, i - 500);
   for(int j = i - L; j >= lim && (nh < 2 || nl < 2); j--)
     {
      if(nh < 2 && IsPivotHigh(j, L, high))
         ph[nh++] = high[j];
      if(nl < 2 && IsPivotLow(j, L, low))
         pl[nl++] = low[j];
     }
   if(nh < 2 || nl < 2)
      return 0;
   if(ph[0] > ph[1] && pl[0] > pl[1])
      return 1;
   if(ph[0] < ph[1] && pl[0] < pl[1])
      return -1;
   if(close[i] > ph[0])
      return 1;
   if(close[i] < pl[0])
      return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Confluence score 0..100 for direction d at bar i                 |
//+------------------------------------------------------------------+
double ComputeScore(const int i, const int d, const datetime &time[],
                    const double &high[], const double &low[], const double &close[])
  {
   double s = 0;
   if(ContextBias(hC1Fast, hC1Slow, InpCtx1TF, time[i]) == d)
      s += 20;
   if(ContextBias(hC2Fast, hC2Slow, InpCtx2TF, time[i]) == d)
      s += 20;
   if(StructureBias(i, high, low, close) == d)
      s += 20;
   double adx = AdxBuf[i];
   if(adx > 0 && adx < 1000)
      s += 20.0 * MathMin(adx / 40.0, 1.0);
   if((d == 1 && PdiBuf[i] > MdiBuf[i]) || (d == -1 && MdiBuf[i] > PdiBuf[i]))
      s += 20;
   return s;
  }

//+------------------------------------------------------------------+
string BiasText(const int b)
  {
   return (b > 0) ? "BULLISH" : (b < 0) ? "BEARISH" : "NEUTRAL";
  }

color BiasColor(const int b)
  {
   return (b > 0) ? clrLime : (b < 0) ? clrTomato : InpTextColor;
  }

string Arrow(const int d)
  {
   return ShortToString((ushort)(d >= 0 ? 0x2191 : 0x2193));
  }

//+------------------------------------------------------------------+
//| Panel helpers                                                    |
//+------------------------------------------------------------------+
void MakeCell(const string id, const int x, const int y, const int w, const int h, const color bg)
  {
   string r = PFX + "bg_" + id;
   if(ObjectFind(0, r) < 0)
     {
      ObjectCreate(0, r, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, r, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, r, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, r, OBJPROP_COLOR, C'20,22,30');
      ObjectSetInteger(0, r, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, r, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, r, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, r, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, r, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, r, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, r, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, r, OBJPROP_BGCOLOR, bg);

   string t = PFX + "tx_" + id;
   if(ObjectFind(0, t) < 0)
     {
      ObjectCreate(0, t, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, t, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, t, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetString(0, t, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, t, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, t, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, t, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, t, OBJPROP_XDISTANCE, x + w / 2);
   ObjectSetInteger(0, t, OBJPROP_YDISTANCE, y + h / 2);
  }

void SetCell(const string id, const string text, const color fg)
  {
   string t = PFX + "tx_" + id;
   ObjectSetString(0, t, OBJPROP_TEXT, text);
   ObjectSetInteger(0, t, OBJPROP_COLOR, fg);
  }

void PanelRow(const int row, const string key, const string val, const color valColor)
  {
   int y = InpPanelY + ROW_H * (row + 1);
   MakeCell("k" + IntegerToString(row), InpPanelX, y, COL1_W, ROW_H, InpCellBg);
   MakeCell("v" + IntegerToString(row), InpPanelX + COL1_W, y, COL2_W, ROW_H, InpCellBg);
   SetCell("k" + IntegerToString(row), key, InpTextColor);
   SetCell("v" + IntegerToString(row), val, valColor);
  }

//+------------------------------------------------------------------+
//| Level helpers                                                    |
//+------------------------------------------------------------------+
void DrawLevel(const string id, const string text, const double price,
               const color clr, const datetime t1, const datetime t2)
  {
   string ln = PFX + "ln_" + id;
   if(ObjectFind(0, ln) < 0)
     {
      ObjectCreate(0, ln, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, ln, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
     }
   ObjectMove(0, ln, 0, t1, price);
   ObjectMove(0, ln, 1, t2, price);
   ObjectSetInteger(0, ln, OBJPROP_COLOR, clr);

   string lb = PFX + "lb_" + id;
   if(ObjectFind(0, lb) < 0)
     {
      ObjectCreate(0, lb, OBJ_TEXT, 0, t2, price);
      ObjectSetInteger(0, lb, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetString(0, lb, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, lb, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, lb, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lb, OBJPROP_HIDDEN, true);
     }
   ObjectMove(0, lb, 0, t2, price);
   ObjectSetString(0, lb, OBJPROP_TEXT, " " + text + " " + DoubleToString(price, _Digits));
   ObjectSetInteger(0, lb, OBJPROP_COLOR, clr);
  }

void DrawZone(const datetime t1, const datetime t2, const double p1, const double p2)
  {
   string n = PFX + "zone";
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, n, OBJPROP_FILL, true);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      ObjectSetInteger(0, n, OBJPROP_COLOR, C'0,70,85');
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectMove(0, n, 0, t1, p1);
   ObjectMove(0, n, 1, t2, p2);
  }

//+------------------------------------------------------------------+
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
   int minBars = InpATRPeriod + InpADXPeriod + 2 * InpSwingLen + InpVolLookback + 10;
   if(rates_total < minBars)
      return 0;

   if(BarsCalculated(hATR) < rates_total || BarsCalculated(hADX) < rates_total)
      return 0;
   if(BarsCalculated(hC1Fast) <= 0 || BarsCalculated(hC1Slow) <= 0 ||
      BarsCalculated(hC2Fast) <= 0 || BarsCalculated(hC2Slow) <= 0)
      return 0;

   bool full = (prev_calculated <= 0 || prev_calculated > rates_total);
   int toCopy = full ? rates_total : rates_total - prev_calculated + 1;

   if(CopyBuffer(hATR, 0, 0, toCopy, AtrBuf) <= 0)
      return 0;
   if(CopyBuffer(hADX, 0, 0, toCopy, AdxBuf) <= 0)
      return 0;
   if(CopyBuffer(hADX, 1, 0, toCopy, PdiBuf) <= 0)
      return 0;
   if(CopyBuffer(hADX, 2, 0, toCopy, MdiBuf) <= 0)
      return 0;

   double m = Mult();
   int start;
   if(full)
     {
      ArrayInitialize(TrailBuf, EMPTY_VALUE);
      ArrayInitialize(TrailClr, 0);
      ArrayInitialize(BuyBuf, EMPTY_VALUE);
      ArrayInitialize(SellBuf, EMPTY_VALUE);
      ArrayInitialize(DirBuf, 0);
      ArrayInitialize(ScoreBuf, EMPTY_VALUE);
      gFirst = MathMax(InpATRPeriod + InpADXPeriod + 2 * InpSwingLen + 2, rates_total - InpMaxBars);
      start = gFirst;
     }
   else
      start = MathMax(prev_calculated - 1, gFirst);

   //--- ATR trailing stop + reversal signals
   for(int i = start; i < rates_total; i++)
     {
      double atr = AtrBuf[i];
      BuyBuf[i]   = EMPTY_VALUE;
      SellBuf[i]  = EMPTY_VALUE;
      ScoreBuf[i] = EMPTY_VALUE;

      if(i == gFirst)
        {
         DirBuf[i]   = 1;
         TrailBuf[i] = close[i] - m * atr;
         TrailClr[i] = 0;
         continue;
        }

      int    pd = (int)DirBuf[i - 1];
      double pt = TrailBuf[i - 1];
      int    d  = pd;
      double t  = pt;
      if(pd >= 0)
        {
         if(close[i] < pt) { d = -1; t = close[i] + m * atr; }
         else               t = MathMax(pt, close[i] - m * atr);
        }
      else
        {
         if(close[i] > pt) { d = 1; t = close[i] - m * atr; }
         else               t = MathMin(pt, close[i] + m * atr);
        }
      DirBuf[i]   = d;
      TrailBuf[i] = t;
      TrailClr[i] = (d > 0) ? 0 : 1;

      bool closedBar = (i < rates_total - 1);
      if(d != pd && (closedBar || !InpConfirmedOnly))
        {
         double sc = ComputeScore(i, d, time, high, low, close);
         if(InpMode == FR_AGGRESSIVE || sc >= InpMinScore)
           {
            ScoreBuf[i] = sc;
            if(d > 0)
               BuyBuf[i] = low[i] - 0.3 * atr;
            else
               SellBuf[i] = high[i] + 0.3 * atr;
           }
        }
     }

   int last = rates_total - 1;

   //--- alerts (only once per signal bar, not on first load)
   int ab = InpConfirmedOnly ? last - 1 : last;
   if(!full && ab >= gFirst && time[ab] != gLastAlert &&
      (BuyBuf[ab] != EMPTY_VALUE || SellBuf[ab] != EMPTY_VALUE))
     {
      gLastAlert = time[ab];
      string side = (BuyBuf[ab] != EMPTY_VALUE) ? "BUY" : "SELL";
      string msg  = StringFormat("Fast Reversal %s %s %s @ %s (score %.1f)",
                                 _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period), side,
                                 DoubleToString(close[ab], _Digits), ScoreBuf[ab]);
      if(InpAlertPopup)
         Alert(msg);
      if(InpAlertPush)
         SendNotification(msg);
     }

   //--- last signal and its levels
   int sig = -1;
   for(int j = last; j >= gFirst; j--)
      if(BuyBuf[j] != EMPTY_VALUE || SellBuf[j] != EMPTY_VALUE)
        {
         sig = j;
         break;
        }

   string sigText = "NONE", statusText = "WAITING", setupText = "-";
   color  sigColor = InpTextColor, statusColor = InpTextColor;

   if(sig >= 0)
     {
      int    d     = (BuyBuf[sig] != EMPTY_VALUE) ? 1 : -1;
      double entry = close[sig];
      double risk  = TrailBuf[sig];
      double R     = MathAbs(entry - risk);
      if(R <= 0)
         R = AtrBuf[sig];
      double zone2 = entry - d * InpZoneATR * AtrBuf[sig];
      if(d > 0)
         zone2 = MathMax(zone2, risk + 0.25 * R);
      else
         zone2 = MathMin(zone2, risk - 0.25 * R);
      double tp1 = entry + d * R * InpTP1;
      double tp2 = entry + d * R * InpTP2;
      double tp3 = entry + d * R * InpTP3;

      //--- trade status since the signal bar
      int  hit = 0;
      bool stopped = false;
      for(int j = sig + 1; j <= last; j++)
        {
         double adv = (d > 0) ? low[j] : high[j];
         double fav = (d > 0) ? high[j] : low[j];
         // adverse move checked first (worst case inside a bar)
         if(d * (adv - risk) <= 0)
           {
            stopped = true;
            break;
           }
         if(d * (fav - tp3) >= 0)
            hit = 3;
         else if(d * (fav - tp2) >= 0)
            hit = MathMax(hit, 2);
         else if(d * (fav - tp1) >= 0)
            hit = MathMax(hit, 1);
         if(hit == 3)
            break;
        }

      if(stopped && hit == 0)
        { statusText = "STOPPED";                              statusColor = clrTomato; }
      else if(stopped)
        { statusText = "CLOSED AFTER TP" + IntegerToString(hit); statusColor = clrGold; }
      else if(hit == 3)
        { statusText = "COMPLETED (END)";                      statusColor = clrLime; }
      else if(hit > 0)
        { statusText = "TP" + IntegerToString(hit) + " HIT";   statusColor = clrLime; }
      else
        { statusText = "ACTIVE";                               statusColor = clrDeepSkyBlue; }

      sigText   = (d > 0) ? "BUY" : "SELL";
      sigColor  = (d > 0) ? clrLime : clrTomato;
      setupText = StringFormat("%s %.1f %s", sigText, ScoreBuf[sig], Arrow(d));

      if(InpShowLevels)
        {
         datetime t1 = time[sig];
         datetime t2 = time[last] + (datetime)(InpExtendBars * PeriodSeconds());
         DrawZone(t1, t2, entry, zone2);
         DrawLevel("tp3",  "END",       tp3,   clrLimeGreen,   t1, t2);
         DrawLevel("tp2",  "TP2",       tp2,   clrLimeGreen,   t1, t2);
         DrawLevel("tp1",  "TP1",       tp1,   clrLimeGreen,   t1, t2);
         DrawLevel("hi",   (d > 0) ? "HIGH ZONE" : "LOW ZONE",  entry, clrDarkTurquoise, t1, t2);
         DrawLevel("lo",   (d > 0) ? "LOW ZONE"  : "HIGH ZONE", zone2, clrDarkTurquoise, t1, t2);
         DrawLevel("risk", "RISK",      risk,  clrRed,         t1, t2);
        }
     }

   //--- panel
   if(InpShowPanel)
     {
      int curDir = (int)DirBuf[last];
      int c1 = ContextBias(hC1Fast, hC1Slow, InpCtx1TF, time[last]);
      int c2 = ContextBias(hC2Fast, hC2Slow, InpCtx2TF, time[last]);
      int st = StructureBias(last, high, low, close);
      int sum = c1 + c2 + st + curDir;
      int mb = (sum >= 2) ? 1 : (sum <= -2) ? -1 : 0;

      double live = ComputeScore(last, curDir, time, high, low, close);
      string liveText = StringFormat("%s %.1f %s", (curDir > 0) ? "BUY" : "SELL", live, Arrow(curDir));

      double atrSum = 0;
      for(int k = 0; k < InpVolLookback; k++)
         atrSum += AtrBuf[last - k];
      double ratio = (atrSum > 0) ? AtrBuf[last] / (atrSum / InpVolLookback) : 1.0;
      string volText = (ratio < 0.8) ? "LOW" : (ratio > 1.3) ? "HIGH" : "NORMAL";
      color  volColor = (ratio > 1.3) ? clrOrange : InpTextColor;

      double adxNow  = AdxBuf[last - 1];
      double adxPrev = AdxBuf[last - 4];
      string momText = StringFormat("%s %.1f", (adxNow > adxPrev) ? "STRENGTHENING" : "WEAKENING", adxNow);
      color  momColor = (adxNow > adxPrev) ? clrLime : clrOrange;

      int totalW = COL1_W + COL2_W;
      MakeCell("title", InpPanelX, InpPanelY, totalW, ROW_H, InpTitleBg);
      SetCell("title", "FAST REVERSAL v1.0", InpTextColor);

      PanelRow(0,  "Mode",          (InpMode == FR_AGGRESSIVE) ? "AGGRESSIVE" : "CONSERVATIVE", InpTextColor);
      PanelRow(1,  "Setup",         setupText, sigColor);
      PanelRow(2,  "Live",          liveText, (curDir > 0) ? clrLime : clrTomato);
      PanelRow(3,  "Context 1",     StringFormat("%d (%s)", PeriodSeconds(InpCtx1TF) / 60, BiasText(c1)), BiasColor(c1));
      PanelRow(4,  "Context 2",     StringFormat("%d (%s)", PeriodSeconds(InpCtx2TF) / 60, BiasText(c2)), BiasColor(c2));
      PanelRow(5,  "Market Bias",   BiasText(mb), BiasColor(mb));
      PanelRow(6,  "Volatility",    volText, volColor);
      PanelRow(7,  "Structure Bias", BiasText(st), BiasColor(st));
      PanelRow(8,  "Signal",        sigText, sigColor);
      PanelRow(9,  "Status",        statusText, statusColor);
      PanelRow(10, "Momentum",      momText, momColor);
     }

   ChartRedraw();
   return rates_total;
  }
//+------------------------------------------------------------------+
