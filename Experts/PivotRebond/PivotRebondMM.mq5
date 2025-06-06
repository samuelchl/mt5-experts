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
  MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
  if (tm.day != lastPivotDay)
  {
    CalculatePivots();       // doit maintenant remplir pivotPP, pivotS1 et pivotR1
    lastPivotDay = tm.day;
  }

  // 2) Ne traiter qu'à la première tick de la bougie TF
  static datetime lastTime = 0;
  datetime curTime = iTime(_Symbol, TF, 0);
  if (curTime == lastTime) return;
  lastTime = curTime;

  // 3) Récupérer prix et seuil
  double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  double pip       = (_Digits >= 5 ? point*10 : point);
  double threshold = seuil_proximite * pip;
  double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);

  // 4) Calcul des niveaux M1–M4 à partir du D1 précédent
  double hiD1   = iHigh(_Symbol, PERIOD_D1, 1);
  double loD1   = iLow (_Symbol, PERIOD_D1, 1);
  double rangeD1= hiD1 - loD1;
  double pivotR2= pivotPP + rangeD1;
  double pivotS2= pivotPP - rangeD1;
  double pivotM1= (pivotS1 + pivotS2)/2.0;
  double pivotM2= (pivotS1 + pivotPP )/2.0;
  double pivotM3= (pivotPP  + pivotR1)/2.0;
  double pivotM4= (pivotR1 + pivotR2)/2.0;

  // 5) Tests de proximité
  bool nearS1  = (MathAbs(bid - pivotS1) <= threshold);
  bool nearM1  = (MathAbs(bid - pivotM1) <= threshold);
  bool nearM2  = (MathAbs(bid - pivotM2) <= threshold);
  bool nearPP  = (MathAbs(bid - pivotPP) <= threshold);
  bool nearM3  = (MathAbs(bid - pivotM3) <= threshold);
  bool nearM4  = (MathAbs(bid - pivotM4) <= threshold);
  bool nearR1  = (MathAbs(bid - pivotR1) <= threshold);

  bool nearSupport    = nearS1 || nearM1 || nearM2 || nearPP;
  bool nearResistance = nearR1 || nearM3 || nearM4 || nearPP;

  // 6) Détection des patterns de rebond sur la bougie fermée (shift=1)
  double op1 = iOpen (_Symbol, TF, 1);
  double cl1 = iClose(_Symbol, TF, 1);
  double lo1 = iLow  (_Symbol, TF, 1);
  double hi1 = iHigh (_Symbol, TF, 1);

  bool bullishReversal = (cl1 > op1) && ((op1 - lo1) >= 2*(cl1 - op1));
  bool bearishReversal = (op1 > cl1) && ((hi1 - op1) >= 2*(op1 - cl1));

  // 7) Cassure + pullback sur S1/R1 (comme avant)
  bool breakoutPullbackBuy  = (cl1 < pivotS1) && (iHigh(_Symbol,TF,0) >= pivotS1);
  bool breakoutPullbackSell = (cl1 > pivotR1) && (iLow (_Symbol,TF,0) <= pivotR1);

  // 8) Gestion des positions
  bool hasPos = SamBotUtils::IsTradeOpen(_Symbol, (ulong)MAGIC_NUMBER);

  if (hasPos)
  {
    // Sortie dynamique si on touche un niveau opposé (inclut M et PP)
    if (sortie_dynamique)
    {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      if (PositionSelectByTicket(ticket))
      {
        ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        if (ptype == POSITION_TYPE_BUY  && nearResistance)
           SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
        else if(ptype == POSITION_TYPE_SELL && nearSupport)
           SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
      }
    }
  }
  else
  {
    // 9) ENTRÉES → on attend REBOND confirmé OU BREAKOUT+PULLBACK
    // BUY si rebond près d'un support (S1, M1, M2, PP) ou breakout+pullback sous S1
    if ( (nearSupport    && bullishReversal) 
       || breakoutPullbackBuy )
    {
      SamBotUtils::tradeOpen(_Symbol,(ulong)MAGIC_NUMBER,
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
    // SELL si rebond près d'une résistance (R1, M3, M4, PP) ou breakout+pullback au-dessus R1
    if ( (nearResistance && bearishReversal) 
       || breakoutPullbackSell )
    {
      SamBotUtils::tradeOpen(_Symbol,(ulong)MAGIC_NUMBER,
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

  // 10) Trailing Stop et TP partiels  
  SamBotUtils::GererTrailingStop(_Symbol,(ulong)MAGIC_NUMBER,
                                 utiliser_trailing_stop,
                                 trailing_stop_pct);
  SamBotUtils::GererPrisesProfitsPartielles4Corrige(_Symbol,(ulong)MAGIC_NUMBER,
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
