//+------------------------------------------------------------------+
//|               SandRBot_Pending_ATR_Improved_Trailing.mq5        |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;

//--- Inputs
input double ATR_Multiplier         = 1.6;   // SL = pivot ± ATR×multiplicateur
input int    PendingExpirationHours = 24;    // durée de vie des pendings (h)
input bool   ShowDebug              = false; // logs debug
input int    LeftBars               = 15;    // barres à gauche du pivot
input int    RightBars              = 15;    // barres à droite du pivot
input int    LineLength             = 20;    // longueur de la ligne en barres
input double LotSize                = 0.01;  // taille de lot

//--- Trailing Stop Inputs
input bool   EnableTrailingStop     = true;  // activer/désactiver trailing stop
input int    TrailingStartPips      = 20;    // activer trailing au-delà de X pips de profit
input int    TrailingStopLossPips   = 10;    // placer le SL à Y pips derrière le prix courant

//--- États globaux
int    atr_handle    = INVALID_HANDLE;
int    obj_counter   = 0;

//+------------------------------------------------------------------+
//| Helper : arrondi au tick_size                                    |
//+------------------------------------------------------------------+
double NormalizeToTick(double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0)
      tick = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return MathFloor(price / tick) * tick;
}

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
   if(shift + LeftBars >= ArraySize(h) || shift - RightBars < 0)
      return false;

   double v = h[shift];
   for(int i = 1; i <= LeftBars;  i++) if(h[shift + i] >= v) return false;
   for(int i = 1; i <= RightBars; i++) if(h[shift - i] >= v) return false;
   return true;
}
bool IsPivotLow(const double &l[], int shift)
{
   if(shift + LeftBars >= ArraySize(l) || shift - RightBars < 0)
      return false;

   double v = l[shift];
   for(int i = 1; i <= LeftBars;  i++) if(l[shift + i] <= v) return false;
   for(int i = 1; i <= RightBars; i++) if(l[shift - i] <= v) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Évalue la qualité d'un pivot haut                                |
//+------------------------------------------------------------------+
double EvaluatePivotHighQuality(const double &h[], const long &volume[], int shift)
{
   if(!IsPivotHigh(h, shift)) return 0;
   double pivotPrice = h[shift], quality = 0, avgDiff = 0;

   for(int i = 1; i <= LeftBars;  i++) avgDiff += (pivotPrice - h[shift + i]);
   for(int i = 1; i <= RightBars; i++) avgDiff += (pivotPrice - h[shift - i]);
   avgDiff /= (LeftBars + RightBars);
   quality += avgDiff * 2;

   if(volume[shift] > 0)
   {
      double avgVolume = 0;
      for(int i = 1; i <= 5; i++)
         if(i <= shift)
            avgVolume += volume[i];
      avgVolume /= 5;
      if(volume[shift] > avgVolume)
         quality += ((double)volume[shift]/avgVolume - 1)*3;
   }

   for(int i = shift + LeftBars + 1; i < ArraySize(h) - RightBars; i++)
   {
      if(IsPivotHigh(h, i))
      {
         double priceDiff = MathAbs(h[i] - pivotPrice);
         if(priceDiff < GetATR()*0.5)
         {
            quality += 5;
            break;
         }
      }
   }
   return quality;
}

//+------------------------------------------------------------------+
//| Évalue la qualité d'un pivot bas                                 |
//+------------------------------------------------------------------+
double EvaluatePivotLowQuality(const double &l[], const long &volume[], int shift)
{
   if(!IsPivotLow(l, shift)) return 0;
   double pivotPrice = l[shift], quality = 0, avgDiff = 0;

   for(int i = 1; i <= LeftBars;  i++) avgDiff += (l[shift + i] - pivotPrice);
   for(int i = 1; i <= RightBars; i++) avgDiff += (l[shift - i] - pivotPrice);
   avgDiff /= (LeftBars + RightBars);
   quality += avgDiff * 2;

   if(volume[shift] > 0)
   {
      double avgVolume = 0;
      for(int i = 1; i <= 5; i++)
         if(i <= shift)
            avgVolume += volume[i];
      avgVolume /= 5;
      if(volume[shift] > avgVolume)
         quality += ((double)volume[shift]/avgVolume - 1)*3;
   }

   for(int i = shift + LeftBars + 1; i < ArraySize(l) - RightBars; i++)
   {
      if(IsPivotLow(l, i))
      {
         double priceDiff = MathAbs(l[i] - pivotPrice);
         if(priceDiff < GetATR()*0.5)
         {
            quality += 5;
            break;
         }
      }
   }
   return quality;
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
//| 1) Récupère jusqu'à 500 barres                                   |
//+------------------------------------------------------------------+
int FetchRates(MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   return CopyRates(_Symbol, PERIOD_CURRENT, 0, 500, rates);
}

//+------------------------------------------------------------------+
//| 2) Copie high[] et low[] en "séries"                             |
//+------------------------------------------------------------------+
void CopyHighLow(int count, double &high[], double &low[])
{
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low,  true);
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, count, high);
   CopyLow (_Symbol, PERIOD_CURRENT, 0, count, low);
}

//+------------------------------------------------------------------+
//| 3a) Trouve le shift du dernier support                           |
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
//| 3b) Trouve le shift de la dernière résistance                    |
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
      if(ticket <= 0 || !OrderSelect(ticket)) continue;
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
//| 5a) Place un BUY_LIMIT au support                                |
//+------------------------------------------------------------------+
void PlaceBuyLimit(double support, double resistance)
{
   double atr = GetATR();
   if(atr <= 0) { Print("ATR invalide"); return; }

   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stop_lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)
                    * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double price_raw = support;
   double sl_raw    = support - ATR_Multiplier * atr;
   double tp_raw    = resistance;

   double price = NormalizeToTick(price_raw);
   double sl    = NormalizeToTick(sl_raw);
   double tp    = NormalizeToTick(tp_raw);

   if(price >= bid - stop_lvl)
   {
      if(ShowDebug)
         PrintFormat("BuyLimit invalide: price=%.5f bid=%.5f stop_lvl=%.5f",
                     price, bid, stop_lvl);
      return;
   }

   datetime expi = TimeCurrent() + PendingExpirationHours * 3600;
   bool ok = trade.BuyLimit(LotSize, price, _Symbol, sl, tp,
                            ORDER_TIME_GTC, expi);
   if(!ok)
      PrintFormat("Erreur BUY_LIMIT code=%d msg=%s",
                  trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
   else if(ShowDebug)
      PrintFormat("BUY_LIMIT @%.5f SL=%.5f TP=%.5f exp=%s",
                  price, sl, tp,
                  TimeToString(expi, TIME_DATE|TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| 5b) Place un SELL_LIMIT à la résistance                          |
//+------------------------------------------------------------------+
void PlaceSellLimit(double resistance, double support)
{
   double atr = GetATR();
   if(atr <= 0) { Print("ATR invalide"); return; }

   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stop_lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)
                    * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double price_raw = resistance;
   double sl_raw    = resistance + ATR_Multiplier * atr;
   double tp_raw    = support;

   double price = NormalizeToTick(price_raw);
   double sl    = NormalizeToTick(sl_raw);
   double tp    = NormalizeToTick(tp_raw);

   if(price <= ask + stop_lvl)
   {
      if(ShowDebug)
         PrintFormat("SellLimit invalide: price=%.5f ask=%.5f stop_lvl=%.5f",
                     price, ask, stop_lvl);
      return;
   }

   datetime expi = TimeCurrent() + PendingExpirationHours * 3600;
   bool ok = trade.SellLimit(LotSize, price, _Symbol, sl, tp,
                             ORDER_TIME_GTC, expi);
   if(!ok)
      PrintFormat("Erreur SELL_LIMIT code=%d msg=%s",
                  trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
   else if(ShowDebug)
      PrintFormat("SELL_LIMIT @%.5f SL=%.5f TP=%.5f exp=%s",
                  price, sl, tp,
                  TimeToString(expi, TIME_DATE|TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| Gestion du trailing stop                                        |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!PositionSelect(_Symbol))
      return;

   ulong  ticket       = PositionGetInteger(POSITION_TICKET);
   int    type         = (int)PositionGetInteger(POSITION_TYPE);
   double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = (type == POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // profit en pips
   double profitPips = (type == POSITION_TYPE_BUY)
                       ? (currentPrice - openPrice) / point
                       : (openPrice - currentPrice) / point;

   if(profitPips >= TrailingStartPips)
   {
      double rawNewSL = (type == POSITION_TYPE_BUY)
                        ? currentPrice - TrailingStopLossPips * point
                        : currentPrice + TrailingStopLossPips * point;
      double newSL = NormalizeToTick(rawNewSL);
      double oldSL = PositionGetDouble(POSITION_SL);
      bool   modify = false;

      if(type == POSITION_TYPE_BUY && newSL > oldSL)
         modify = true;
      if(type == POSITION_TYPE_SELL && newSL < oldSL)
         modify = true;

      if(modify)
      {
         double tp = PositionGetDouble(POSITION_TP);
         if(trade.PositionModify(ticket, newSL, tp) && ShowDebug)
            PrintFormat("Trailing SL modifié: ancienne=%.5f, nouvelle=%.5f", oldSL, newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Fonction principale                                             |
//+------------------------------------------------------------------+
void DetectAndTrade()
{
   bool cantrade = true;

   if(PositionSelect(_Symbol))
   {
      if(ShowDebug)
         PrintFormat("Position déjà ouverte sur %s, skip.", _Symbol);
      cantrade = false;
   }

   MqlRates rates[];
   int copied = FetchRates(rates);
   if(copied < RightBars + 1) return;

   double high[], low[];
   long   volume[];
   CopyHighLow(copied, high, low);
   ArraySetAsSeries(volume, true);
   CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, copied, volume);

   int sShift = 0, rShift = 0;
   bool support_found    = FindLatestSupport(low, copied, sShift);
   bool resistance_found = FindLatestResistance(high, copied, rShift);

   if(support_found)
      CreatePivotLine(rates[sShift].time,
                      rates[sShift + LineLength].time,
                      low[sShift], clrBlue);
   if(resistance_found)
      CreatePivotLine(rates[rShift].time,
                      rates[rShift + LineLength].time,
                      high[rShift], clrRed);

   CleanupPendingOrders();

   if(cantrade)
   {
      if(support_found && resistance_found)
      {
         double supportQuality    = EvaluatePivotLowQuality(low, volume, sShift);
         double resistanceQuality = EvaluatePivotHighQuality(high, volume, rShift);
         if(ShowDebug)
            PrintFormat("Qualités - Support: %.2f, Résistance: %.2f",
                        supportQuality, resistanceQuality);
         if(supportQuality >= resistanceQuality)
            PlaceBuyLimit(low[sShift], high[rShift]);
         else
            PlaceSellLimit(high[rShift], low[sShift]);
      }
      else if(support_found)
         PlaceBuyLimit(low[sShift], high[rShift]);
      else if(resistance_found)
         PlaceSellLimit(high[rShift], low[sShift]);
   }
}

//+------------------------------------------------------------------+
//| Tick principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   DetectAndTrade();
   if(EnableTrailingStop)
      ManageTrailingStop();  // gestion du trailing stop
}
