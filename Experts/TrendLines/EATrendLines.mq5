//+------------------------------------------------------------------+
//|                         TLB_CTrade_EA.mq5                        |
//|      EA autonome utilisant TrendLinesWithBreaks + CTrade         |
//+------------------------------------------------------------------+
#property copyright "VotreNom"
#property link      "https://votresite.exemple"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade         trade;

//--- Paramètres externes
// On ne met QUE le nom de l’indicateur, sans dossier :
input string   InpIndicatorName   = "TrendLinesWithBreaks-Indicator"; 
input int      InpLength          = 14;       // length de l’indicateur
input double   InpSlope           = 1.0;      // k
enum ENUM_Method { Atr, Stdev, Linreg };
input ENUM_Method InpMethod       = Atr;      // méthode de pente

input double   InpLotSize         = 0.10;     // taille de lot fixe
input double   InpRewardRiskRatio = 2.0;      // ratio R/R pour calculer TP
input int      InpMagicNumber     = 894757;   // magic number pour filtrer les positions
input bool   InpShowOnlyConfirmed = true;  // corresponds à show=true de l’indicateur


//--- Handle de l’indicateur
int            indHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int _Shift;
int OnInit()
{
  indHandle = iCustom(_Symbol,_Period,
                      InpIndicatorName,
                      InpLength, InpSlope, InpMethod, InpShowOnlyConfirmed);
  if(indHandle==INVALID_HANDLE) return INIT_FAILED;

  // Si on attend une confirmation (show=true), la flèche tombe length barres plus tard
  _Shift = InpShowOnlyConfirmed ? (InpLength + 1) : 1;
  return INIT_SUCCEEDED;
}


//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(indHandle!=INVALID_HANDLE)
      IndicatorRelease(indHandle);
}

//+------------------------------------------------------------------+
//| Lit un buffer de l’indicateur                                  |
//+------------------------------------------------------------------+
double GetBuffer(int buf, int shift)
{
  double v[];
  if(CopyBuffer(indHandle, buf, shift, 1, v) != 1)
     return EMPTY_VALUE;
  return v[0];
}

//+------------------------------------------------------------------+
//| Détection du signal de cassure                                 |
//+------------------------------------------------------------------+


int TrendLineSignal(double &outSL)
{
  // Buffer 0 = breakout buy
  double buy = GetBuffer(0, _Shift);
  if(buy > 0)
  {
    outSL = GetBuffer(2, _Shift);  // Buffer 2 = SL buy
    return +1;
  }
  // Buffer 1 = breakout sell
  double sell = GetBuffer(1, _Shift);
  if(sell > 0)
  {
    outSL = GetBuffer(3, _Shift);  // Buffer 3 = SL sell
    return -1;
  }
  return 0;
}


//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBar=0;
   datetime curBar = iTime(_Symbol,_Period,0);
   if(curBar==lastBar) return;  // on attend la nouvelle bougie
   lastBar = curBar;

   double slPrice=0;
   int sig = TrendLineSignal(slPrice);
   if(sig==0) return;

   // Vérifier qu’aucune position similaire n’est déjà ouverte
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(PositionGetTicket(i)>0
         && PositionGetInteger(POSITION_MAGIC)==InpMagicNumber
         && PositionGetString(POSITION_SYMBOL)==_Symbol
         && ((sig>0 && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
          || (sig<0 && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)))
         return;
   }

   // Préparation des paramètres
   double price = sig>0
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double volume = InpLotSize;
   double tp = sig>0
               ? price + (price - slPrice) * InpRewardRiskRatio
               : price - (slPrice - price) * InpRewardRiskRatio;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(5);

   bool ok = (sig>0)
             ? trade.Buy(volume, _Symbol, price, slPrice, tp, "TLB Buy")
             : trade.Sell(volume, _Symbol, price, slPrice, tp, "TLB Sell");

   if(ok)
      PrintFormat("Trade %s OK @%.5f SL=%.5f TP=%.5f",
                  (sig>0?"BUY":"SELL"), price, slPrice, tp);
   else
      PrintFormat("Erreur %s : %d", (sig>0?"BUY":"SELL"), GetLastError());
}
