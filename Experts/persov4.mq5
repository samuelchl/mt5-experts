//+------------------------------------------------------------------+
//|                                             Strategie_WMA.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "1.01"
#property strict

//--- paramètres de l'EA configurables
input double seuil_proximite = 0.1; // Seuil de proximité (%)
input double take_profit_pct = 3; // Take profit (%)
input double stop_loss_pct = 1; // Stop loss (%)
input bool   sortie_dynamique = true; // Sortie dynamique
input ENUM_TIMEFRAMES TF = PERIOD_CURRENT; // Timeframe de travail

input bool   GestionDynamiqueLot = true; // Utiliser gestion dynamique du lot
input double RisqueParTradePct   = 1.0; // Risque par trade en %
input double LotFixe             = 0.1; // Lot fixe (si gestion dynamique désactivée)

input bool   utiliser_trailing_stop = true; // Activer Trailing Stop
input double trailing_stop_pct = 0.2; // Trailing Stop (%)

input bool utiliser_prise_profit_partielle = true;  // Activation des prises profit partielles





//--- Variables pour ATH/ATL
double ATH = 0;
double ATL = 0;
datetime lastWeeklyUpdate = 0;

//--- Moving averages
int handle_WMA8;
int handle_WMA38;
int handle_WMA200;
double WMA8[], WMA38[], WMA200[];

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
   
   // ATH/ATL INIT only once here
   const int nbWeeks = 104;
   double highs[], lows[];

   if (CopyHigh(_Symbol, PERIOD_W1, 1, nbWeeks, highs) == nbWeeks &&
       CopyLow(_Symbol, PERIOD_W1, 1, nbWeeks, lows) == nbWeeks)
   {
      ATH = highs[0];
      ATL = lows[0];
      for (int i = 1; i < nbWeeks; i++)
      {
         if (highs[i] > ATH) ATH = highs[i];
         if (lows[i] < ATL) ATL = lows[i];
      }
   }

   return(INIT_SUCCEEDED);

   return(INIT_SUCCEEDED);
}


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
    double prix_actuel = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (prix_actuel > ATH) ATH = prix_actuel;
   if (prix_actuel < ATL) ATL = prix_actuel;

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

   if(PositionSelect(_Symbol))
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

void tradeOpen(ENUM_ORDER_TYPE type, double sl_pct, double tp_pct)
{
   double price = SymbolInfoDouble(_Symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   double sl = price - (type==ORDER_TYPE_BUY?1:-1)*price*sl_pct/100.0;

   double tp_calcule = price + (type == ORDER_TYPE_BUY ? 1 : -1) * price * tp_pct / 100.0;
   double tp_final = tp_calcule;

   if(type == ORDER_TYPE_BUY)
      tp_final = MathMin(tp_calcule, ATH);
   else
      tp_final = MathMax(tp_calcule, ATL);

   if ((type == ORDER_TYPE_BUY  && tp_final <= price) ||
       (type == ORDER_TYPE_SELL && tp_final >= price))
   {
      Print("TP invalide, ordre non ouvert. TP: ", tp_final, " Prix: ", price);
      return;
   }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.type     = type;
   double slPips = MathAbs(price - sl) / SymbolInfoDouble(_Symbol, SYMBOL_POINT) / 10.0;
   request.volume = CalculerLotSize(slPips);
   request.price    = price;
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp_final, _Digits);
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

   if(PositionSelect(_Symbol))
   {
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
   if(!utiliser_prise_profit_partielle || !PositionSelect(_Symbol))
      return;

   double prix_ouverture = PositionGetDouble(POSITION_PRICE_OPEN);
   double prix_tp_final = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE type_position = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double volume_initial = PositionGetDouble(POSITION_VOLUME);
   double volume_restant = volume_initial;

   double prix_actuel_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double prix_actuel_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double tp25 = prix_ouverture + 0.25*(prix_tp_final - prix_ouverture);
   double tp50 = prix_ouverture + 0.50*(prix_tp_final - prix_ouverture);
   double tp75 = prix_ouverture + 0.75*(prix_tp_final - prix_ouverture);

   if(type_position == POSITION_TYPE_BUY)
   {
      if(prix_actuel_bid >= tp25 && volume_restant >= volume_initial * 0.75)
         FermerPartiellement(volume_initial * 0.25);

      else if(prix_actuel_bid >= tp50 && volume_restant >= volume_initial * 0.50)
         FermerPartiellement(volume_initial * 0.25);

      else if(prix_actuel_bid >= tp75 && volume_restant >= volume_initial * 0.25)
         FermerPartiellement(volume_initial * 0.25);
      // la dernière tranche se fermera automatiquement au TP final
   }
   else if(type_position == POSITION_TYPE_SELL)
   {
      tp25 = prix_ouverture - 0.25*(prix_ouverture - prix_tp_final);
      tp50 = prix_ouverture - 0.50*(prix_ouverture - prix_tp_final);
      tp75 = prix_ouverture - 0.75*(prix_ouverture - prix_tp_final);

      if(prix_actuel_ask <= tp25 && volume_restant >= volume_initial * 0.75)
         FermerPartiellement(volume_initial * 0.25);

      else if(prix_actuel_ask <= tp50 && volume_restant >= volume_initial * 0.50)
         FermerPartiellement(volume_initial * 0.25);

      else if(prix_actuel_ask <= tp75 && volume_restant >= volume_initial * 0.25)
         FermerPartiellement(volume_initial * 0.25);
      // la dernière tranche se fermera automatiquement au TP final
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