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
input int    InpWindow    = 61;      // Fenêtre pour MA 
input double InpStdDevRatio   = 1; //Ratio fenetre stddev
input double InpK         = 6.5;     // Multiplicateur d’écart‑type
input double InpLots      = 0.1;     // Taille de la position (lots)
input int    InpSlippage  = 5;       // Slippage maximal en points
input double InpEpsilon   = 1e-8;    // Pour stabiliser la division

input int secondsWaiting =15;
input double InpMaxSpread = 2.0; // Spread max autorisé (en pips)
input bool showAlive = false;
input int    MAGIC_NUMBER                   = 444444;

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   int stdDevPeriod = (int)MathMax(1, InpWindow * InpStdDevRatio); // Sécurité : min 1
  // Création des indicateurs MA et StdDev
  handleMA  = iMA   (_Symbol, PERIOD_CURRENT, InpWindow, 0, MODE_SMA, PRICE_MEDIAN);
  handleStd = iStdDev(_Symbol, PERIOD_CURRENT, stdDevPeriod, 0, MODE_SMA, PRICE_MEDIAN);
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

static datetime lastTime = 0;
   datetime now = TimeCurrent();

   if(now - lastTime < secondsWaiting)
      return;  // ⛔ Moins de 15 sec écoulées → on quitte

   lastTime = now;
   
   if(showAlive)
      Print(IntegerToString(MAGIC_NUMBER) + " alive");

     // 1) Lire le dernier close, la MA et l’écart‑type
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price = (bid + ask) / 2.0;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spreadPips = (ask - bid) / point;
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;


   bool canEnter = true;
   if(spreadPips > InpMaxSpread)
   {
      canEnter= false;
   }

   if(showAlive){
   
      Print("spreadPips" + DoubleToString(spreadPips));
      Print("InpMaxSpread" + DoubleToString(InpMaxSpread));
      Print("spread" + DoubleToString(spread));
   }
  double ma_buf[1], std_buf[1];
  if(CopyBuffer(handleMA,  0, 0, 1, ma_buf)  != 1) return;
  if(CopyBuffer(handleStd, 0, 0, 1, std_buf) != 1) return;
  
  double m   = ma_buf[0];
  double s   = std_buf[0];
  double z   = (price - m) / (s * InpK + InpEpsilon);
  
  // 2) Vérifier position ouverte sur ce symbole
  bool hasPos    = PositionSelect(_Symbol);
  bool hasLong   = hasPos && ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
  bool hasShort  = hasPos && ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL);
  
  // 3) Logic d’entrée/sortie
  // -- Long entry
  if(z < -1.0 && !hasLong)
  {
    if(hasShort)                         // si short existant, le fermer
      trade.PositionClose(PositionGetInteger(POSITION_TICKET));
      
      if(canEnter)
         trade.Buy(InpLots, _Symbol, ask /* , sl_price, tp_price */);
  }
  // -- Long exit
  else if(z > 0.0 && hasLong)
  {
    trade.PositionClose(PositionGetInteger(POSITION_TICKET));
  }
  
  // -- Short entry
  if(z > 1.0 && !hasShort)
  {
    if(hasLong)
      trade.PositionClose(PositionGetInteger(POSITION_TICKET));
    if(canEnter)
      trade.Sell(InpLots, _Symbol, bid /* , sl_price, tp_price */);
  }
  // -- Short exit
  else if(z < 0.0 && hasShort)
  {
    trade.PositionClose(PositionGetInteger(POSITION_TICKET));
  }
}

