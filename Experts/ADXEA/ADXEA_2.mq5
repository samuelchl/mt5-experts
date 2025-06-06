//+------------------------------------------------------------------+
//|                                             Strategie_ADX.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "1.00"
#property strict

#include <SamBotUtils.mqh>

//+------------------------------------------------------------------+
//| Expert configuration                                            |
//+------------------------------------------------------------------+
// Paramètres généraux
input ENUM_TIMEFRAMES TF                    = PERIOD_CURRENT;

input int    MAGIC_NUMBER                   = 415975344;

// Paramètres Stop Loss / Take Profit (en %)
input double stop_loss_pct                  = 1.0;
input double take_profit_pct                = 2.0;
input bool   sortie_dynamique               = false;

// Paramètres gestion de lot
input bool   GestionDynamiqueLot            = false;
input double RisqueParTradePct              = 1.0;
input double LotFixe                        = 0.1;

// Paramètres ADX
input int    ADX_Period                     = 14;
input double Seuil_ADX                      = 25.0;

// Paramètres Trailing Stop
input bool   utiliser_trailing_stop         = false;
input double trailing_stop_pct              = 0.5;

// Paramètres Prises de profit partielles
input bool   utiliser_prise_profit_partielle= false;
input double tranche_prise_profit_pct       = 0.02;
input int    nb_tp_partiel                  = 2;

// Paramètres spread
input bool   UseMaxSpread                   = false;
input int    MaxSpreadPoints                = 40;
input bool SL_BreakEVEN_after_first_partialTp = false;

input bool closeIfVolumeLow =false;
input double percentToCloseTrade =0.20;
input bool showAlive = false;

input bool tradeVendredi = false;

input int heuresToCloseTradeIfReverseSignal = 2;

input ENUM_TIMEFRAMES TF_ONTICK             = PERIOD_CURRENT;
input bool Use_TF_ONTICK = false; // si false on utilise TF

input ENUM_TIMEFRAMES TF_TRADE_MGMT = PERIOD_CURRENT;
input bool Use_TF_TRADE_MGMT = false; // si false on utilise TF

input double Seuil_ADX_exit_dyna = 0;

//--- Handles pour l’ADX
int handle_ADX;
double ADXBuf[], plusDIBuf[], minusDIBuf[];
static datetime lastSignalBar = 0;
static datetime lastMgmtBar   = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Création du handle ADX
   handle_ADX = iADX(_Symbol, TF, ADX_Period);
   if(handle_ADX == INVALID_HANDLE)
   {
      Print("Erreur à la création du handle ADX");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Vérifie si on peut ouvrir une position (blocage le vendredi)     |
//+------------------------------------------------------------------+
bool CanOpenTrade()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   // day_of_week: 0=Sunday, 1=Monday,...,5=Friday
   if(now.day_of_week == 5 && !tradeVendredi)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Tick principal: on découple les entrées et la gestion            |
//+------------------------------------------------------------------+
void OnTick()
{
   HandleEntry();
   HandleManagement();
}

//+------------------------------------------------------------------+
//| Gère l’ouverture de position                                     |
//+------------------------------------------------------------------+
void HandleEntry()
{
   // 1) throttle par TF d’entrée
   ENUM_TIMEFRAMES tfSignal = (Use_TF_ONTICK ? TF_ONTICK : TF);
   datetime timeSignal = iTime(_Symbol, tfSignal, 0);
   if(timeSignal == lastSignalBar) 
      return;
   lastSignalBar = timeSignal;
   
   int spread_points = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
      if(showAlive)
   Print(IntegerToString(MAGIC_NUMBER) + " alive" + " spread "  + IntegerToString(spread_points));

   // 2) pas d’entrée si déjà position
   if(SamBotUtils::IsTradeOpen(_Symbol, (ulong)MAGIC_NUMBER)) 
      return;

   // 3) pas d’entrée si vendredi bloqué
   if(!CanOpenTrade())
      return;

   // 4) lecture ADX/DI sur TF principal
   if(CopyBuffer(handle_ADX, 0, 0, 1, ADXBuf)    < 1) return;
   if(CopyBuffer(handle_ADX, 1, 0, 1, plusDIBuf)< 1) return;
   if(CopyBuffer(handle_ADX, 2, 0, 1, minusDIBuf)< 1) return;
   double adx = ADXBuf[0], pDI = plusDIBuf[0], mDI = minusDIBuf[0];
   bool tendanceForte = (adx > Seuil_ADX);
   bool buyCondition  = tendanceForte && (pDI > mDI);
   bool sellCondition = tendanceForte && (mDI > pDI);


   // 5) conditions d’ouverture
   if(buyCondition)
      SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                             ORDER_TYPE_BUY,
                             stop_loss_pct,
                             take_profit_pct,
                             GestionDynamiqueLot,
                             LotFixe,
                             RisqueParTradePct,
                             UseMaxSpread,
                             MaxSpreadPoints);

   if(sellCondition)
      SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                             ORDER_TYPE_SELL,
                             stop_loss_pct,
                             take_profit_pct,
                             GestionDynamiqueLot,
                             LotFixe,
                             RisqueParTradePct,
                             UseMaxSpread,
                             MaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Gère les sorties : dynamic exit, trailing, TP partiels           |
//+------------------------------------------------------------------+
void HandleManagement()
{
   // 1) throttle par TF de gestion
   ENUM_TIMEFRAMES tfMgmt = (Use_TF_TRADE_MGMT ? TF_TRADE_MGMT : TF);
   datetime timeMgmt = iTime(_Symbol, tfMgmt, 0);
   if(timeMgmt == lastMgmtBar) 
      return;
   lastMgmtBar = timeMgmt;
   
   int spread_points = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
      if(showAlive)
   Print(IntegerToString(MAGIC_NUMBER) + " alive" + " spread "  + IntegerToString(spread_points));

   // 2) rien si pas de position
   if(!SamBotUtils::IsTradeOpen(_Symbol, (ulong)MAGIC_NUMBER))
      return;

   // 3) lecture ADX/DI
   if(CopyBuffer(handle_ADX, 0, 0, 1, ADXBuf)    < 1) return;
   if(CopyBuffer(handle_ADX, 1, 0, 1, plusDIBuf)< 1) return;
   if(CopyBuffer(handle_ADX, 2, 0, 1, minusDIBuf)< 1) return;
   double adx = ADXBuf[0], pDI = plusDIBuf[0], mDI = minusDIBuf[0];
   bool force = (adx > Seuil_ADX_exit_dyna);
   bool exitSell  = force && (pDI > mDI);
   bool exitBuy = force && (mDI > pDI);

   // 4) sortie dynamique seulement si en perte
   if(sortie_dynamique)
   {
      double profit = PositionGetDouble(POSITION_PROFIT);
      if(profit < 0.0)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         ulong type = PositionGetInteger(POSITION_TYPE);
         
         datetime now = TimeCurrent();
         datetime t_open = (datetime)PositionGetInteger(POSITION_TIME);
         double   heures = (now - t_open) / 3600.0;

         // inversion BUY→SELL
         if(type==POSITION_TYPE_BUY && exitBuy && heuresToCloseTradeIfReverseSignal >= heures )
         {
            SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
            if(CanOpenTrade())
               SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                     ORDER_TYPE_SELL,
                                     stop_loss_pct,
                                     take_profit_pct,
                                     GestionDynamiqueLot,
                                     LotFixe,
                                     RisqueParTradePct,
                                     UseMaxSpread,
                                     MaxSpreadPoints);
         }
         // inversion SELL→BUY
         else if(type==POSITION_TYPE_SELL && exitSell && heuresToCloseTradeIfReverseSignal >= heures)
         {
            SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
            if(CanOpenTrade())
               SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                     ORDER_TYPE_BUY,
                                     stop_loss_pct,
                                     take_profit_pct,
                                     GestionDynamiqueLot,
                                     LotFixe,
                                     RisqueParTradePct,
                                     UseMaxSpread,
                                     MaxSpreadPoints);
         }
      }
   }

   // 5) trailing stop
   SamBotUtils::GererTrailingStop(_Symbol, (ulong)MAGIC_NUMBER,
                                  utiliser_trailing_stop,
                                  trailing_stop_pct);

   // 6) prises profit partielles
   SamBotUtils::GererPrisesProfitsPartielles(_Symbol, (ulong)MAGIC_NUMBER,
                                             utiliser_prise_profit_partielle,
                                             tranche_prise_profit_pct,
                                             nb_tp_partiel,
                                             SL_BreakEVEN_after_first_partialTp,
                                             closeIfVolumeLow,
                                             percentToCloseTrade);
}


//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_ADX != INVALID_HANDLE) 
      IndicatorRelease(handle_ADX);
}
