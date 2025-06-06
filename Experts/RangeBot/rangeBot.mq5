#property strict
#property indicator_chart_window

// Inputs
input int    range_window = 30;
input double touch_tolerance_pct = 0.2;
input double breakout_tolerance_pct = 0.3;
input double stop_loss_pct = 0.5;     // SL en %
input double marge_pct = 0.1;         // Tolérance de proximité pour entrer
input double LotFixe = 0.1;

// Variables globales
double rangeHigh = 0.0, rangeLow = 0.0;
bool rangeValide = false;

//+------------------------------------------------------------------+
int OnInit()
{
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   double prix = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Détection du range
   if(!rangeValide)
   {
      if(DetectRange(rangeHigh, rangeLow))
      {
         rangeValide = true;
         Print("📦 Range détecté : ", DoubleToString(rangeLow, _Digits), " - ", DoubleToString(rangeHigh, _Digits));
         DrawRangeBox(rangeHigh, rangeLow);
      }
   }
   else
   {
      // Vérifier si cassure du range
      if(PrixEnBreakout(prix, rangeHigh, rangeLow))
      {
         Print("❌ Breakout détecté. Reset du range.");
         rangeValide = false;
         ObjectDelete(0, "rangeBox");
         return;
      }

      bool canBuy  = prix <= rangeLow * (1 + marge_pct / 100.0);
      bool canSell = prix >= rangeHigh * (1 - marge_pct / 100.0);

      if(!PositionSelect(_Symbol))
      {
         if(canBuy)
         {
            Print("🟢 BUY bas du range");
            tradeOpen(ORDER_TYPE_BUY);
         }
         else if(canSell)
         {
            Print("🔴 SELL haut du range");
            tradeOpen(ORDER_TYPE_SELL);
         }
      }
   }
}

//+------------------------------------------------------------------+
// Détection du range basé sur 2 touches haut et bas
bool DetectRange(double &high, double &low)
{
   int touchesHaut = 0;
   int touchesBas = 0;

   high = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, range_window, 1));
   low  = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, range_window, 1));

   double toleranceHigh = high * touch_tolerance_pct / 100.0;
   double toleranceLow  = low * touch_tolerance_pct / 100.0;

   for(int i = 1; i <= range_window; i++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);

      if(MathAbs(h - high) <= toleranceHigh)
         touchesHaut++;
      if(MathAbs(l - low) <= toleranceLow)
         touchesBas++;
   }

   return (touchesHaut >= 2 && touchesBas >= 2);
}

//+------------------------------------------------------------------+
// Détecter breakout hors du range
bool PrixEnBreakout(double prix, double high, double low)
{
   double breakoutHigh = high * (1 + breakout_tolerance_pct / 100.0);
   double breakoutLow  = low * (1 - breakout_tolerance_pct / 100.0);
   return (prix > breakoutHigh || prix < breakoutLow);
}

//+------------------------------------------------------------------+
// Ouvrir un trade avec TP au bord opposé du range
void tradeOpen(ENUM_ORDER_TYPE type)
{
   double price = SymbolInfoDouble(_Symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   double sl, tp;

   if(type == ORDER_TYPE_BUY)
   {
      sl = price - price * stop_loss_pct / 100.0;
      tp = rangeHigh; // 🎯 TP haut du range
   }
   else
   {
      sl = price + price * stop_loss_pct / 100.0;
      tp = rangeLow;  // 🎯 TP bas du range
   }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.type     = type;
   request.volume   = LotFixe;
   request.price    = price;
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= 10;

   if(!OrderSend(request,result))
      Print("Erreur ordre : ", result.comment);
}

//+------------------------------------------------------------------+
// Dessiner visuellement le range sur le graphique
void DrawRangeBox(double high, double low)
{
   datetime timeStart = iTime(_Symbol, PERIOD_CURRENT, range_window);
   datetime timeEnd   = TimeCurrent();

   ObjectCreate(0, "rangeBox", OBJ_RECTANGLE, 0, timeStart, high, timeEnd, low);
   ObjectSetInteger(0, "rangeBox", OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, "rangeBox", OBJPROP_STYLE, STYLE_DASH);
}
