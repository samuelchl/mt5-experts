//+------------------------------------------------------------------+
//|                          SandRBot_Pending_ATR.mq5                |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs
input int    LeftBars               = 15;    // barres à gauche du pivot
input int    RightBars              = 15;    // barres à droite du pivot
input int    LineLength             = 20;    // longueur de la ligne en barres
input double LotSize                = 0.01;  // taille de lot
input double ATR_Multiplier         = 1.6;   // SL = pivot ± ATR×multiplicateur
input int    PendingExpirationHours = 24;    // durée de vie des pendings (h)
input bool   ShowDebug              = false; // logs debug

//--- États globaux
int    atr_handle       = INVALID_HANDLE;
double current_support  = 0.0;
double current_resistance = 0.0;
int    obj_counter      = 0;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
  if(atr_handle == INVALID_HANDLE)
     Print("Erreur création ATR handle");
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Libération à la fermeture                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  if(atr_handle != INVALID_HANDLE)
     IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Récupère l'ATR courant                                           |
//+------------------------------------------------------------------+
double GetATR()
{
  double buf[1];
  return(CopyBuffer(atr_handle, 0, 0, 1, buf) == 1 ? buf[0] : 0.0);
}

//+------------------------------------------------------------------+
//| Test de pivot haut / bas                                         |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &h[], int shift)
{
  double v = h[shift];
  for(int i = 1; i <= LeftBars;  i++) if(h[shift + i] >= v) return false;
  for(int i = 1; i <= RightBars; i++) if(h[shift - i] >= v) return false;
  return true;
}
bool IsPivotLow(const double &l[], int shift)
{
  double v = l[shift];
  for(int i = 1; i <= LeftBars;  i++) if(l[shift + i] <= v) return false;
  for(int i = 1; i <= RightBars; i++) if(l[shift - i] <= v) return false;
  return true;
}

//+------------------------------------------------------------------+
//| Trace une ligne de pivot                                         |
//+------------------------------------------------------------------+
void CreatePivotLine(datetime t0, datetime t1, double price, color clr)
{
  string name = "PivotLine_" + IntegerToString(obj_counter++);
  if(ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t1, price))
  {
    ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,     2);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
  }
}

//+------------------------------------------------------------------+
//| 1) Récupère jusqu’à 500 barres                                   |
//+------------------------------------------------------------------+
int FetchRates(MqlRates &rates[])
{
  ArraySetAsSeries(rates, true);
  return CopyRates(_Symbol, PERIOD_CURRENT, 0, 500, rates);
}

//+------------------------------------------------------------------+
//| 2) Copie high[] et low[] en "séries"                              |
//+------------------------------------------------------------------+
void CopyHighLow(int count, double &high[], double &low[])
{
  ArraySetAsSeries(high, true);
  ArraySetAsSeries(low,  true);
  CopyHigh(_Symbol, PERIOD_CURRENT, 0, count, high);
  CopyLow (_Symbol, PERIOD_CURRENT, 0, count, low);
}

//+------------------------------------------------------------------+
//| 3a) Trouve le shift du dernier support                            |
//+------------------------------------------------------------------+
bool FindLatestSupport(const double &low[], int count, int &outShift)
{
  int minS = RightBars;
  int maxS = MathMin(count - LeftBars - 1, count - LineLength - 1);
  for(int s = minS; s <= maxS; s++)
    if(IsPivotLow(low, s))
    {
      outShift = s;
      return true;
    }
  return false;
}

//+------------------------------------------------------------------+
//| 3b) Trouve le shift de la dernière résistance                     |
//+------------------------------------------------------------------+
bool FindLatestResistance(const double &high[], int count, int &outShift)
{
  int minS = RightBars;
  int maxS = MathMin(count - LeftBars - 1, count - LineLength - 1);
  for(int s = minS; s <= maxS; s++)
    if(IsPivotHigh(high, s))
    {
      outShift = s;
      return true;
    }
  return false;
}

//+------------------------------------------------------------------+
//| 4) Supprime tous les pendings BUY_LIMIT & SELL_LIMIT             |
//+------------------------------------------------------------------+
void CleanupPendingOrders()
{
  int total = OrdersTotal();
  for(int i = total - 1; i >= 0; i--)
  {
    ulong ticket = OrderGetTicket(i);
    if(ticket <= 0 || !OrderSelect(ticket))
      continue;
    int type   = (int)OrderGetInteger(ORDER_TYPE);
    string sym = OrderGetString(ORDER_SYMBOL);
    if(sym == _Symbol &&
       (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT))
    {
      if(trade.OrderDelete(ticket) && ShowDebug)
        PrintFormat("Pending #%I64u supprimé (type=%d)", ticket, type);
    }
  }
}

//+------------------------------------------------------------------+
//| 5a) Place un BUY_LIMIT au support                                 |
//+------------------------------------------------------------------+
void PlaceBuyLimit(double support, double resistance)
{
  double atr    = GetATR();
  double sl     = NormalizeDouble(support - ATR_Multiplier * atr, _Digits);
  double tp     = NormalizeDouble(resistance,                    _Digits);
  datetime expi = TimeCurrent() + PendingExpirationHours * 3600;
  if(trade.BuyLimit(
       LotSize,
       support,
       _Symbol,
       sl,
       tp,
       ORDER_TIME_GTC,
       expi
     ) && ShowDebug)
    PrintFormat("BUY_LIMIT @%.5f SL=%.5f TP=%.5f exp=%s",
                support, sl, tp,
                TimeToString(expi, TIME_DATE|TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| 5b) Place un SELL_LIMIT à la résistance                           |
//+------------------------------------------------------------------+
void PlaceSellLimit(double resistance, double support)
{
  double atr    = GetATR();
  double sl     = NormalizeDouble(resistance + ATR_Multiplier * atr, _Digits);
  double tp     = NormalizeDouble(support,                       _Digits);
  datetime expi = TimeCurrent() + PendingExpirationHours * 3600;
  if(trade.SellLimit(
       LotSize,
       resistance,
       _Symbol,
       sl,
       tp,
       ORDER_TIME_GTC,
       expi
     ) && ShowDebug)
    PrintFormat("SELL_LIMIT @%.5f SL=%.5f TP=%.5f exp=%s",
                resistance, sl, tp,
                TimeToString(expi, TIME_DATE|TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| 6) Fonction principale                                           |
//+------------------------------------------------------------------+
void DetectAndTrade()
{
  // a) Fetch & Copy
  MqlRates rates[];      int copied = FetchRates(rates);
  if(copied < RightBars + 1) return;
  double high[], low[];  CopyHighLow(copied, high, low);

  // b) Find pivots
  int sShift = 0, rShift = 0;
  bool support_found    = FindLatestSupport(low,  copied, sShift);
  bool resistance_found = FindLatestResistance(high, copied, rShift);

  // c) Draw lines
  if(support_found)
    CreatePivotLine(rates[sShift].time,
                    rates[sShift + LineLength].time,
                    low[sShift],
                    clrBlue);
  if(resistance_found)
    CreatePivotLine(rates[rShift].time,
                    rates[rShift + LineLength].time,
                    high[rShift],
                    clrRed);

  // d) Cleanup pendings
  CleanupPendingOrders();

  // e) Place exactly one pending order
  if(support_found && resistance_found)
  {
    // pivot le plus récent = plus petit shift
    if(sShift < rShift)
      PlaceBuyLimit(low[sShift], high[rShift]);
    else
      PlaceSellLimit(high[rShift], low[sShift]);
  }
  else if(support_found)
    PlaceBuyLimit(low[sShift], high[rShift]);
  else if(resistance_found)
    PlaceSellLimit(high[rShift], low[sShift]);
}

//+------------------------------------------------------------------+
//| Tick principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
  DetectAndTrade();
}
