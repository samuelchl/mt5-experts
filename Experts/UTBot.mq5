#property strict
#property indicator_chart_window

input int    Sensibilite     = 1;       // a = Sensitivity
input int    ATR_Period      = 10;      // c = ATR Period
input bool   UseHeikinAshi   = false;   // h = Use Heikin Ashi
input double LotFixe         = 0.1;     
input double RiskReward      = 2.0;     // RR Ratio

datetime lastBarTime = 0;
double trailingStop = 0;
double src[], ema1[];

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (currentBarTime == lastBarTime)
      return;

   lastBarTime = currentBarTime;

   
   double stopNow;
   double atr = GetATR(ATR_Period);

   if (UseHeikinAshi)
   {
      ArraySetAsSeries(src, true);
      CalcHeikinAshiClose(src);
   }
   else
   {
      ArrayResize(src, 3);
      for (int i = 0; i < 3; i++)
         src[i] = iClose(_Symbol, PERIOD_CURRENT, i);
   }

   double nLoss = Sensibilite * atr;

   double prevStop = trailingStop;

   if (src[0] > prevStop && src[1] > prevStop)
      stopNow = MathMax(prevStop, src[0] - nLoss);
   else if (src[0] < prevStop && src[1] < prevStop)
      stopNow = MathMin(prevStop, src[0] + nLoss);
   else
      stopNow = (src[0] > prevStop) ? src[0] - nLoss : src[0] + nLoss;

   trailingStop = stopNow;

   // EMA(1) sur src[]
   CalculateEMA1(src, ema1);

   bool buySignal = (src[0] > trailingStop) && (ema1[1] < trailingStop && ema1[0] > trailingStop);
   bool sellSignal = (src[0] < trailingStop) && (ema1[1] > trailingStop && ema1[0] < trailingStop);

   if (!PositionSelect(_Symbol))
   {
      if (buySignal)
         OpenTrade(ORDER_TYPE_BUY, stopNow);
      else if (sellSignal)
         OpenTrade(ORDER_TYPE_SELL, stopNow);
   }
}

//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double sl)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp = (type == ORDER_TYPE_BUY) ? price + (price - sl) * RiskReward
                                        : price - (sl - price) * RiskReward;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.type     = type;
   request.volume   = LotFixe;
   request.price    = NormalizeDouble(price, _Digits);
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= 10;

   if (!OrderSend(request, result))
      Print("Erreur trade ", result.comment);
   else
      Print("✅ ", EnumToString(type), " @", price, " SL=", sl, " TP=", tp);
}

//+------------------------------------------------------------------+
// ATR via handle + CopyBuffer
double GetATR(int period)
{
   int handle = iATR(_Symbol, PERIOD_CURRENT, period);
   if (handle == INVALID_HANDLE) return 0;

   double atrBuf[1];
   if (CopyBuffer(handle, 0, 0, 1, atrBuf) <= 0)
      return 0;

   IndicatorRelease(handle);
   return atrBuf[0];
}

//+------------------------------------------------------------------+
// EMA(1) sur buffer
//+------------------------------------------------------------------+
void CalculateEMA1(double &source[], double &output[])
{
   ArrayResize(output, 3);
   ArraySetAsSeries(source, true);
   ArraySetAsSeries(output, true);

   double alpha = 2.0 / (1 + 1);  // EMA period = 1 → alpha = 1
   output[1] = source[1];
   output[0] = alpha * source[0] + (1 - alpha) * output[1];
}


//+------------------------------------------------------------------+
// Heikin Ashi CLOSE (uniquement)
void CalcHeikinAshiClose(double &dest[])
{
   ArrayResize(dest, 3);
   for (int i = 0; i < 3; i++)
   {
      double open = iOpen(_Symbol, PERIOD_CURRENT, i);
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low  = iLow(_Symbol, PERIOD_CURRENT, i);
      double close= iClose(_Symbol, PERIOD_CURRENT, i);

      dest[i] = (open + high + low + close) / 4.0;
   }
}
