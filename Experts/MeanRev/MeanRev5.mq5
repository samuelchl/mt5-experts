#include <Trade\Trade.mqh>
CTrade trade;

// === Paramètres utilisateur

input double ExitThreshold = 0.0;  // Seuil de clôture (ex : 0.0 = pur retour à la moyenne)

input int    InpSlippage    = 5;
input int    secondsWaiting = 15;
input bool   showAlive      = true;
input int    MAGIC_NUMBER   = 5555555;
input double stop_loss_pct                  = 1.0;
input double take_profit_pct                = 2.0;
input bool   GestionDynamiqueLot            = false;
input double RisqueParTradePct              = 1.0;
input double LotFixe                        = 0.1;
// Paramètres spread
input bool   UseMaxSpread                   = false;
input int    MaxSpreadPoints                = 40;
input bool SL_BreakEVEN_after_first_partialTp = false;

input bool closeIfVolumeLow =false;
input double percentToCloseTrade =0.20;

input double EntryThreshold = 2.0;  // Seuil d'entrée (ex: 2.0)

// === Paramètres indicateur (doivent correspondre à l’indicateur ZScore_EACoherent)
input int      InpWindow       = 30;          // Fenêtre MA
input double   InpStdDevRatio  = 0.4;         // Ratio de fenêtre StdDev
input double   InpK            = 2.5;         // Multiplicateur d’écart‑type
input double   InpEpsilon      = 1e-8;        // Stabilité division
input ENUM_APPLIED_PRICE PriceType = PRICE_MEDIAN;
input ENUM_TIMEFRAMES TF = PERIOD_CURRENT;

// Paramètres Prises de profit partielles
input bool   utiliser_prise_profit_partielle= false;
input double tranche_prise_profit_pct       = 0.02;
input int    nb_tp_partiel                  = 2;


#include <SamBotUtils.mqh>

// --- Handle de l’indicateur
int handleZ;

int OnInit()
{
   handleZ = iCustom(_Symbol, TF, "ZScore_ExactEA",
                     InpWindow, InpStdDevRatio, InpK, InpEpsilon,PriceType,TF);

   if(handleZ == INVALID_HANDLE)
   {
      Print("⛔ Erreur chargement de ZScore_ExactEA");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(handleZ != INVALID_HANDLE)
      IndicatorRelease(handleZ);
}

void OnTick()
{
   static datetime lastTime = 0;
   datetime now = TimeCurrent();
   if(now - lastTime < secondsWaiting)
      return;
   lastTime = now;

   if(showAlive) Print(IntegerToString(MAGIC_NUMBER) + " alive");

   // === Contrôle du spread
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);



   // === Lecture du z-score (bougie fermée i = 1)
   double z_buf[1];
   if(CopyBuffer(handleZ, 0, 1, 1, z_buf) != 1)
   {
      Print("⛔ Erreur lecture z-score");
      return;
   }

   double z = z_buf[0];
   if(showAlive) Print("Z = ", DoubleToString(z, 4));

   // === État des positions
   bool hasPos    = PositionSelect(_Symbol);
   bool hasLong   = hasPos && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   bool hasShort  = hasPos && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL;


   

   // === Entrée Short
   if(z > EntryThreshold && !hasShort)
   {
      if(hasLong) {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
      }
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
   // === Sortie Short
   else if(z <= ExitThreshold && hasShort)
   {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
   }

   // === Entrée Long
   if(z < -EntryThreshold && !hasLong)
   {
      if(hasShort) {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
      
      }
      
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
   // === Sortie Long
   else if(z >= ExitThreshold && hasLong)
   {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
   }
   
      // Prises de profit partielles
   SamBotUtils::GererPrisesProfitsPartielles(_Symbol, (ulong)MAGIC_NUMBER,
                                             utiliser_prise_profit_partielle,
                                             tranche_prise_profit_pct,
                                             nb_tp_partiel,SL_BreakEVEN_after_first_partialTp, closeIfVolumeLow,percentToCloseTrade);
}
