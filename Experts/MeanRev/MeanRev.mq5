//+------------------------------------------------------------------+
//|                                               MeanRev.mq5        |
//|   Mean‑Reversion EA basé sur un Z‑Score                          |
//+------------------------------------------------------------------+
#property copyright "…"
#property link      "…"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>        // Pour CTrade
CTrade       trade;                // Objet pour envoyer les ordres

//--- Handles d’indicateurs
int          handleMA;
int          handleStd;

//--- Paramètres externes
input int    InpWindow    = 61;      // Fenêtre pour MA & StdDev
input double InpK         = 6.5;     // Multiplicateur d’écart‑type
input double InpLots      = 0.1;     // Taille de la position (lots)
input int    InpSlippage  = 5;       // Slippage maximal en points
input double InpEpsilon   = 1e-8;    // Pour stabiliser la division

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
  // Création des indicateurs MA et StdDev
  handleMA  = iMA   (_Symbol, PERIOD_M1, InpWindow, 0, MODE_SMA, PRICE_CLOSE);
  handleStd = iStdDev(_Symbol, PERIOD_M1, InpWindow, 0, MODE_SMA, PRICE_CLOSE);
  
  if(handleMA  == INVALID_HANDLE ||
     handleStd == INVALID_HANDLE)
    return INIT_FAILED;
  
  return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  // Libération des handles
  if(handleMA  != INVALID_HANDLE)  IndicatorRelease(handleMA);
  if(handleStd != INVALID_HANDLE)  IndicatorRelease(handleStd);
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
  // 1) Lire le dernier close, la MA et l’écart‑type
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double ma_buf[1], std_buf[1];
  if(CopyBuffer(handleMA,  0, 0, 1, ma_buf)  != 1) return;
  if(CopyBuffer(handleStd, 0, 0, 1, std_buf) != 1) return;
  
  double m   = ma_buf[0];
  double s   = std_buf[0];
  double z   = (bid - m) / (s * InpK + InpEpsilon);
  
  // 2) Vérifier position ouverte sur ce symbole
  bool hasPos    = PositionSelect(_Symbol);
  bool hasLong   = hasPos && ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
  bool hasShort  = hasPos && ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL);
  
  // 3) Logic d’entrée/sortie
  // -- Long entry
  if(z < -1.0 && !hasLong)
  {
    if(hasShort)                         // si short existant, le fermer
      trade.PositionClose(PositionGetInteger(POSITION_TICKET), InpSlippage);
    trade.Buy(InpLots, _Symbol, bid, InpSlippage);
  }
  // -- Long exit
  else if(z > 0.0 && hasLong)
  {
    trade.PositionClose(PositionGetInteger(POSITION_TICKET), InpSlippage);
  }
  
  // -- Short entry
  if(z > 1.0 && !hasShort)
  {
    if(hasLong)
      trade.PositionClose(PositionGetInteger(POSITION_TICKET), InpSlippage);
    trade.Sell(InpLots, _Symbol, bid, InpSlippage);
  }
  // -- Short exit
  else if(z < 0.0 && hasShort)
  {
    trade.PositionClose(PositionGetInteger(POSITION_TICKET), InpSlippage);
  }
}

double OnTester()
{
  // ici, trade.GetStatistic(STAT_SHARPE) est juste un exemple
  // vous pouvez retourner le profit factor, le recovery factor, etc.
  return(trade.GetStatistic(STAT_SHARPE_RATIO));
}