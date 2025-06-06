//+------------------------------------------------------------------+
//|               Cipher Twister EA - 100% MetaTrader 5             |
//|        Léger, sans tableau, avec signaux et clôtures inverses   |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

input double LotSize = 0.1;
input double RiskRewardRatio = 2.0;
input int ChannelLength = 10;
input int AverageLength = 21;
input int obLevel2 = 53;
input int osLevel2 = -53;

// Ajuste ce coefficient pour que le Stop Loss respecte les contraintes du broker.
// Exemple de recommandations :
// - Forex avec levier 1:30 → SLMultiplier = 1.0 à 2.0 (par défaut)
// - Indices avec levier 1:20 → SLMultiplier = 3.0 à 5.0
// - Or (XAUUSD) avec levier 1:20 → SLMultiplier = 5.0 à 10.0
// - Crypto (BTCUSD) avec levier 1:1 → SLMultiplier = 10.0 à 20.0 (voire plus)

input double SLMultiplier = 1.0;  // Coefficient multiplicateur pour la taille du SL/TP


//+------------------------------------------------------------------+
//| Récupère HLC3 (typical price) d'une bougie                       |
//+------------------------------------------------------------------+
double GetHLC3(int shift)
{
   double high[1], low[1], close[1];

   if(CopyHigh(_Symbol, _Period, shift, 1, high) <= 0) return 0;
   if(CopyLow(_Symbol, _Period, shift, 1, low) <= 0) return 0;
   if(CopyClose(_Symbol, _Period, shift, 1, close) <= 0) return 0;

   return (high[0] + low[0] + close[0]) / 3.0;
}

//+------------------------------------------------------------------+
//| Calcule EMA manuellement sur 2 valeurs (approx rapide)          |
//+------------------------------------------------------------------+
double CalculateEMA(double current, double previous, int period)
{
   double k = 2.0 / (period + 1);
   return current * k + previous * (1 - k);
}

//+------------------------------------------------------------------+
//| Fonction principale OnTick                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   if(Bars(_Symbol, _Period) < AverageLength + 5)
      return;

   // --- HLC3 (typical price)
   double ap0 = GetHLC3(0);
   double ap1 = GetHLC3(1);

   // --- ESA (EMA de ap)
   static double esa1 = ap1;
   double esa0 = CalculateEMA(ap0, esa1, ChannelLength);

   // --- D (EMA de |ap - esa|)
   double dev0 = MathAbs(ap0 - esa0);
   static double d1 = MathAbs(ap1 - esa1);
   double d0 = CalculateEMA(dev0, d1, ChannelLength);

   // --- CI
   double ci0 = (ap0 - esa0) / (0.015 * MathMax(d0, 0.0001));
   static double ci1 = (ap1 - esa1) / (0.015 * MathMax(d1, 0.0001));

   // --- TCI (EMA de CI)
   static double tci1 = ci1;
   double tci0 = CalculateEMA(ci0, tci1, AverageLength);

   // --- WT1 = TCI, WT2 = SMA 4-périodes (approximée ici)
   static double tci2 = tci1;
   static double tci3 = tci2;
   static double tci4 = tci3;

   double wt1_0 = tci0;
   double wt1_1 = tci1;
   double wt2_0 = (tci0 + tci1 + tci2 + tci3) / 4.0;
   double wt2_1 = (tci1 + tci2 + tci3 + tci4) / 4.0;

   // --- Signaux
   bool buySignal = wt1_1 < wt2_1 && wt1_0 > wt2_0 && wt1_0 < osLevel2;
   bool sellSignal = wt1_1 > wt2_1 && wt1_0 < wt2_0 && wt1_0 > obLevel2;

   // --- Clôture si signal inverse
   if(PositionSelect(_Symbol))
   {
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ulong ticket = PositionGetInteger(POSITION_TICKET);

      if((posType == POSITION_TYPE_BUY && sellSignal) ||
         (posType == POSITION_TYPE_SELL && buySignal))
      {
         tradeClose(ticket);
         return;
      }

      return;
   }

   // --- Entrée de position
   
  double rawSL = 100 * _Point * SLMultiplier;

if(buySignal)
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = entry - rawSL;
   double tp = entry + RiskRewardRatio * (entry - sl);
   tradeOpen(ORDER_TYPE_BUY, entry, sl, tp);
}

if(sellSignal)
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = entry + rawSL;
   double tp = entry - RiskRewardRatio * (sl - entry);
   tradeOpen(ORDER_TYPE_SELL, entry, sl, tp);
}

   // --- MAJ des historiques pour la prochaine bougie
   esa1 = esa0;
   d1 = d0;
   ci1 = ci0;
   tci4 = tci3;
   tci3 = tci2;
   tci2 = tci1;
   tci1 = tci0;
}

//+------------------------------------------------------------------+
//| Ouvre une position                                               |
//+------------------------------------------------------------------+
void tradeOpen(ENUM_ORDER_TYPE type, double entryPrice, double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   // Obtenir les infos de l’actif
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   // Corriger SL/TP si trop proches
   if(MathAbs(entryPrice - sl) < stopLevel)
   {
      if(type == ORDER_TYPE_BUY)
         sl = entryPrice - stopLevel;
      else
         sl = entryPrice + stopLevel;
   }

   if(MathAbs(tp - entryPrice) < stopLevel)
   {
      if(type == ORDER_TYPE_BUY)
         tp = entryPrice + stopLevel;
      else
         tp = entryPrice - stopLevel;
   }

   // Normalisation
   entryPrice = NormalizeDouble(entryPrice, digits);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Construction requête
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = type;
   request.price = entryPrice;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;

   // Mode de remplissage (sécurité : vérifier si FOK est autorisé)
   if(SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE) == ORDER_FILLING_FOK)
      request.type_filling = ORDER_FILLING_FOK;
   else
      request.type_filling = ORDER_FILLING_IOC;

   // Envoi
   if(!OrderSend(request, result))
   {
      Print("❌ Erreur ouverture ordre : ", result.retcode, " / ", result.comment);
   }
   else
   {
      Print("✅ Ordre envoyé avec succès : ticket=", result.order, " type=", type);
   }
}
//+------------------------------------------------------------------+
//| Ferme une position                                               |
//+------------------------------------------------------------------+
void tradeClose(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.position = ticket;
   request.volume   = volume;
   request.price    = NormalizeDouble(price, _Digits);
   request.type     = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request, result))
      Print("Erreur fermeture : ", result.retcode, " ", result.comment);
}