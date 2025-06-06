//+------------------------------------------------------------------+
//|                                             Strategie_WMA.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "1.00"
#property strict

#include <SamBotUtils.mqh>

//+------------------------------------------------------------------+
//| Expert configuration                                            |
//+------------------------------------------------------------------+
input double seuil_proximite                = 0.1;
input double take_profit_pct                = 1;
input double stop_loss_pct                  = 1;
input bool   sortie_dynamique               = false;
input ENUM_TIMEFRAMES TF                    = PERIOD_CURRENT;

input bool   GestionDynamiqueLot            = false;
input double RisqueParTradePct              = 1.0;
input double LotFixe                        = 0.2;

input bool   utiliser_trailing_stop         = false;
input double trailing_stop_pct              = 0.2;

input bool   utiliser_prise_profit_partielle= true;
input double tranche_prise_profit_pct       = 0.02;
input int    nb_tp_partiel                  = 50;

input int    MAGIC_NUMBER                   = 123456789;

input bool UseMaxSpread = false;
input int MaxSpreadPoints = 40;

//--- Moving averages
int handle_WMA8, handle_WMA38, handle_WMA200;
double WMA8[], WMA38[], WMA200[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   handle_WMA8   = iMA(_Symbol, TF, 8,   0, MODE_LWMA, PRICE_CLOSE);
   handle_WMA38  = iMA(_Symbol, TF, 38,  0, MODE_LWMA, PRICE_CLOSE);
   handle_WMA200 = iMA(_Symbol, TF, 200, 0, MODE_LWMA, PRICE_CLOSE);
   if(handle_WMA8 == INVALID_HANDLE || handle_WMA38 == INVALID_HANDLE || handle_WMA200 == INVALID_HANDLE)
   {
      Print("Erreur lors de la création des handles MA");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, TF, 0);
   if(lastTime == currentTime) return;
   lastTime = currentTime;

   if(CopyBuffer(handle_WMA8,   0, 0, 2, WMA8)   < 2) return;
   if(CopyBuffer(handle_WMA38,  0, 0, 2, WMA38)  < 2) return;
   if(CopyBuffer(handle_WMA200, 0, 0, 1, WMA200) < 1) return;

   double wma8_0   = WMA8[0],  wma8_1  = WMA8[1];
   double wma38_0  = WMA38[0], wma38_1 = WMA38[1];
   double wma200_0 = WMA200[0];

   bool buyCondition  = SamBotUtils::isRejet3WMA(wma8_0, wma8_1, wma38_0, wma38_1, wma200_0, "up",   seuil_proximite);
   bool sellCondition = SamBotUtils::isRejet3WMA(wma8_0, wma8_1, wma38_0, wma38_1, wma200_0, "down", seuil_proximite);

   if(buyCondition)
   {
      double lowPrice = iLow(_Symbol, TF, 1);
      ObjectCreate(0, "buy"+TimeToString(TimeCurrent()), OBJ_ARROW_UP, 0, TimeCurrent(), lowPrice);
   }
   if(sellCondition)
   {
      double highPrice = iHigh(_Symbol, TF, 1);
      ObjectCreate(0, "sell"+TimeToString(TimeCurrent()), OBJ_ARROW_DOWN, 0, TimeCurrent(), highPrice);
   }

   bool hasPos = SamBotUtils::IsTradeOpen(_Symbol, (ulong)MAGIC_NUMBER);
   if(hasPos)
   {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      if(sortie_dynamique)
      {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && sellCondition)
            SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && buyCondition)
            SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
      }
   }
   else
   {
      if(buyCondition)
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_BUY,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,UseMaxSpread,MaxSpreadPoints);
      if(sellCondition)
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_SELL,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,UseMaxSpread,MaxSpreadPoints);
   }

   SamBotUtils::GererTrailingStop(_Symbol, (ulong)MAGIC_NUMBER,
                                  utiliser_trailing_stop,
                                  trailing_stop_pct);

   SamBotUtils::GererPrisesProfitsPartielles(_Symbol, (ulong)MAGIC_NUMBER,
                                             utiliser_prise_profit_partielle,
                                             tranche_prise_profit_pct,
                                             nb_tp_partiel);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_WMA8  != INVALID_HANDLE) IndicatorRelease(handle_WMA8);
   if(handle_WMA38 != INVALID_HANDLE) IndicatorRelease(handle_WMA38);
   if(handle_WMA200!= INVALID_HANDLE) IndicatorRelease(handle_WMA200);
}
