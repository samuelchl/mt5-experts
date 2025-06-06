//+------------------------------------------------------------------+
//|                                             Strategie_ADX.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "1.00"
#property strict

#include <SamBotUtils.mqh>
#include <TradeFilters.mqh>

//+------------------------------------------------------------------+
//| Expert configuration                                            |
//+------------------------------------------------------------------+
// Paramètres généraux
input ENUM_TIMEFRAMES TF                    = PERIOD_CURRENT;
input int    MAGIC_NUMBER                   = 15975344;

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
input int OppositecandleConsecutiveToClose = 3;
input ENUM_TIMEFRAMES TF_opposite_candle = PERIOD_CURRENT;

input int MaxOpenPositions = 5;

input ENUM_TIMEFRAMES TF_FILTER = PERIOD_CURRENT;
input FilterMode filterMode = FILTER_RSI_HIGH_BOTH;
input int    RSI_FILTER_Period                     = 14;
input double rsi_buy_level = 30.0;
input double rsiSellLevel = 70.0;
input int lookbackFilter = 50;
input double bufferPctFilter = 1.0;
input bool activerPente = false;

input int close_all_pos_treshold = -10000;

input bool useDailylimiter = false;
input double neg_Seuil = -0.005;
input double Pos_Seuil = +0.01;
input double trailing_buffer = 0.002;

//--- Handles pour l’ADX
int handle_ADX;

 double ADXBuf[2], plusDIBuf[2], minusDIBuf[2]; // Récupérer valeurs actuelle et précédente

TradeFilterContext filterCtx;

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
   
   if (!InitTradeFilters(filterCtx, _Symbol, TF_FILTER, RSI_FILTER_Period,
   rsi_buy_level,rsiSellLevel,lookbackFilter,bufferPctFilter
    ,filterMode)){
   
      Print("Erreur à la création du handle Filter rsi");
      return INIT_FAILED;
   }
      
   
   return(INIT_SUCCEEDED);
}


int GetCountOpenPosition(){


 // Limite de positions ouvertes
   int total = PositionsTotal();
   int count = 0;

   for(int i = 0; i < total; i++)
      {
         if(PositionGetTicket(i))
         {
            string symb = PositionGetString(POSITION_SYMBOL);
            ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
   
            if(symb == _Symbol && magic == (ulong)MAGIC_NUMBER)
            {
               count++;
            }
         }
      }
      
      return count;

}

bool CanOpenTrade()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   // day_of_week: 0=Sunday, 1=Monday,...,5=Friday
   if(now.day_of_week == 5 && !tradeVendredi)
      return false;

   if(GetCountOpenPosition() >= MaxOpenPositions)
      return false;
      
    if(useDailylimiter && limiter.IsTradingStopped())
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Fermeture de toutes les positions                                |
//+------------------------------------------------------------------+
void CloseAllPositions2()
{
   int total = PositionsTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      SamBotUtils::tradeClose(_Symbol, MAGIC_NUMBER,ticket);
   }
}

// Calcule le profit flottant total des positions ouvertes
double GetTotalFloatingProfit()
{
    double totalProfit = 0.0;
    int total = PositionsTotal();
    
    for(int i = 0; i < total; i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
                totalProfit += PositionGetDouble(POSITION_PROFIT);
        }
    }
    
    return totalProfit;
}

// Ferme toutes les positions ouvertes associées à _Symbol et MAGIC_NUMBER
void CloseAllPositions()
{
    int total = PositionsTotal();
    
    for(int i = total - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(PositionSelectByTicket(ticket))
            {
                // Ajoute ici une vérification si tu veux filtrer par _Symbol et MAGIC_NUMBER
                if(PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER &&
                   PositionGetString(POSITION_SYMBOL) == _Symbol)
                {
                    SamBotUtils::tradeClose(_Symbol, MAGIC_NUMBER, ticket);
                }
            }
        }
    }
}


void CloseAllPositionsIfLossBelow(double lossThreshold)
{
    double totalProfit = GetTotalFloatingProfit();
    if(totalProfit <= lossThreshold)
    {
        CloseAllPositions();
    }
}


#include <DailyLimiter.mqh>

DailyProfitLimiter limiter;

void OnTick()
{
    limiter.OnTick(useDailylimiter,neg_Seuil,Pos_Seuil,trailing_buffer);

    CloseAllPositionsIfLossBelow(close_all_pos_treshold);

   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, TF, 0);
   if(lastTime == currentTime) 
      return;
   lastTime = currentTime;
   
   int spread_points = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(showAlive)
      Print(IntegerToString(MAGIC_NUMBER) + " alive" + " spread "  + IntegerToString(spread_points) + "cntOpenPos :" +IntegerToString(GetCountOpenPosition()));

   
   if(CopyBuffer(handle_ADX, 0, 0, 2, ADXBuf) < 2) return;
   if(CopyBuffer(handle_ADX, 1, 0, 2, plusDIBuf) < 2) return;
   if(CopyBuffer(handle_ADX, 2, 0, 2, minusDIBuf) < 2) return;
   
   // Valeurs actuelles et précédentes
   double adx      = ADXBuf[0];
   double adxPrev  = ADXBuf[1];
   double pDI      = plusDIBuf[0];
   double pDIPrev  = plusDIBuf[1];
   double mDI      = minusDIBuf[0];
   double mDIPrev  = minusDIBuf[1];
   
   bool tendanceForte = (adx > Seuil_ADX);
   
   // Déclaration des conditions
   bool buyCondition = false;
   bool sellCondition = false;
   
   // Logique sans ou avec pente selon l’input
   if(!activerPente)
   {
      // Mode simple : juste ADX + dominance directionnelle
      buyCondition  = tendanceForte && (pDI > mDI);
      sellCondition = tendanceForte && (mDI > pDI);
   }
   else
   {
      // Mode avancé : on ajoute la pente à la logique
      bool penteADX   = (adx > adxPrev);
      bool penteBuy   = (pDI > pDIPrev) && (mDI < mDIPrev);  // +DI monte, -DI baisse
      bool penteSell  = (mDI > mDIPrev) && (pDI < pDIPrev);  // -DI monte, +DI baisse
   
      buyCondition  = tendanceForte && (pDI > mDI) && penteADX && penteBuy;
      sellCondition = tendanceForte && (mDI > pDI) && penteADX && penteSell;
   }

      // Récupérer toutes les positions ouvertes pour le symbole et magic
      SamBotUtils::PositionInfo openPositions[];
      int count = 0;
      
      SamBotUtils::GetOpenPositions(_Symbol,MAGIC_NUMBER, openPositions, count);
      
      if(sortie_dynamique)
      {
         for(int i = 0; i < count; i++)
         {
            SamBotUtils::PositionInfo pos = openPositions[i];
      
            if(pos.profit < 0.0)
            {
               // BUY → 3 bougies rouges M15
               if(pos.type == POSITION_TYPE_BUY
                  && HasConsecutiveBarsSinceOpen(pos.open_time, -1, OppositecandleConsecutiveToClose, TF_opposite_candle))
               {
                  SamBotUtils::tradeClose(_Symbol, MAGIC_NUMBER, pos.ticket);
               }
               // SELL → 3 bougies vertes M15
               else if(pos.type == POSITION_TYPE_SELL
                  && HasConsecutiveBarsSinceOpen(pos.open_time, +1, OppositecandleConsecutiveToClose, TF_opposite_candle))
               {
                  SamBotUtils::tradeClose(_Symbol, MAGIC_NUMBER, pos.ticket);
               }
            }
         }
      }
      
      // Ouverture de position
      if(buyCondition && CanOpenTrade() && canOpenBuy(filterCtx))
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_BUY,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
      if(sellCondition && CanOpenTrade() && canOpenSell(filterCtx))
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_SELL,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
   



   // Trailing Stop
   SamBotUtils::GererTrailingStop(_Symbol, (ulong)MAGIC_NUMBER,
                                  utiliser_trailing_stop,
                                  trailing_stop_pct);

   // Prises de profit partielles
   SamBotUtils::GererPrisesProfitsPartielles(_Symbol, (ulong)MAGIC_NUMBER,
                                             utiliser_prise_profit_partielle,
                                             tranche_prise_profit_pct,
                                             nb_tp_partiel,SL_BreakEVEN_after_first_partialTp, closeIfVolumeLow,percentToCloseTrade);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_ADX != INVALID_HANDLE) 
      IndicatorRelease(handle_ADX);
}

//+------------------------------------------------------------------+
//| Fonction générique : détecte N bougies consécutives              |
//|  direction = +1 pour bougies vertes (close>open)                 |
//|  direction = -1 pour bougies rouges (close<open)                 |
//+------------------------------------------------------------------+
bool HasConsecutiveBarsSinceOpen(datetime open_time,
                                 int direction,     // +1 ou -1
                                 int requiredCount, // ex. 3
                                 ENUM_TIMEFRAMES tf = PERIOD_M15)
  {
   // 1) trouver l'index de la bougie tf contenant open_time
   int startBar = iBarShift(_Symbol, tf, open_time, true);
   if(startBar < 0)
      return(false);

   int count = 0;
   // 2) parcourir toutes les bougies fermées après l'ouverture
   for(int i = startBar - 1; i >= 1; i--)
     {
      double op = iOpen (_Symbol, tf, i);
      double cl = iClose(_Symbol, tf, i);

      // test en fonction de la direction
      if(direction > 0 ? (cl > op) : (cl < op))
        {
         if(++count >= requiredCount)
            return(true);
        }
      else
        {
         count = 0; // rupture de la séquence
        }
     }
   return(false);
  }
