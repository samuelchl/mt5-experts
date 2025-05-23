//+-----------------------------------------------------------------+
//| RSI Cross Strategy Only                                          |
//+------------------------------------------------------------------+
#property strict

input int rsiPeriodFast = 9;
input int rsiPeriodSlow = 14;
input double angleSeuil = 1.0; // Angle de retournement RSI

input double take_profit_pct = 3;  // TP en %
input double stop_loss_pct  = 0.5;  // SL en %

input bool   GestionDynamiqueLot = false;
input double RisqueParTradePct   = 1.0;
input double LotFixe             = 0.3;

// Déclaration des handles et tableaux pour les RSI
int handleRSI5, handleRSI14;
double rsi5[], rsi14[];

// --- Initialisation
int OnInit()
{
   // Créer le handle pour les RSI
   handleRSI5 = iRSI(_Symbol, PERIOD_CURRENT, 5, PRICE_CLOSE);
   handleRSI14 = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);

   if(handleRSI5 == INVALID_HANDLE || handleRSI14 == INVALID_HANDLE)
   {
      Print("Erreur lors de la création des RSI");
      return INIT_FAILED;
   }

   // --- Créer les objets pour afficher les RSI sur le graphique
   ObjectCreate(0, "RSI5_Line", OBJ_TRENDBYANGLE, 0, 0, 0);
   ObjectSetInteger(0, "RSI5_Line", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "RSI5_Line", OBJPROP_RAY_RIGHT, false);

   ObjectCreate(0, "RSI14_Line", OBJ_TRENDBYANGLE, 0, 0, 0);
   ObjectSetInteger(0, "RSI14_Line", OBJPROP_COLOR, clrBlue);
   ObjectSetInteger(0, "RSI14_Line", OBJPROP_RAY_RIGHT, false);

   // --- Afficher les RSI sur le graphique en ligne continue
   return INIT_SUCCEEDED;
}



void OnDeinit(const int reason)
{
   if(handleRSI5 != INVALID_HANDLE) IndicatorRelease(handleRSI5);
   if(handleRSI14 != INVALID_HANDLE) IndicatorRelease(handleRSI14);
   
   
   
}


void DrawSignal(string name, datetime time, double price, color col, string text)
{
   string arrowName = name + "_" + TimeToString(time, TIME_SECONDS);

   ObjectCreate(0, arrowName, OBJ_ARROW, 0, time, price);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, col);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 233); // flèche vers le haut/bas

   // Créer un label texte si tu veux (optionnel)
   string labelName = arrowName + "_label";
   ObjectCreate(0, labelName, OBJ_TEXT, 0, time, price + 20 * _Point);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, col);
   ObjectSetString(0, labelName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
}


void OnTick()
{
   // On récupère 6 valeurs pour analyse de range + croisement
   if(CopyBuffer(handleRSI5, 0, 0, 6, rsi5) < 6 || CopyBuffer(handleRSI14, 0, 0, 6, rsi14) < 6)
      return;

   double rsi5_curr = rsi5[1];    // dernière bougie clôturée
   double rsi5_prev = rsi5[2];
   double rsi14_curr = rsi14[1];
   double rsi14_prev = rsi14[2];

   // --- Affichage des lignes (optionnel)
   ObjectMove(0, "RSI5_Line", 0, TimeCurrent(), rsi5[0]);
   ObjectMove(0, "RSI14_Line", 0, TimeCurrent(), rsi14[0]);

   // --- FILTRE ANTI-CONSOLIDATION ---
   double minEcartRSI = 2.0; // écart minimum requis pour agir
   double rsiDistance = MathAbs(rsi5_curr - rsi14_curr);
   if(rsiDistance < minEcartRSI)
      return; // trop plat

   double rsi5_max = rsi5[1];
   double rsi5_min = rsi5[1];
   double rsi14_max = rsi14[1];
   double rsi14_min = rsi14[1];

   for(int i = 1; i <= 5; i++)
   {
      rsi5_max = MathMax(rsi5_max, rsi5[i]);
      rsi5_min = MathMin(rsi5_min, rsi5[i]);
      rsi14_max = MathMax(rsi14_max, rsi14[i]);
      rsi14_min = MathMin(rsi14_min, rsi14[i]);
   }

   double range5 = rsi5_max - rsi5_min;
   double range14 = rsi14_max - rsi14_min;

   if(range5 < 2.0 && range14 < 2.0)
      return; // consolidation détectée → ignorer

   // --- Croisement RSI
   bool crossUp = (rsi5_prev < rsi14_prev) && (rsi5_curr > rsi14_curr);
   bool crossDown = (rsi5_prev > rsi14_prev) && (rsi5_curr < rsi14_curr);

   // --- Retournement RSI5
   bool rsi5TurnedUp   = (rsi5_curr - rsi5_prev) > angleSeuil && (rsi5_prev - rsi5[2]) < 0;
   bool rsi5TurnedDown = (rsi5_curr - rsi5_prev) < -angleSeuil && (rsi5_prev - rsi5[2]) > 0;

   // --- LOGIQUE D’OUVERTURE
   if(!PositionSelect(_Symbol))
   {
      if(crossUp)
      {
         Print("🔺 BUY signal : croisement haussier RSI5");
         tradeOpen(ORDER_TYPE_BUY, stop_loss_pct, take_profit_pct);
         DrawSignal("BUY", TimeCurrent(), SymbolInfoDouble(_Symbol, SYMBOL_BID), clrLime, "BUY");
      }
      else if(crossDown)
      {
         Print("🔻 SELL signal : croisement baissier RSI5");
         tradeOpen(ORDER_TYPE_SELL, stop_loss_pct, take_profit_pct);
         DrawSignal("SELL", TimeCurrent(), SymbolInfoDouble(_Symbol, SYMBOL_BID), clrRed, "SELL");
      }
   }
   else // --- LOGIQUE DE FERMETURE
   {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY && rsi5TurnedDown)
      {
         Print("❌ Clôture BUY : retournement baissier RSI5");
         tradeClose(ticket);
         DrawSignal("EXIT_BUY", TimeCurrent(), SymbolInfoDouble(_Symbol, SYMBOL_BID), clrOrange, "EXIT");
      }
      else if(type == POSITION_TYPE_SELL && rsi5TurnedUp)
      {
         Print("❌ Clôture SELL : retournement haussier RSI5");
         tradeClose(ticket);
         DrawSignal("EXIT_SELL", TimeCurrent(), SymbolInfoDouble(_Symbol, SYMBOL_BID), clrOrange, "EXIT");
      }
   }
}




//+------------------------------------------------------------------+
//| Gestion de lot                                                   |
//+------------------------------------------------------------------+
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
//| Fonctions trade                                                  |
//+------------------------------------------------------------------+
void tradeOpen(ENUM_ORDER_TYPE type, double sl_pct, double tp_pct)
{
   double price = SymbolInfoDouble(_Symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   double sl = price - (type==ORDER_TYPE_BUY ? 1 : -1) * price * sl_pct / 100.0;
   double tp = price + (type==ORDER_TYPE_BUY ? 1 : -1) * price * tp_pct / 100.0;

   if(type == ORDER_TYPE_SELL && tp < 0) tp = 1.0;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.type     = type;
   double slPips = MathAbs(price - sl) / SymbolInfoDouble(_Symbol, SYMBOL_POINT) / 10.0;
   request.volume   = CalculerLotSize(slPips);
   request.price    = price;
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= 10;

   if(!OrderSend(request, result))
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

   if(!OrderSend(request, result))
      Print("Erreur fermeture ordre : ", result.comment);
}
