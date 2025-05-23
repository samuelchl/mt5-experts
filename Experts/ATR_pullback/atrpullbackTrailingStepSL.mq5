//+------------------------------------------------------------------+
//| Expert Advisor : ATR Pullback Strategy                           |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>


enum TradeMode
{
   OnlyBuy = 0,
   OnlySell = 1,
   Both = 2
};

input TradeMode trade_mode = Both; // Mode de trading sélectionné

input double MinATR = 0.0005; // Seuil minimal de l'ATR pour filtrer les périodes de faible volatilité

input double coeffsl = 1.5;           
input double LotSize = 0.1;           // Taille du lot
input double RiskRewardRatio = 2.0;   // Ratio Risque/Rendement
input int ATR_Period = 14;            // Période de l'ATR
input int MA_Period = 50;             // Période de la Moyenne Mobile
input ENUM_MA_METHOD MA_Method = MODE_SMA; // Méthode de la Moyenne Mobile
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; // Période de temps
input int cooldownMinutes     = 180;        // ⏳ Délai min entre 2 trades
input bool useCooldown         = true;

input bool useTrailingSL          = true;     // Active le SL dynamique
input double trailingTriggerATR   = 1.0;       // Seuil de déclenchement en ATR (ex: 1.0 = +1 ATR)
input double trailingOffsetATR    = 0.2;       // Offset du SL en gain (ex: +0.2 ATR)


input int StartHour1   = 17;
input int StartMinute1 = 0;
input int EndHour1     = 23;
input int EndMinute1   = 30;

input int StartHour2   = 1;
input int StartMinute2 = 30;
input int EndHour2     = 3;
input int EndMinute2   = 0;

input bool useTradinghours = false;

input double trailingStepATR = 0.2; // Taille du step à chaque progression du trailing



CTrade trade;

int atr_handle;
int ma_handle;
datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
//| Fonction d'initialisation de l'EA                                |
//+------------------------------------------------------------------+
int OnInit()
{
    // Création des handles pour les indicateurs
    atr_handle = iATR(_Symbol, Timeframe, ATR_Period);
    if (atr_handle == INVALID_HANDLE)
    {
        Print("Erreur lors de la création du handle ATR : ", GetLastError());
        return(INIT_FAILED);
    }

    ma_handle = iMA(_Symbol, Timeframe, MA_Period, 0, MA_Method, PRICE_CLOSE);
    if (ma_handle == INVALID_HANDLE)
    {
        Print("Erreur lors de la création du handle MA : ", GetLastError());
        return(INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

static bool hadPosition = false;

//+------------------------------------------------------------------+
//| Fonction appelée à chaque tick                                   |
//+------------------------------------------------------------------+
void OnTick()
{

      bool hasPosition = PositionSelect(_Symbol);
   if(hadPosition && !hasPosition)
   {
      //lastTradeTime = TimeCurrent();  // Cooldown déclenché à la clôture
      //Print("🔒 Position clôturée, cooldown lancé à ", TimeToString(lastTradeTime, TIME_MINUTES));
   }
   hadPosition = hasPosition;

    //Print("OnTick");
    // Vérifier s'il y a déjà une position ouverte
   

    // Récupérer les valeurs actuelles de l'ATR et de la MA
    double atr_value[], ma_value[];
    if (CopyBuffer(atr_handle, 0, 0, 1, atr_value) <= 0 ||
        CopyBuffer(ma_handle, 0, 0, 1, ma_value) <= 0)
    {
        Print("Erreur lors de la copie des données des indicateurs : ", GetLastError());
        return;
    }

    double current_atr = atr_value[0];
    double current_ma = ma_value[0];
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
 if(PositionSelect(_Symbol) && useTrailingSL)
{
   double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl     = PositionGetDouble(POSITION_SL);
   double tp     = PositionGetDouble(POSITION_TP);
   long type     = PositionGetInteger(POSITION_TYPE);
   double price  = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double move = (type == POSITION_TYPE_BUY) ? price - entry : entry - price;
   double stepSize = current_atr * trailingStepATR;

   // Calcul du nouveau SL possible
   int steps = int(move / stepSize);
   if(steps > 0)
   {
      double newSL = (type == POSITION_TYPE_BUY)
                     ? entry + (steps * stepSize)
                     : entry - (steps * stepSize);

      newSL = NormalizeDouble(newSL, _Digits);

      // Ne bouger le SL que s’il est mieux (plus proche du TP)
      bool shouldUpdate = (type == POSITION_TYPE_BUY && newSL > sl && newSL < price) ||
                          (type == POSITION_TYPE_SELL && newSL < sl && newSL > price);

      if(shouldUpdate)
      {
         trade.PositionModify(_Symbol, newSL, tp);
         Print("🔁 SL trail step mis à jour : ", newSL);
      }
   }
}



  if (!IsTradingTime() && useTradinghours)
    {
        Print("Hors des horaires de trading autorisés.");
        return;
    }

        // --- Cooldown
   if(useCooldown && TimeCurrent() - lastTradeTime < cooldownMinutes * 60)
   {
      Print("⏱️ Cooldown actif (", cooldownMinutes, "min)");
      return;
   }

    // Filtrer les périodes de faible volatilité
    if (current_atr < MinATR)
    {
        Print("Volatilité trop faible (ATR = ", current_atr, "), aucune position ouverte.");
        return;
    }

     if (PositionsTotal() > 0)
        return;

    // Conditions d'achat
    if ((trade_mode == OnlyBuy || trade_mode == Both) &&
        current_price > current_ma &&
        current_price < current_ma + current_atr)
    {
        double sl = current_price - current_atr * coeffsl;
        double tp = current_price + current_atr * RiskRewardRatio;
        trade.Buy(LotSize, _Symbol, current_price, sl, tp, "Achat ATR Pullback");
        lastTradeTime = TimeCurrent();
    }

    // Conditions de vente
    else if ((trade_mode == OnlySell || trade_mode == Both) &&
             current_price < current_ma &&
             current_price > current_ma - current_atr)
    {
        double sl = current_price + current_atr * coeffsl;
        double tp = current_price - current_atr * RiskRewardRatio;
        trade.Sell(LotSize, _Symbol, current_price, sl, tp, "Vente ATR Pullback");
        lastTradeTime = TimeCurrent();
    }
    
   
}

bool IsTradingTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeLocal(), dt);  // Convertit le temps actuel en structure

    int time_in_minutes = dt.hour * 60 + dt.min;

    int start1 = StartHour1 * 60 + StartMinute1;
    int end1   = EndHour1   * 60 + EndMinute1;
    int start2 = StartHour2 * 60 + StartMinute2;
    int end2   = EndHour2   * 60 + EndMinute2;

    if ((time_in_minutes >= start1 && time_in_minutes <= end1) ||
        (time_in_minutes >= start2 && time_in_minutes <= end2))
    {
        return true;
    }

    return false;
}


