//+------------------------------------------------------------------+
//|                    SandRBot_Pending_ATR_Optimized.mq5            |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
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
int    atr_handle    = INVALID_HANDLE;
int    obj_counter   = 0;

//--- Variables pour l'optimisation
datetime last_candle_time = 0;      // Heure de la dernière bougie analysée
double   last_support = 0;          // Dernier niveau de support trouvé
double   last_resistance = 0;       // Dernier niveau de résistance trouvé
bool     support_valid = false;     // Indique si le support est valide
bool     resistance_valid = false;  // Indique si la résistance est valide

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
      
   // Réinitialiser les variables d'optimisation
   last_candle_time = 0;
   last_support = 0;
   last_resistance = 0;
   support_valid = false;
   resistance_valid = false;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Libération à la fermeture                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
      
   // Nettoyer les objets graphiques
   ObjectsDeleteAll(0, "PivotLine_");
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
//| 1) Récupère le nombre minimum de barres nécessaires              |
//+------------------------------------------------------------------+
int FetchRates(MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   // Calcul du nombre minimum de barres nécessaires
   int minBars = MathMax(LeftBars + RightBars + LineLength + 10, 100);
   // Limiter à un maximum de 500 barres
   minBars = MathMin(minBars, 500);
   return CopyRates(_Symbol, PERIOD_CURRENT, 0, minBars, rates);
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
//| 5a) Place un BUY_LIMIT au support                                 |
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
//| 5b) Place un SELL_LIMIT à la résistance                           |
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
//| 6) Fonction principale - détection et trading                    |
//+------------------------------------------------------------------+
void DetectAndTrade()
{
   // Nettoyer les objets graphiques existants
   ObjectsDeleteAll(0, "PivotLine_");
   obj_counter = 0;
   
   bool cantrade = true;

   //--- n'ouvre rien si une position existe déjà
   if(PositionSelect(_Symbol))
   {
      if(ShowDebug)
         PrintFormat("Position déjà ouverte sur %s, skip.", _Symbol);
      cantrade = false;
   }

   // a) Fetch & Copy
   MqlRates rates[];
   int copied = FetchRates(rates);
   if(copied < RightBars + LeftBars + 1)
   {
      if(ShowDebug)
         PrintFormat("Pas assez de barres copiées: %d", copied);
      return;
   }

   double high[], low[];
   CopyHighLow(copied, high, low);

   // b) Find pivots
   int sShift = 0, rShift = 0;
   support_valid = FindLatestSupport(low, copied, sShift);
   resistance_valid = FindLatestResistance(high, copied, rShift);

   // c) Draw lines and save values
   if(support_valid)
   {
      last_support = low[sShift];
      CreatePivotLine(rates[sShift].time,
                      rates[MathMin(sShift + LineLength, copied-1)].time,
                      last_support,
                      clrBlue);
      if(ShowDebug)
         PrintFormat("Support trouvé: %.5f à %s", last_support, 
                     TimeToString(rates[sShift].time, TIME_DATE|TIME_MINUTES));
   }
   
   if(resistance_valid)
   {
      last_resistance = high[rShift];
      CreatePivotLine(rates[rShift].time,
                      rates[MathMin(rShift + LineLength, copied-1)].time,
                      last_resistance,
                      clrRed);
      if(ShowDebug)
         PrintFormat("Résistance trouvée: %.5f à %s", last_resistance, 
                     TimeToString(rates[rShift].time, TIME_DATE|TIME_MINUTES));
   }

   // d) Cleanup pendings
   CleanupPendingOrders();

   if(cantrade)
   {
      // e) Place exactly one pending order
      if(support_valid && resistance_valid)
      {
         if(sShift < rShift)
            PlaceBuyLimit(last_support, last_resistance);
         else
            PlaceSellLimit(last_resistance, last_support);
      }
      else if(support_valid)
         PlaceBuyLimit(last_support, last_resistance);
      else if(resistance_valid)
         PlaceSellLimit(last_resistance, last_support);
   }
}

//+------------------------------------------------------------------+
//| Tick principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   // Vérifier si une nouvelle bougie est formée
   datetime current_candle_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Première exécution ou nouvelle bougie
   if(current_candle_time != last_candle_time)
   {
      if(ShowDebug)
         PrintFormat("Nouvelle bougie détectée, analyse des pivots...");
         
      // Mettre à jour le repère temporel
      last_candle_time = current_candle_time;
      
      // Détection des supports/résistances et placement des ordres
      DetectAndTrade();
   }
}