#include <Trade\Trade.mqh>
CTrade trade;

// === Inputs principaux ===
input int wmaFastPeriod = 8;
input int wmaSlowPeriod = 38;
input int wmaTrendPeriod = 200;
input ENUM_MA_METHOD maMethod = MODE_LWMA;

input double lotSize = 0.1;
input double RiskRewardRatio = 2.0;

input int atrPeriod = 14;
input double atrSLMultiplier = 1.5;

input double proximityATRPercent = 3.0;
input double ecartementATRPercent = 5.0;

// === Filtres activables ===
input bool useCooldown        = true;
input bool useSpreadFilter    = true;
input bool useSpreadATR       = true;
input bool useATRFilter       = true;

input bool useTrendFilterBuy  = true;
input bool useTrendFilterSell = true;

// === Paramètres filtres ===
input double cooldownMinutes = 30.0;
input double spreadATRPercent = 30.0;
input double atrMinimum = 0.00005;

input bool useCandleFilter     = true;           // Active le filtre bougie
input double candleBodyATRMin = 10.0;            // % min du corps par rapport à l'ATR

input bool useTrailingSL          = true;     // Active le SL dynamique
input double trailingTriggerATR   = 1.0;       // Seuil de déclenchement en ATR (ex: 1.0 = +1 ATR)
input double trailingOffsetATR    = 0.2;       // Offset du SL en gain (ex: +0.2 ATR)

input bool usePartialTP         = true;
input double partialTP_RR       = 5.0;     // Niveau de RR pour prise partielle
input double partialTP_fraction = 0.25;    // Fraction à clôturer (ex: 0.25 = 25%)
input bool debugmode = false;

datetime lastTradeTime = 0;

// === Variables dynamiques de suivi ===
double proxMin = DBL_MAX;
double proxMax = DBL_MIN;
double ecartMin = DBL_MAX;
double ecartMax = DBL_MIN;

// === Récupère la valeur MA en MQL5 ===
double GetMAValue(int period, int shift)
{
   int handle = iMA(_Symbol, _Period, period, 0, maMethod, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return 0;

   double buffer[1];
   if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0) return 0;

   return buffer[0];
}

double MAMethodDiff(int shift)
{
   double fast = GetMAValue(wmaFastPeriod, shift);
   double slow = GetMAValue(wmaSlowPeriod, shift);
   return (fast - slow);
}

bool RejetBrusqueBuy(double seuilProximite, double seuilEcartement)
{
   int i = 1;
   double d0 = MAMethodDiff(i);
   double d1 = MAMethodDiff(i + 1);
   double d2 = MAMethodDiff(i + 2);

   double prox = MathAbs(d1);
   double ecart = d0 - d1;

   // Update dynamiques
   if(prox < proxMin) proxMin = prox;
   if(prox > proxMax) proxMax = prox;
   if(ecart < ecartMin) ecartMin = ecart;
   if(ecart > ecartMax) ecartMax = ecart;

   return (MathAbs(d2) > MathAbs(d1)) && (prox < seuilProximite) && (ecart > seuilEcartement);
}

bool RejetBrusqueSell(double seuilProximite, double seuilEcartement)
{
   int i = 1;
   double d0 = MAMethodDiff(i);
   double d1 = MAMethodDiff(i + 1);
   double d2 = MAMethodDiff(i + 2);

   double prox = MathAbs(d1);
   double ecart = d0 - d1;

   if(prox < proxMin) proxMin = prox;
   if(prox > proxMax) proxMax = prox;
   if(ecart < ecartMin) ecartMin = ecart;
   if(ecart > ecartMax) ecartMax = ecart;

   return (MathAbs(d2) > MathAbs(d1)) && (prox < seuilProximite) && (ecart < -seuilEcartement);
}

void tradeOpen(ENUM_ORDER_TYPE type, double entry, double atr)
{
   double sl = 0, tp = 0;
   double stopDist = atr * atrSLMultiplier;

   if(type == ORDER_TYPE_BUY)
   {
      sl = entry - stopDist;
      tp = entry + stopDist * RiskRewardRatio;
   }
   else
   {
      sl = entry + stopDist;
      tp = entry - stopDist * RiskRewardRatio;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   if(!PositionSelect(_Symbol))
   {
      trade.SetDeviationInPoints(10);
      bool sent = trade.PositionOpen(_Symbol, type, lotSize, entry, sl, tp, "Rejet");

      if(sent)
         Print("✅ Trade : ", EnumToString(type), " | Entry: ", entry, " SL: ", sl, " TP: ", tp);
      else
         Print("❌ Erreur trade : ", trade.ResultRetcode(), " / ", trade.ResultRetcodeDescription());
   }
}

void PrintDebug(string Message){
 if (debugmode)
      Print(Message);

}

void OnTick()
{
   if(PositionSelect(_Symbol)) return;

   // Cooldown
   if(useCooldown && TimeCurrent() - lastTradeTime < cooldownMinutes * 60)
   {
      PrintDebug("⏱️ Cooldown actif");
      return;
   }

   // ATR
   int atrHandle = iATR(_Symbol, _Period, atrPeriod);
   if(atrHandle == INVALID_HANDLE)
   {
      PrintDebug("❌ ATR handle invalide");
      return;
   }

   double atr[1];
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) return;
   double atrValue = atr[0];

   if(useATRFilter && atrValue < atrMinimum)
   {
      PrintDebug("📉 ATR trop faible : "+ DoubleToString(atrValue));
      return;
   }

   // Spread
   if(useSpreadFilter)
   {
      double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(useSpreadATR)
      {
         double maxSpread = atrValue * spreadATRPercent / 100.0;
         if(spread > maxSpread)
         {
            PrintDebug("🚫 Spread > "+ DoubleToString(maxSpread, _Digits)+ " ("+ DoubleToString(spreadATRPercent)+ "% de l'ATR : "+ DoubleToString(atrValue, _Digits)+ ")");
            return;
         }
      }
      
   }

   // Seuils dynamiques
   double seuilProximite  = atrValue * proximityATRPercent  / 100.0;
   double seuilEcartement = atrValue * ecartementATRPercent / 100.0;

   // Bougie précédente
   double open[], close[], high[], low[];
   if(CopyOpen(_Symbol, _Period, 0, 2, open) <= 0 ||
      CopyClose(_Symbol, _Period, 0, 2, close) <= 0 ||
      CopyHigh(_Symbol, _Period, 0, 2, high) <= 0 ||
      CopyLow(_Symbol, _Period, 0, 2, low) <= 0)
   {
      Print("❌ Erreur OHLC");
      return;
   }

   double bodySize = MathAbs(open[1] - close[1]);
   double candleSize = high[1] - low[1];

  if(useCandleFilter)
{
   double bodySize   = MathAbs(open[1] - close[1]);
   double minBodyATR = atrValue * candleBodyATRMin / 100.0;

   if(bodySize < minBodyATR)
   {
      PrintDebug("🕯️ Bougie rejetée (corps = "+ DoubleToString(bodySize, _Digits) +" < "+ DoubleToString(candleBodyATRMin)+ "% de l’ATR = "+ DoubleToString(minBodyATR, _Digits)+ ")");
      return;
   }
}
   // MA trend
   double ma38_now   = GetMAValue(wmaSlowPeriod, 0);
   double ma200_now  = GetMAValue(wmaTrendPeriod, 0);
   double ma200_prev = GetMAValue(wmaTrendPeriod, 1);

   // BUY
   if(RejetBrusqueBuy(seuilProximite, seuilEcartement))
   {
      if(!useTrendFilterBuy || (ma38_now > ma200_now && ma200_now > ma200_prev))
      {
         double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         tradeOpen(ORDER_TYPE_BUY, entry, atrValue);
         lastTradeTime = TimeCurrent();
      }
      else PrintDebug("🚫 BUY rejeté : MA non haussière");
   }

   // SELL
   if(RejetBrusqueSell(seuilProximite, seuilEcartement))
   {
      if(!useTrendFilterSell || (ma38_now < ma200_now && ma200_now < ma200_prev))
      {
         double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         tradeOpen(ORDER_TYPE_SELL, entry, atrValue);
         lastTradeTime = TimeCurrent();
      }
      else PrintDebug("🚫 SELL rejeté : MA non baissière");
   }
   
   
if(PositionSelect(_Symbol) && useTrailingSL)
{
   double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl     = PositionGetDouble(POSITION_SL);
   double tp     = PositionGetDouble(POSITION_TP);
   long type     = PositionGetInteger(POSITION_TYPE);
   double price  = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double move = MathAbs(price - entry);
   double trigger = atrValue * trailingTriggerATR;

   if(move >= trigger)
   {
      double newSL = (type == POSITION_TYPE_BUY)
                     ? entry + (atrValue * trailingOffsetATR)
                     : entry - (atrValue * trailingOffsetATR);

      newSL = NormalizeDouble(newSL, _Digits);

      if(PositionGetDouble(POSITION_SL) != newSL)
      {
         trade.PositionModify(_Symbol, newSL, tp);
         Print("🔁 SL déplacé en break-even + offset ATR : ", newSL);
      }
   }
}

if(PositionSelect(_Symbol) && usePartialTP)
{
   double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl     = PositionGetDouble(POSITION_SL);
   double volume = PositionGetDouble(POSITION_VOLUME);
   long type     = PositionGetInteger(POSITION_TYPE);
   double price  = (type == POSITION_TYPE_BUY)
                   ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                   : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double rrDistance = MathAbs(entry - sl) * partialTP_RR;
   double target = (type == POSITION_TYPE_BUY)
                   ? entry + rrDistance
                   : entry - rrDistance;

   bool shouldClose = (type == POSITION_TYPE_BUY && price >= target) ||
                      (type == POSITION_TYPE_SELL && price <= target);

   if(shouldClose && volume > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      double volumeToClose = volume * partialTP_fraction;
      volumeToClose = MathMax(volumeToClose, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
      double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      volumeToClose = MathFloor(volumeToClose / volumeStep) * volumeStep;

      if(trade.PositionClosePartial(_Symbol, volumeToClose))
         Print("✅ TP partiel exécuté (", partialTP_fraction * 100, "%) à RR=", partialTP_RR);
      else
         Print("❌ Erreur TP partiel : ", trade.ResultRetcode(), " / ", trade.ResultRetcodeDescription());
   }
}

}

void TesterDeinit()
{
   PrintDebug("📊 Résumé des seuils observés pendant le backtest :");
   PrintDebug("➡️ Proximité : Min = "+ DoubleToString(proxMin+ 6)+ " / Max = "+ DoubleToString(proxMax+ 6));
   PrintDebug("➡️ Écartement : Min = "+ DoubleToString(ecartMin+ 6)+ " / Max = "+ DoubleToString(ecartMax+ 6));
}