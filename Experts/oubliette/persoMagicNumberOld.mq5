//+------------------------------------------------------------------+
//|                                             Strategie_WMA.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
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

   if(CopyBuffer(handle_WMA8,   0, 0, 2, WMA8)   < 2) return;
   if(CopyBuffer(handle_WMA38,  0, 0, 2, WMA38)  < 2) return;
   if(CopyBuffer(handle_WMA200,0, 0, 1, WMA200) < 1) return;

   double wma8_0 = WMA8[0], wma8_1 = WMA8[1];
   double wma38_0 = WMA38[0], wma38_1 = WMA38[1];
   double wma200_0 = WMA200[0];

   bool buyCondition  = isRejet3WMA(wma8_0, wma8_1, wma38_0, wma38_1, wma200_0, "up", seuil_proximite);
   bool sellCondition = isRejet3WMA(wma8_0, wma8_1, wma38_0, wma38_1, wma200_0, "down", seuil_proximite);

   if(buyCondition)
   {
     double lowPrice  = iLow(_Symbol, TF, 1);
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

   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int    prec     = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

   int totalPos = PositionsTotal();
   for(int i = totalPos - 1; i >= 0; i--)
   {
      // 1) récupérer le ticket de la i‑ème position ouverte
      ulong ticket = PositionGetTicket(i);
      // 2) sélectionner la position grâce à son ticket
      if(!PositionSelectByTicket(ticket))
         continue;

      // filtrer par magic number et symbole
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER
         || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      double prixOuverture  = PositionGetDouble(POSITION_PRICE_OPEN);
      double prixTPFinal    = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volumeInitial  = PositionGetDouble(POSITION_VOLUME);
      double volumeRestant  = volumeInitial;

      for(int n = 1; n <= nb_tp_partiel; n++)
      {
         double pct     = tranche_prise_profit_pct * n;
         double tpLevel = (typePos == POSITION_TYPE_BUY)
                           ? prixOuverture + pct * (prixTPFinal - prixOuverture)
                           : prixOuverture - pct * (prixOuverture - prixTPFinal);
         double prixActu = (typePos == POSITION_TYPE_BUY)
                           ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         if((typePos == POSITION_TYPE_BUY  && prixActu >= tpLevel) ||
            (typePos == POSITION_TYPE_SELL && prixActu <= tpLevel))
         {
            double volToClose = NormalizeDouble(volumeInitial * tranche_prise_profit_pct, prec);
            if(volToClose < minLot)
               volToClose = minLot;
            if(volumeRestant - volToClose < minLot)
               volToClose = volumeRestant - minLot;
            if(volToClose >= minLot)
            {
               FermerPartiellement(volToClose);
               volumeRestant -= volToClose;
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