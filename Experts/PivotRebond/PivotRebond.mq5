//+------------------------------------------------------------------+
//|                                         PivotStrategy_SamBot.mq5 |
//|                      Adaptation de votre archi + logique Pivot  |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "1.00"
#property strict

#include <SamBotUtils.mqh>

//+------------------------------------------------------------------+
//| Expert configuration                                             |
//+------------------------------------------------------------------+
input double           seuil_proximite                 = 5.0;     // distance max en pips du niveau S1/R1
input double           take_profit_pct                 = 1.0;     // TP en % du prix d'entrée
input double           stop_loss_pct                   = 1.0;     // SL en % du prix d'entrée
input bool             sortie_dynamique                = true;    // fermer au renversement
input ENUM_TIMEFRAMES  TF                              = PERIOD_CURRENT;

input bool             GestionDynamiqueLot             = false;
input double           RisqueParTradePct               = 1.0;
input double           LotFixe                         = 0.2;

input bool             utiliser_trailing_stop          = false;
input double           trailing_stop_pct               = 0.2;

input bool             utiliser_prise_profit_partielle = false;
input double           tranche_prise_profit_pct        = 0.02;
input int              nb_tp_partiel                   = 50;

input int              MAGIC_NUMBER                    = 517985;

input bool             UseMaxSpread                    = true;
input int              MaxSpreadPoints                 = 40;

//--- Variables de pivot
double pivotPP, pivotS1, pivotR1;
int    lastPivotDay = -1;

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
  // Aucun handle à créer ici
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  // Rien à libérer
}

//+------------------------------------------------------------------+
//| Expert tick                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
  // 1) Recalcul des pivots D1 une fois par jour
  MqlDateTime tm;
  TimeToStruct(TimeCurrent(), tm);
  if (tm.day != lastPivotDay)
  {
    CalculatePivots();
    lastPivotDay = tm.day;
  }

  // 2) Ne traiter que sur chaque nouvelle bougie TF
  static datetime lastTime = 0;
  datetime       curTime  = iTime(_Symbol, TF, 0);
  if (curTime == lastTime)
    return;
  lastTime = curTime;

  // 3) Calcul de la proximité au pivot
  double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  double pip       = (_Digits >= 5 ? point * 10 : point);
  double threshold = seuil_proximite * pip;
  double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);

  bool nearS1      = (MathAbs(bid - pivotS1) <= threshold);
  bool nearR1      = (MathAbs(bid - pivotR1) <= threshold);

  // 4) Gestion des positions via SamBotUtils
  bool hasPos = SamBotUtils::IsTradeOpen(_Symbol, (ulong)MAGIC_NUMBER);

  if (hasPos)
  {
    // Sortie dynamique si inversion simple (reste inchangée)
    if (sortie_dynamique)
    {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      if (PositionSelectByTicket(ticket))
      {
        ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        if (ptype == POSITION_TYPE_BUY && nearR1)
          SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
        else if (ptype == POSITION_TYPE_SELL && nearS1)
          SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
      }
    }
  }
  else
  {
    // --- CONFIRMATION DE REBOND / BREAKOUT+PULLBACK ---

    // 4a) Détection d'un hammer bas (bougie fermée shift=1)
    double op1 = iOpen (_Symbol, TF, 1);
    double cl1 = iClose(_Symbol, TF, 1);
    double lo1 = iLow  (_Symbol, TF, 1);
    bool bullishReversal = (cl1 > op1) && ((op1 - lo1) >= 2 * (cl1 - op1)) && nearS1;

    // 4b) Détection d'un shooting star / hammer haut (shift=1)
    double hi1 = iHigh (_Symbol, TF, 1);
    bool bearishReversal = (op1 > cl1) && ((hi1 - op1) >= 2 * (op1 - cl1)) && nearR1;

    // 4c) Breakout sous S1 + pullback dessus
    bool breakoutPullbackBuy = (cl1 < pivotS1) && (iHigh(_Symbol, TF, 0) >= pivotS1);

    // 4d) Breakout au-dessus R1 + pullback dessous
    bool breakoutPullbackSell = (cl1 > pivotR1) && (iLow(_Symbol, TF, 0) <= pivotR1);

    // 5) Entrées
    if (bullishReversal || breakoutPullbackBuy)
    {
      SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                             ORDER_TYPE_BUY,
                             stop_loss_pct,
                             take_profit_pct,
                             GestionDynamiqueLot,
                             LotFixe,
                             RisqueParTradePct,
                             UseMaxSpread,
                             MaxSpreadPoints);
      return;
    }
    if (bearishReversal || breakoutPullbackSell)
    {
      SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                             ORDER_TYPE_SELL,
                             stop_loss_pct,
                             take_profit_pct,
                             GestionDynamiqueLot,
                             LotFixe,
                             RisqueParTradePct,
                             UseMaxSpread,
                             MaxSpreadPoints);
      return;
    }
  }

  // 6) Trailing Stop et TP partiels
  SamBotUtils::GererTrailingStop(_Symbol, (ulong)MAGIC_NUMBER,
                                 utiliser_trailing_stop,
                                 trailing_stop_pct);

  SamBotUtils::GererPrisesProfitsPartielles4Corrige(_Symbol, (ulong)MAGIC_NUMBER,
                                           utiliser_prise_profit_partielle,
                                           tranche_prise_profit_pct,
                                           nb_tp_partiel);
}


//+------------------------------------------------------------------+
//| Calcule PP, S1 et R1 sur la bougie D1 précédente                 |
//+------------------------------------------------------------------+
void CalculatePivots()
{
  double hi    = iHigh(_Symbol, PERIOD_D1, 1);
  double lo    = iLow (_Symbol, PERIOD_D1, 1);
  double cls   = iClose(_Symbol, PERIOD_D1, 1);

  pivotPP = (hi + lo + cls) / 3.0;
  pivotS1 = 2 * pivotPP - hi;
  pivotR1 = 2 * pivotPP - lo;
}
