#property strict
#property indicator_chart_window

// Inputs
input int    range_window = 30;
input double touch_tolerance_pct = 0.2;
input double breakout_tolerance_pct = 0.3;
input double LotFixe = 0.1;
input double tp_multiplier = 1.0;

// Globales
double rangeHigh = 0.0, rangeLow = 0.0;
bool   rangeValide = false;
bool   breakoutDetecte = false;
double tp1_level = 0.0;
ulong  ticketPrincipal = 0;

//+------------------------------------------------------------------+
int OnInit() { return INIT_SUCCEEDED; }

//+------------------------------------------------------------------+
void OnTick()
{
   double prix = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Étape 1 : Détecter le range
   if(!rangeValide && DetectRange(rangeHigh, rangeLow))
   {
      rangeValide = true;
      breakoutDetecte = false;
      ObjectDelete(0, "rangeBox");
      DrawRangeBox(rangeHigh, rangeLow);
      Print("📦 Nouveau range détecté");
   }

   // Étape 2 : Breakout ?
   if(rangeValide && !breakoutDetecte)
   {
      if(PrixBreakHaut(prix, rangeHigh))
      {
         Print("🚀 Breakout HAUT détecté → BUY");
         ticketPrincipal = OuvrirBreakoutTrade(ORDER_TYPE_BUY);
         breakoutDetecte = true;
         tp1_level = rangeHigh + (rangeHigh - rangeLow) * 0.5;
      }
      else if(PrixBreakBas(prix, rangeLow))
      {
         Print("🔻 Breakout BAS détecté → SELL");
         ticketPrincipal = OuvrirBreakoutTrade(ORDER_TYPE_SELL);
         breakoutDetecte = true;
         tp1_level = rangeLow - (rangeHigh - rangeLow) * 0.5;
      }
   }

   // Étape 3 : Gestion TP partiel
   if(PositionSelectByTicket(ticketPrincipal))
   {
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double price = SymbolInfoDouble(_Symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);

      double fullTP = (rangeHigh - rangeLow) * tp_multiplier;
      double tpFinal = type == POSITION_TYPE_BUY ? entry + fullTP : entry - fullTP;

      bool tp1Touché = (type == POSITION_TYPE_BUY) ? (price >= tp1_level) : (price <= tp1_level);
      bool tpFinalTouché = (type == POSITION_TYPE_BUY) ? (price >= tpFinal) : (price <= tpFinal);

      static bool tp1DéjàPris = false;

      if(tp1Touché && !tp1DéjàPris)
      {
         double demiLot = NormalizeDouble(volume / 2.0, 2);
         FermerPartiel(ticketPrincipal, demiLot);
         Print("🟡 TP1 atteint - 50% clôturé");
         tp1DéjàPris = true;
      }

      if(tpFinalTouché)
      {
         FermerPosition(ticketPrincipal);
         Print("✅ TP final atteint - position clôturée");
         ResetBot();
      }

      if(tp1DéjàPris && !tpFinalTouché)
      {
         // Si on redescend/revient à TP1
         bool retourSurTP1 = (type == POSITION_TYPE_BUY && price <= tp1_level) ||
                             (type == POSITION_TYPE_SELL && price >= tp1_level);
         if(retourSurTP1)
         {
            FermerPosition(ticketPrincipal);
            Print("🔁 Retour sur TP1 → clôture de la 2e moitié");
            ResetBot();
         }
      }
   }
}

//+------------------------------------------------------------------+
bool DetectRange(double &high, double &low)
{
   int touchesHaut = 0;
   int touchesBas = 0;

   high = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, range_window, 1));
   low  = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, range_window, 1));

   double tolHigh = high * touch_tolerance_pct / 100.0;
   double tolLow  = low * touch_tolerance_pct / 100.0;

   for(int i = 1; i <= range_window; i++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);
      if(MathAbs(h - high) <= tolHigh) touchesHaut++;
      if(MathAbs(l - low) <= tolLow) touchesBas++;
   }

   return (touchesHaut >= 2 && touchesBas >= 2);
}

//+------------------------------------------------------------------+
bool PrixBreakHaut(double prix, double high)
{
   return prix > high * (1 + breakout_tolerance_pct / 100.0);
}

bool PrixBreakBas(double prix, double low)
{
   return prix < low * (1 - breakout_tolerance_pct / 100.0);
}

//+------------------------------------------------------------------+
ulong OuvrirBreakoutTrade(ENUM_ORDER_TYPE type)
{
   double entry = SymbolInfoDouble(_Symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? rangeLow : rangeHigh;
   double tp = (type == ORDER_TYPE_BUY) ? entry + (rangeHigh - rangeLow) * tp_multiplier
                                        : entry - (rangeHigh - rangeLow) * tp_multiplier;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.type   = type;
   request.volume = LotFixe;
   request.price  = entry;
   request.sl     = NormalizeDouble(sl, _Digits);
   request.tp     = NormalizeDouble(tp, _Digits);
   request.deviation = 10;

   if(OrderSend(request, result))
      return result.order;
   else
      Print("Erreur envoi ordre breakout : ", result.comment);

   return 0;
}

//+------------------------------------------------------------------+
void FermerPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;

   double volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double price = SymbolInfoDouble(_Symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol   = _Symbol;
   request.volume   = volume;
   request.price    = price;
   request.type     = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.deviation = 10;

   OrderSend(request, result);
}

void FermerPartiel(ulong ticket, double volume)
{
   if(!PositionSelectByTicket(ticket)) return;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double price = SymbolInfoDouble(_Symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol   = _Symbol;
   request.volume   = volume;
   request.price    = price;
   request.type     = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.deviation = 10;

   OrderSend(request, result);
}

//+------------------------------------------------------------------+
void DrawRangeBox(double high, double low)
{
   datetime timeStart = iTime(_Symbol, PERIOD_CURRENT, range_window);
   datetime timeEnd   = TimeCurrent();

   ObjectCreate(0, "rangeBox", OBJ_RECTANGLE, 0, timeStart, high, timeEnd, low);
   ObjectSetInteger(0, "rangeBox", OBJPROP_COLOR, clrTeal);
   ObjectSetInteger(0, "rangeBox", OBJPROP_STYLE, STYLE_DOT);
}

//+------------------------------------------------------------------+
void ResetBot()
{
   rangeValide = false;
   breakoutDetecte = false;
   ticketPrincipal = 0;
   ObjectDelete(0, "rangeBox");
}
