//+------------------------------------------------------------------+
//|                                             Strategie_WMA.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "1.00"
#property strict

//--- paramètres de l'EA configurables
input double seuil_proximite = 0.1;          // Seuil de proximité (%)
input double take_profit_pct = 1;          // Take profit (%)
input double stop_loss_pct = 1;            // Stop loss (%)
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

input int MAGIC_NUMBER = 569873;


//--- Moving averages
int handle_WMA8;
int handle_WMA38;
int handle_WMA200;

//--- Variables globales
double WMA8[], WMA38[], WMA200[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
//int OnInit()
//{
//   // handles des moyennes mobiles WMA
//   handle_WMA8   = iMA(_Symbol, TF, 8, 0, MODE_LWMA, PRICE_CLOSE);
//   handle_WMA38  = iMA(_Symbol, TF, 38, 0, MODE_LWMA, PRICE_CLOSE);
//   handle_WMA200 = iMA(_Symbol, TF, 200, 0, MODE_LWMA, PRICE_CLOSE);
//   
//   if(handle_WMA8 == INVALID_HANDLE || handle_WMA38 == INVALID_HANDLE || handle_WMA200 == INVALID_HANDLE)
//   {
//      Print("Erreur lors de la création des handles MA");
//      return(INIT_FAILED);
//   }
//
//   return(INIT_SUCCEEDED);
//}

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
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, TF, 0);
   if(lastTime == currentTime) return;
   lastTime = currentTime;

   // --- Charger les valeurs clôturées uniquement
   if(CopyBuffer(handle_WMA8,   0, 0, 3, WMA8)   < 3) return;
   if(CopyBuffer(handle_WMA38,  0, 0, 3, WMA38)  < 3) return;
   if(CopyBuffer(handle_WMA200,0, 0, 2, WMA200) < 2) return;

   // Valeurs figées (bougies 1 et 2)
   double wma8_1 = WMA8[1], wma8_2 = WMA8[2];
   double wma38_1 = WMA38[1], wma38_2 = WMA38[2];
   double wma200_1 = WMA200[1];

   // Logique de rejet avec données clôturées
   bool buyCondition  = isRejet3WMA(wma8_1, wma8_2, wma38_1, wma38_2, wma200_1, "up", seuil_proximite);
   bool sellCondition = isRejet3WMA(wma8_1, wma8_2, wma38_1, wma38_2, wma200_1, "down", seuil_proximite);

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

   if(IsTradeOpen())
   {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      if(sortie_dynamique)
      {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && sellCondition)
            tradeClose(ticket);
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && buyCondition)
            tradeClose(ticket);
      }
   }
   else
   {
      if(buyCondition)  tradeOpen(ORDER_TYPE_BUY, stop_loss_pct, take_profit_pct);
      if(sellCondition) tradeOpen(ORDER_TYPE_SELL, stop_loss_pct, take_profit_pct);
   }

   GererTrailingStop();
   GererPrisesProfitsPartielles();
}

bool IsTradeOpen(){

   for(int i = PositionsTotal()-1; i>=0; i--){
   
      ulong position_ticket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(position_ticket)){
      
         if(PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER && PositionGetSymbol(POSITION_SYMBOL) == _Symbol ){
            
            return true;
         
         }
      
      }
      
  
   
   }
   
   return false;
}


//+------------------------------------------------------------------+
//| Fonctions pour ouverture/fermeture des ordres                    |
//+------------------------------------------------------------------+
void tradeOpen(ENUM_ORDER_TYPE type, double sl_pct, double tp_pct)
{
   double price = SymbolInfoDouble(_Symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   double sl = price - (type==ORDER_TYPE_BUY?1:-1)*price*sl_pct/100.0;
   double tp = price + (type==ORDER_TYPE_BUY?1:-1)*price*tp_pct/100.0;
   
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
   request.volume = CalculerLotSize(slPips);
   request.price    = price;
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= 10;

   if(!OrderSend(request,result))
      Print("Erreur ouverture ordre : ", result.comment);
}

void tradeClose(ulong ticket)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double price = SymbolInfoDouble(_Symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);
   
   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.position = ticket;
   request.volume   = PositionGetDouble(POSITION_VOLUME);
   request.price    = price;
   request.type     = type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.deviation= 10;

   if(!OrderSend(request,result))
      Print("Erreur fermeture ordre : ", result.comment);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_WMA8!=INVALID_HANDLE) IndicatorRelease(handle_WMA8);
   if(handle_WMA38!=INVALID_HANDLE) IndicatorRelease(handle_WMA38);
   if(handle_WMA200!=INVALID_HANDLE) IndicatorRelease(handle_WMA200);
}


double CalculerLotSize(double slPips)
{
   if(!GestionDynamiqueLot)
      return(LotFixe);

   double valeurTick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tailleTick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   double montantRisque = balance * RisqueParTradePct / 100.0;
   double lot = montantRisque / (slPips * (valeurTick / tailleTick));

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;

   lot = MathMax(minLot, MathMin(maxLot, lot));

   return NormalizeDouble(lot, 2);
}


void GererTrailingStop()
{
   if(!utiliser_trailing_stop) return;

   for(int i = PositionsTotal()-1; i >= 0; i--)
{
   if(PositionGetTicket(i) && PositionSelectByTicket(PositionGetTicket(i)))
   {
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      double prix_actuel_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double prix_actuel_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double prix_position   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl_actuel       = PositionGetDouble(POSITION_SL);
      ulong ticket           = PositionGetInteger(POSITION_TICKET);
      ENUM_POSITION_TYPE type= (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double nouveau_sl;

      // Gestion BUY
      if(type == POSITION_TYPE_BUY)
      {
         nouveau_sl = prix_actuel_bid - (prix_actuel_bid * trailing_stop_pct / 100.0);

         if(nouveau_sl > prix_position && (nouveau_sl > sl_actuel || sl_actuel == 0))
            ModifierSL(ticket, nouveau_sl);
      }
      // Gestion SELL
      else if(type == POSITION_TYPE_SELL)
      {
         nouveau_sl = prix_actuel_ask + (prix_actuel_ask * trailing_stop_pct / 100.0);

         if(nouveau_sl < prix_position && (nouveau_sl < sl_actuel || sl_actuel == 0))
            ModifierSL(ticket, nouveau_sl);
      }
   }
   }
}

// Fonction pour modifier le SL :
void ModifierSL(ulong ticket, double nouveau_sl)
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_SLTP;
   request.symbol   = _Symbol;
   request.position = ticket;
   request.sl       = NormalizeDouble(nouveau_sl, _Digits);
   request.tp       = PositionGetDouble(POSITION_TP);

   if(!OrderSend(request, result))
      Print("Erreur Trailing Stop : ", result.comment);
}


void GererPrisesProfitsPartielles()
{
   if(!utiliser_prise_profit_partielle)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER || PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

         double prix_ouverture = PositionGetDouble(POSITION_PRICE_OPEN);
         double prix_tp_final = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE type_position = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volume_initial = PositionGetDouble(POSITION_VOLUME);
         double volume_restant = volume_initial;

         double prix_actuel_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double prix_actuel_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         for(int n = 1; n <= nb_tp_partiel; n++)
         {
            double niveau_pct = tranche_prise_profit_pct * n;

            // BUY
            if(type_position == POSITION_TYPE_BUY)
            {
               double tp_level = prix_ouverture + niveau_pct * (prix_tp_final - prix_ouverture);
               if(prix_actuel_bid >= tp_level && volume_restant >= volume_initial * (1.0 - tranche_prise_profit_pct * n))
               {
                  FermerPartiellement(volume_initial * tranche_prise_profit_pct);
               }
            }
            // SELL
            else if(type_position == POSITION_TYPE_SELL)
            {
               double tp_level = prix_ouverture - niveau_pct * (prix_ouverture - prix_tp_final);
               if(prix_actuel_ask <= tp_level && volume_restant >= volume_initial * (1.0 - tranche_prise_profit_pct * n))
               {
                  FermerPartiellement(volume_initial * tranche_prise_profit_pct);
               }
            }
         }
      }
   }
}



// Fonction pour fermer partiellement une position :
void FermerPartiellement(double volume_a_fermer)
{
    if (volume_a_fermer < 0.01)
      return;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double prix = SymbolInfoDouble(_Symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);
   
   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.position = PositionGetInteger(POSITION_TICKET);
   request.volume   = NormalizeDouble(volume_a_fermer, 2);
   request.price    = prix;
   request.type     = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.deviation= 10;

   if(!OrderSend(request, result))
      Print("Erreur prise profit partielle : ", result.comment);
}