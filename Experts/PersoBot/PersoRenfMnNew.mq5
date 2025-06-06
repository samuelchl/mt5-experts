//+------------------------------------------------------------------+
//|                                             Strategie_WMA.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "1.00"
#property strict

#include <SamBotUtils.mqh>

//--- paramètres de l'EA configurables
input double seuil_proximite                = 0.1;    // Seuil de proximité (%)
input double take_profit_pct                = 1.0;    // Take profit (%)
input double stop_loss_pct                  = 1.0;    // Stop loss (%)
input bool   sortie_dynamique               = true;   // Sortie dynamique
input ENUM_TIMEFRAMES TF                    = PERIOD_CURRENT;

input bool   GestionDynamiqueLot            = true;   // Gestion dynamique du lot
input double RisqueParTradePct              = 1.0;    // Risque par trade en %
input double LotFixe                        = 0.1;    // Lot fixe si non dynamique

input bool   utiliser_trailing_stop         = true;   // Activer Trailing Stop
input double trailing_stop_pct              = 0.2;    // Trailing Stop (%)

input bool   utiliser_prise_profit_partielle= true;   // Activer TP partiels
input double tranche_prise_profit_pct       = 0.25;   // % par tranche
input int    nb_tp_partiel                  = 3;      // nombre de tranches

input int    MAGIC_NUMBER                   = 569873;

//--- Moving averages
int    handle_WMA8, handle_WMA38, handle_WMA200;
double WMA8[], WMA38[], WMA200[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   handle_WMA8   = iMA(_Symbol, TF, 8,   0, MODE_LWMA, PRICE_CLOSE);
   handle_WMA38  = iMA(_Symbol, TF, 38,  0, MODE_LWMA, PRICE_CLOSE);
   handle_WMA200 = iMA(_Symbol, TF, 200, 0, MODE_LWMA, PRICE_CLOSE);
   if(handle_WMA8==INVALID_HANDLE || handle_WMA38==INVALID_HANDLE || handle_WMA200==INVALID_HANDLE)
   {
      Print("Erreur lors de la création des handles MA");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}


//+------------------------------------------------------------------+
//| Expert tick                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, TF, 0);
   if(currentTime == lastTime) return;
   lastTime = currentTime;

   // Charger les valeurs clôturées uniquement
   if(CopyBuffer(handle_WMA8,   0, 0, 3, WMA8)   < 3) return;
   if(CopyBuffer(handle_WMA38,  0, 0, 3, WMA38)  < 3) return;
   if(CopyBuffer(handle_WMA200, 0, 0, 2, WMA200) < 2) return;

   // Valeurs clôturées (barres 1 et 2)
   double wma8_1   = WMA8[1],   wma8_2   = WMA8[2];
   double wma38_1  = WMA38[1],  wma38_2  = WMA38[2];
   double wma200_1 = WMA200[1];

   // Signaux d'entrée
   bool buyCondition  = SamBotUtils::isRejet3WMARenforce(
                           wma8_1, wma8_2,
                           wma38_1, wma38_2,
                           wma200_1,
                           "up",   seuil_proximite);
   bool sellCondition = SamBotUtils::isRejet3WMARenforce(
                           wma8_1, wma8_2,
                           wma38_1, wma38_2,
                           wma200_1,
                           "down", seuil_proximite);

      // Affichage visuel
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

   // Gestion des positions
   bool hasPos = SamBotUtils::IsTradeOpen(_Symbol, (ulong)MAGIC_NUMBER);
   if(hasPos)
   {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      if(sortie_dynamique)
      {
         if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY  && sellCondition)
            SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
         else if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && buyCondition)
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
                                RisqueParTradePct);
      if(sellCondition)
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_SELL,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct);
   }

   // Trailing stop et TP partiels
   SamBotUtils::GererTrailingStop(
      _Symbol, (ulong)MAGIC_NUMBER,
      utiliser_trailing_stop,
      trailing_stop_pct);

   SamBotUtils::GererPrisesProfitsPartielles3(
      _Symbol, (ulong)MAGIC_NUMBER,
      utiliser_prise_profit_partielle,
      tranche_prise_profit_pct,
      nb_tp_partiel);
      
      //GererPrisesProfitsPartielles();
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_WMA8   != INVALID_HANDLE) IndicatorRelease(handle_WMA8);
   if(handle_WMA38  != INVALID_HANDLE) IndicatorRelease(handle_WMA38);
   if(handle_WMA200 != INVALID_HANDLE) IndicatorRelease(handle_WMA200);
}

