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

int handleFast;
input int fastPeriod = 8;


//--- Paramètres externes
input int    InpWindow    = 61;      // Fenêtre pour MA & StdDev
input double InpK         = 6.5;     // Multiplicateur d’écart‑type
input double InpLots      = 0.1;     // Taille de la position (lots)
input int    InpSlippage  = 5;       // Slippage maximal en points
input double InpEpsilon   = 1e-8;    // Pour stabiliser la division

input int startTradingHour = 2;
input int EndTradingHour = 22;

input double seuil = 0.2;

input double take_profit_pct = 2;          // Take profit (%)
input double stop_loss_pct = 0.5; 
input int MAGIC_NUMBER = 14638795;


datetime time_initialized;


//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   
  time_initialized = TimeCurrent();
  
  
   
   
  // Création des indicateurs MA et StdDev
  handleMA  = iMA   (_Symbol, PERIOD_M1, InpWindow, 0, MODE_SMA, PRICE_CLOSE);
  handleStd = iStdDev(_Symbol, PERIOD_M1, InpWindow, 0, MODE_SMA, PRICE_CLOSE);
  handleFast = iMA(_Symbol, PERIOD_M1, fastPeriod, 0, MODE_EMA, PRICE_OPEN);
  
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
    if(handleFast != INVALID_HANDLE)  IndicatorRelease(handleFast);
}


bool IsInTradingHours (datetime now){
// Obtenir la date/heure actuelle du serveur (en UTC)

MqlDateTime dt;
TimeToStruct(now, dt);

// Vérifier les jours de trading (lundi à vendredi)
if(dt.day_of_week == 0 || dt.day_of_week == 6) // dimanche (0) ou samedi (6)
    return false;

// Vérifier les heures autorisées : entre 00:00 et 20:00 UTC
if(dt.hour < startTradingHour || dt.hour >= EndTradingHour)
    return false;
    
    return true;

}



//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{

   datetime now = TimeCurrent();


  // 1) Lire le dernier close, la MA et l’écart‑type
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double ma_buf[1], std_buf[1];
  if(CopyBuffer(handleMA,  0, 0, 1, ma_buf)  != 1) return;
  if(CopyBuffer(handleStd, 0, 0, 1, std_buf) != 1) return;
  
     double maFastBuf[1];
   if(CopyBuffer(handleFast, 0, 0, 1, maFastBuf) != 1) return;
   double maFast = maFastBuf[0];
     
  double m   = ma_buf[0];
  double s   = std_buf[0];
  double z = (maFast - m) / (s * InpK + InpEpsilon);
    double z1 = (bid - m) / (s * InpK + InpEpsilon);
    
    //Print("----");
    //Print("z" + DoubleToString(z));
    //Print("z1" + DoubleToString(z1));
    //Print("----");
  
  
  // 2) Vérifier position ouverte sur ce symbole
  bool hasPos    = PositionSelect(_Symbol);
  bool hasLong   = hasPos && ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
  bool hasShort  = hasPos && ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL);
  
  
   if (!IsInTradingHours(now)){
      
      if(PositionSelect(_Symbol))
    {
        ulong ticket = PositionGetInteger(POSITION_TICKET);
        trade.PositionClose(ticket);
    }
   return;
   }
         
         
            // Ne pas trader durant les X premières minutes après démarrage
int delay_minutes = 180;
if(now - time_initialized < delay_minutes * 60)
    return;
  
  // 3) Logic d’entrée/sortie
  // -- Long entry
  if(z < -seuil && !hasLong)
  {
    if(hasShort)                         // si short existant, le fermer
      trade.PositionClose(PositionGetInteger(POSITION_TICKET));
    tradeOpen(ORDER_TYPE_BUY);
  }
  // -- Long exit
  else if(z > 0.0 && hasLong)
  {
    trade.PositionClose(PositionGetInteger(POSITION_TICKET));
  }
  
  // -- Short entry
  if(z > seuil && !hasShort)
  {
    if(hasLong)
      trade.PositionClose(PositionGetInteger(POSITION_TICKET));
    tradeOpen(ORDER_TYPE_SELL);
  }
  // -- Short exit
  else if(z < 0.0 && hasShort)
  {
    trade.PositionClose(PositionGetInteger(POSITION_TICKET));
  }
}

//+------------------------------------------------------------------+
//| Fonctions pour ouverture/fermeture des ordres                    |
//+------------------------------------------------------------------+
void tradeOpen(ENUM_ORDER_TYPE type)
{

   //if(UseMaxSpread)
   //  {
   //   int spread_points = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   //   if(spread_points > MaxSpreadPoints)
   //     {
   //      PrintFormat("Spread trop élevé (%d pts > %d pts) → ordre annulé",
   //                  spread_points, MaxSpreadPoints);
   //      return;
   //     }
   //  }


   double price = SymbolInfoDouble(_Symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   double sl = price - (type==ORDER_TYPE_BUY?1:-1)*price*stop_loss_pct/100.0;
   double tp = price + (type==ORDER_TYPE_BUY?1:-1)*price*take_profit_pct/100.0;
   
   // ✅ Ne jamais avoir un TP SELL négatif
    if(type == ORDER_TYPE_SELL && tp < 0)
    tp = 1.0;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.magic = MAGIC_NUMBER;
   request.type     = type;
   double slPips = MathAbs(price - sl) / SymbolInfoDouble(_Symbol, SYMBOL_POINT) / 10.0;
   request.volume = InpLots;
   request.price    = price;
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= 10;

   if(!OrderSend(request,result))
      Print("Erreur ouverture ordre : ", result.comment);
}
