//+------------------------------------------------------------------+
//|                                             Strategie_WMA.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+

#include <SamBotUtils.mqh>

#property copyright "Adaptation MT5"
#property version   "1.00"
#property strict

//--- paramètres de l'EA configurables
input double seuil_proximite = 0.2;          // Seuil de proximité (%)
input double take_profit_pct = 200;          // Take profit (%)
input double stop_loss_pct = 0.1;            // Stop loss (%)
input bool   sortie_dynamique = true;        // Sortie dynamique
input ENUM_TIMEFRAMES TF = PERIOD_CURRENT;   // Timeframe de travail

input bool   GestionDynamiqueLot = true;      // Utiliser gestion dynamique du lot
input double RisqueParTradePct   = 1.0;       // Risque par trade en %
input double LotFixe             = 0.1;       // Lot fixe (si gestion dynamique désactivée)

input bool   utiliser_trailing_stop = true;      // Activer Trailing Stop
input double trailing_stop_pct = 0.2;            // Trailing Stop (%)

input bool utiliser_prise_profit_partielle = true;  // Activation des prises profit partielles
input double tranche_prise_profit_pct = 0.25;       // Fraction de fermeture à chaque TP partiel (ici 25%)
input int nb_tp_partiel = 3;          // nb TP partiel (

input int MAGIC_NUMBER = 123456789;


//--- Moving averages
int handle_WMA8;
int handle_WMA38;
int handle_WMA200;

//--- Variables globales
double WMA8[], WMA38[], WMA200[];

static SamBotUtils utils(
   _Symbol,
   (ulong)MAGIC_NUMBER,
   tranche_prise_profit_pct,
   nb_tp_partiel,
   utiliser_prise_profit_partielle,
   GestionDynamiqueLot,
   LotFixe,
   RisqueParTradePct,
   utiliser_trailing_stop,
   trailing_stop_pct
);

int OnInit()
{
   handle_WMA8   = iMA(_Symbol, TF, 8, 0, MODE_LWMA, PRICE_CLOSE);
   handle_WMA38  = iMA(_Symbol, TF, 38, 0, MODE_LWMA, PRICE_CLOSE);
   handle_WMA200 = iMA(_Symbol, TF, 200, 0, MODE_LWMA, PRICE_CLOSE);

   if(handle_WMA8 == INVALID_HANDLE || handle_WMA38 == INVALID_HANDLE || handle_WMA200 == INVALID_HANDLE)
   {
      Print("Erreur lors de la création des handles MA");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}


// Fonction de rejet (inspirée de Pine)
bool isRejet3WMA(double fast0, double fast1, double slow0, double slow1, double trend,
                 string sens, double seuil)
{
   double diffNow  = fast0 - slow0;
   double diffPrev = fast1 - slow1;
   double ecart    = MathAbs(diffNow);
   bool proche     = ecart <= MathAbs(slow0 * seuil / 100.0);

   bool rejet = false;
   if(sens == "up")
      rejet = (diffPrev < 0 && diffNow > 0 && fast0 > trend && slow0 > trend);
   else if(sens == "down")
      rejet = (diffPrev > 0 && diffNow < 0 && fast0 < trend && slow0 < trend);

   return rejet && proche;
}

void OnTick()
{
   // synchronisation sur la barre
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, TF, 0);
   if(lastTime == currentTime) return;
   lastTime = currentTime;

   // remplir les buffers
   if(CopyBuffer(handle_WMA8,   0, 0, 2, WMA8)   < 2) return;
   if(CopyBuffer(handle_WMA38,  0, 0, 2, WMA38)  < 2) return;
   if(CopyBuffer(handle_WMA200, 0, 0, 1, WMA200) < 1) return;

   double wma8_0  = WMA8[0],  wma8_1  = WMA8[1];
   double wma38_0 = WMA38[0], wma38_1 = WMA38[1];
   double wma200_0= WMA200[0];

   bool buyCondition  = isRejet3WMA(wma8_0, wma8_1, wma38_0, wma38_1, wma200_0, "up",   seuil_proximite);
   bool sellCondition = isRejet3WMA(wma8_0, wma8_1, wma38_0, wma38_1, wma200_0, "down", seuil_proximite);

   // flèches graphiques
   if(buyCondition)
   {
     double lowPrice = iLow(_Symbol, TF, 1);
     ObjectCreate(0, "buy"+TimeToString(TimeCurrent()), OBJ_ARROW_UP, 0, TimeCurrent(), lowPrice);
   }
   if(sellCondition)
   {
     double highPrice= iHigh(_Symbol, TF, 1);
     ObjectCreate(0, "sell"+TimeToString(TimeCurrent()), OBJ_ARROW_DOWN, 0, TimeCurrent(), highPrice);
   }

   // gestion des positions
   if(utils.IsTradeOpen())
   {
      // on récupère le ticket de la position courante
      ulong ticket = PositionGetInteger(POSITION_TICKET);

      if(sortie_dynamique)
      {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && sellCondition)
            utils.TradeClose(ticket);
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && buyCondition)
            utils.TradeClose(ticket);
      }
   }
   else
   {
      if(buyCondition)
         utils.TradeOpen(ORDER_TYPE_BUY, stop_loss_pct, take_profit_pct);
      if(sellCondition)
         utils.TradeOpen(ORDER_TYPE_SELL, stop_loss_pct, take_profit_pct);
   }

   // trailing stop et TP partiels via la classe
   utils.GererTrailingStop();
   utils.GererPrisesProfitsPartielles();
}



//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_WMA8!=INVALID_HANDLE) IndicatorRelease(handle_WMA8);
   if(handle_WMA38!=INVALID_HANDLE) IndicatorRelease(handle_WMA38);
   if(handle_WMA200!=INVALID_HANDLE) IndicatorRelease(handle_WMA200);
}


