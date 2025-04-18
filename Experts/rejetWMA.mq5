//+------------------------------------------------------------------+
//|           Détection et affichage visuel des rejets MA           |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict

//--- Entrées utilisateur
input ENUM_MA_METHOD MAType     = MODE_LWMA;
input int            Period1    = 8;
input int            Period2    = 38;
input int            Period3    = 200;
input ENUM_APPLIED_PRICE PriceType = PRICE_CLOSE;
input double seuil_proximite = 0.1;
input bool   sortie_dynamique = true;        // Sortie dynamique

input double take_profit_pct = 1;          // Take profit (%)
input double stop_loss_pct = 1; 

input bool   GestionDynamiqueLot = true;      // Utiliser gestion dynamique du lot
input double RisqueParTradePct   = 1.0;       // Risque par trade en %
input double LotFixe             = 0.1;       // Lot fixe (si gestion dynamique désactivée)

input double marge_pct = 0.1; // Marge de distance pour valider le rejet (en %)
//--- Handles et buffers
int handleMA1, handleMA2, handleMA3;
double bufferMA1[], bufferMA2[], bufferMA3[];

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   handleMA1 = iMA(_Symbol, PERIOD_CURRENT, Period1, 0, MAType, PriceType);
   handleMA2 = iMA(_Symbol, PERIOD_CURRENT, Period2, 0, MAType, PriceType);
   handleMA3 = iMA(_Symbol, PERIOD_CURRENT, Period3, 0, MAType, PriceType);

   if(handleMA1 == INVALID_HANDLE || handleMA2 == INVALID_HANDLE || handleMA3 == INVALID_HANDLE)
   {
      Print("Erreur de création des MA");
      return INIT_FAILED;
   }

   // Créer les objets graphiques pour les MA
   ObjectCreate(0, "WMA1", OBJ_TREND, 0, 0, 0);
   ObjectCreate(0, "WMA2", OBJ_TREND, 0, 0, 0);
   ObjectCreate(0, "WMA3", OBJ_TREND, 0, 0, 0);

   ObjectSetInteger(0, "WMA1", OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, "WMA2", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, "WMA3", OBJPROP_COLOR, clrTomato);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Fonction de rejet                                                |
//+------------------------------------------------------------------+
bool isRejet(double fast0, double fast1, double slow0, double slow1, double seuil_pct)
{
   double diffNow  = fast0 - slow0;
   double diffPrev = fast1 - slow1;

   bool proche = MathAbs(diffNow) <= MathAbs(slow0 * seuil_pct / 100.0);
   bool changement_direction = (diffNow - diffPrev) > 0;

   return (proche && changement_direction);
}

//+------------------------------------------------------------------+
//| Tick principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   if(CopyBuffer(handleMA1, 0, 0, 2, bufferMA1) < 2) return;
   if(CopyBuffer(handleMA2, 0, 0, 2, bufferMA2) < 2) return;
   if(CopyBuffer(handleMA3, 0, 0, 2, bufferMA3) < 2) return;

   double ma1_0 = bufferMA1[0], ma1_1 = bufferMA1[1];
   double ma2_0 = bufferMA2[0], ma2_1 = bufferMA2[1];
   double ma3_0 = bufferMA3[0], ma3_1 = bufferMA3[1];

   bool rejet_1_2 = isRejet(ma1_0, ma1_1, ma2_0, ma2_1, seuil_proximite);
   bool rejet_1_3 = isRejet(ma1_0, ma1_1, ma3_0, ma3_1, seuil_proximite);
   bool rejetDouble = rejet_1_2 && rejet_1_3;

   // Ajout indicateur visuel
   string name = "rej_" + TimeToString(TimeCurrent(), TIME_SECONDS);

if(rejetDouble)
{
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), ma1_0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
}
else if(rejet_1_2)
{
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), ma1_0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
}
else if(rejet_1_3)
{
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), ma1_0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrGreen);
}

double prix = SymbolInfoDouble(_Symbol, SYMBOL_BID);

bool prixSousLesTrois = (prix < ma1_0 * (1 - marge_pct / 100.0)) &&
                        (prix < ma2_0 * (1 - marge_pct / 100.0)) &&
                        (prix < ma3_0 * (1 - marge_pct / 100.0));

bool prixAuDessusDesTrois = (prix > ma1_0 * (1 + marge_pct / 100.0)) &&
                            (prix > ma2_0 * (1 + marge_pct / 100.0)) &&
                            (prix > ma3_0 * (1 + marge_pct / 100.0));
                            


bool buyCondition = false;
bool sellCondition = false;

if(rejetDouble)
{
   if(prixSousLesTrois)
   {
      Print("🔻 SELL déclenché : rejet double + prix sous les 3 MA");
      // -> ici tu peux appeler tradeOpen(ORDER_TYPE_SELL, ...)
      sellCondition = true;
   }
   else if(prixAuDessusDesTrois)
   {
      Print("🔺 BUY déclenché : rejet double + prix au-dessus des 3 MA");
      // -> ici tu peux appeler tradeOpen(ORDER_TYPE_BUY, ...)
      buyCondition = true;
   }
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
      if(buyCondition) 
      {
         tradeOpen(ORDER_TYPE_BUY, stop_loss_pct, take_profit_pct);
       }
      if(sellCondition) 
      {
         tradeOpen(ORDER_TYPE_SELL, stop_loss_pct, take_profit_pct);
      }
   }

}

//+------------------------------------------------------------------+
//| Nettoyage                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleMA1 != INVALID_HANDLE) IndicatorRelease(handleMA1);
   if(handleMA2 != INVALID_HANDLE) IndicatorRelease(handleMA2);
   if(handleMA3 != INVALID_HANDLE) IndicatorRelease(handleMA3);
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