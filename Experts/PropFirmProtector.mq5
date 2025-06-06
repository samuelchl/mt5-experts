//+------------------------------------------------------------------+
//|                                            PropFirmProtector.mq5 |
//|                        Adapté pour règles Prop Firm strictes     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.01"

#include <Trade/Trade.mqh>
#include <SamBotUtils.mqh>
#include <VarCalculator.mqh>
#include <VarCalculatorV2.mqh>
CTrade trade;

// Paramètres fixes
input double INITIAL_ACCOUNT_BALANCE = 100000;       // Capital de départ
input double PROFIT_TARGET_PCT = 10;                 // Objectif de profit en %
input double MAX_GLOBAL_DRAWDOWN = 10000;            // Drawdown global fixe
input double MAX_DAILY_DRAWDOWN = 5000;              // Drawdown journalier max
input double DRAWDOWN_BUFFER_PCT = 10;              // Buffer de sécurité (optionnel)
input double Profit_BUFFER_PCT = 0.5;   

double PROFIT_TARGET_BALANCE;
double MAX_GLOBAL_DD_LEVEL;

double day_starting_balance = 0;
int barsD1 = 0;

input bool debug = false;

VarCalculator varCalculator;
VarCalculatorV2 varCalculator2;


//+------------------------------------------------------------------+
//| Initialisation                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   PROFIT_TARGET_BALANCE = INITIAL_ACCOUNT_BALANCE * (1 + PROFIT_TARGET_PCT / 100.0);
   MAX_GLOBAL_DD_LEVEL = INITIAL_ACCOUNT_BALANCE - MAX_GLOBAL_DRAWDOWN;
   
   varCalculator.Init("XAUUSD", 100, 2.33, PERIOD_H1);
   varCalculator.UpdateVolatility();
   
   varCalculator2.Init("XAUUSD", 100, 2.33, PERIOD_H1, true);
   varCalculator2.UpdateVolatility();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Tick principal                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   
   PrintVar();
   PrintVar2();
   
   SamBotUtils::CloseSmallProfitablePositionsV2();
   
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   int currentBarsD1 = iBars(_Symbol, PERIOD_D1);
   if (barsD1 != currentBarsD1)
   {
      day_starting_balance = balance;
      barsD1 = currentBarsD1;
   }

   // Si pas encore initialisé (ex. au premier tick)
   if (day_starting_balance == 0)
      day_starting_balance = balance;

   // Calcul du max drawdown autorisé aujourd'hui
   double remaining_to_global_limit = day_starting_balance - MAX_GLOBAL_DD_LEVEL;
   double allowed_daily_loss = MathMin(MAX_DAILY_DRAWDOWN, remaining_to_global_limit);
   double allowed_daily_dd_level = day_starting_balance - allowed_daily_loss;

   // Application du buffer (optionnel)
   double buffer_factor = 1 + DRAWDOWN_BUFFER_PCT / 100.0;
   double buffer_factor_profit = 1 + Profit_BUFFER_PCT / 100.0;

   if (debug){
   
      Print ("equity : " + DoubleToString(equity));
      Print ("PROFIT_TARGET_BALANCE * buffer_profit : " + DoubleToString(PROFIT_TARGET_BALANCE * buffer_factor_profit));
      Print ("allowed_daily_dd_level * buffer_dd :" + DoubleToString(allowed_daily_dd_level * buffer_factor));
      Print ("MAX_GLOBAL_DD_LEVEL * buffer_dd :" + DoubleToString(MAX_GLOBAL_DD_LEVEL * buffer_factor));
      
         }

   // Vérification des conditions
   if (equity >= PROFIT_TARGET_BALANCE * buffer_factor_profit ||
       equity < allowed_daily_dd_level * buffer_factor ||
       equity < MAX_GLOBAL_DD_LEVEL * buffer_factor)
   {
      Print("🔒 Limite atteinte : fermeture des positions.");
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Fermeture de toutes les positions                                |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int total = PositionsTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!trade.PositionClose(ticket))
      {
         Print("Erreur de fermeture pour ticket ", ticket, ": ", trade.ResultRetcode());
      }
   }
}


static datetime lastVolUpdate2 = 0;

void PrintVar2()
  {
   if(TimeCurrent() - lastVolUpdate2 < 60)
      return; // encore trop tôt pour mettre à jour

   lastVolUpdate2 = TimeCurrent();

   if(!varCalculator2.UpdateVolatility())
     {
      Print("Erreur : mise à jour de la volatilité échouée.");
      return;
     }

   double vol = varCalculator2.GetVolatility();
   Print("Volatilité mise à jour : ", DoubleToString(vol, 6));

   // --- Calcul des lots perdants sur XAUUSD
   double lots_losing = 0.0;
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == "XAUUSD")
           {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit < 0)
               lots_losing += PositionGetDouble(POSITION_VOLUME);
           }
        }
     }

   // --- Calculs VaR
   double var_param = varCalculator2.ComputeVaR(lots_losing);
   double var_hist  = varCalculator2.ComputeHistoricalVaR(lots_losing, 0.01); // 1% historique

   // --- Affichage texte brut sans fantaisie
   PrintFormat("VaR paramétrique (Z=%.2f) pour %.2f lots perdants : %.10f USD",
            varCalculator2.GetZScore(), lots_losing, var_param);

   PrintFormat("VaR historique (1%% percentile) pour %.2f lots perdants : %.2f USD",
               lots_losing, var_hist);
  }


static datetime lastVolUpdate = 0;
void PrintVar(){

 
   if(TimeCurrent() - lastVolUpdate > 60) // update volatilité toutes les 60 sec
     {
      if(varCalculator.UpdateVolatility())
         Print("Volatilité mise à jour : ", DoubleToString(varCalculator.GetVolatility(), 6));
      lastVolUpdate = TimeCurrent();
     

   // Calculer la VaR des positions perdantes sur XAUUSD
   double lots_losing = 0.0;
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
     
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == "XAUUSD")
           {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit < 0)
               lots_losing += PositionGetDouble(POSITION_VOLUME);
           }
        }
     }

   double var_losing = varCalculator.ComputeVaR(lots_losing);
   PrintFormat("VaR positions perdantes XAUUSD : %.2f USD (lots perdants: %.2f)", var_losing, lots_losing);

}
}



