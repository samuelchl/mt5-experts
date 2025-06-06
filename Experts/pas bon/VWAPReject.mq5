#property strict
#property indicator_chart_window

input double proximity_pct = 0.1;     // Tolérance en % pour considérer un retour sur VWAP
input double risk_per_trade = 1.0;    // Risque en % du capital (non utilisé ici)
input double rr_ratio = 2.0;          // Ratio TP/SL
input double min_rejection_size = 10; // Taille min. du rejet en points
input double lotFixe = 0.1;

datetime lastTradeDate = 0;

//+------------------------------------------------------------------+
int OnInit() { return INIT_SUCCEEDED; }

//+------------------------------------------------------------------+
void OnTick()
{
   // Ne trader qu'une fois par jour
   MqlDateTime nowStruct;
   TimeToStruct(TimeCurrent(), nowStruct);

   MqlDateTime lastStruct;
   TimeToStruct(lastTradeDate, lastStruct);

   if(nowStruct.day != lastStruct.day) // nouveau jour ?
   {
      if(NewCandle())
      {
         int last = 1;
         double vwap = CalculateVWAP();
         double open = iOpen(_Symbol, PERIOD_CURRENT, last);
         double close = iClose(_Symbol, PERIOD_CURRENT, last);
         double high = iHigh(_Symbol, PERIOD_CURRENT, last);
         double low  = iLow(_Symbol, PERIOD_CURRENT, last);

         double rejectionSize = (high - low) / _Point;
         double prix = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         if(rejectionSize < min_rejection_size) return;

         double tol = vwap * proximity_pct / 100.0;

         if(MathAbs(open - vwap) < tol || MathAbs(close - vwap) < tol)
         {
            // Rejet HAUT → SELL
            if(open > close && high > vwap && close < vwap)
            {
               double sl = high + _Point * 5;
               double tp = close - (sl - close) * rr_ratio;
               if(OpenTrade(ORDER_TYPE_SELL, sl, tp))
                  lastTradeDate = TimeCurrent();
            }
            // Rejet BAS → BUY
            else if(close > open && low < vwap && close > vwap)
            {
               double sl = low - _Point * 5;
               double tp = close + (close - sl) * rr_ratio;
               if(OpenTrade(ORDER_TYPE_BUY, sl, tp))
                  lastTradeDate = TimeCurrent();
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
double CalculateVWAP()
{
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   double sumPV = 0.0, sumVol = 0.0;

   int bars = iBars(_Symbol, PERIOD_M1);
   for(int i = 0; i < bars; i++)
   {
      datetime t = iTime(_Symbol, PERIOD_M1, i);
      if(t < dayStart) break;

      double high = iHigh(_Symbol, PERIOD_M1, i);
      double low  = iLow(_Symbol, PERIOD_M1, i);
      double close= iClose(_Symbol, PERIOD_M1, i);
      double vol  = (double)iVolume(_Symbol, PERIOD_M1, i); // ✔️ conversion ici

      double typical = (high + low + close) / 3.0;
      sumPV  += typical * vol;
      sumVol += vol;
   }

   if(sumVol == 0) return iClose(_Symbol, PERIOD_M1, 0);
   return sumPV / sumVol;
}

//+------------------------------------------------------------------+
bool NewCandle()
{
   static datetime lastTime = 0;
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t != lastTime)
   {
      lastTime = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type, double sl, double tp)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.type   = type;
   request.volume = lotFixe;
   request.price  = NormalizeDouble(price, _Digits);
   request.sl     = NormalizeDouble(sl, _Digits);
   request.tp     = NormalizeDouble(tp, _Digits);
   request.deviation = 10;

   if(!OrderSend(request, result))
   {
      Print("Erreur envoi ordre : ", result.comment);
      return false;
   }

   Print("✅ Trade ouvert ", EnumToString(type), " | Prix: ", price, " SL: ", sl, " TP: ", tp);
   return true;
}
