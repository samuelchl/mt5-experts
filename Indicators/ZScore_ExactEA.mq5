#property indicator_separate_window
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_label1  "Z-Score EA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

// === Inputs identiques à ton EA ===
// === Inputs identiques à ton EA ===
input int      InpWindow       = 30;          // Fenêtre MA
input double   InpStdDevRatio  = 0.4;         // Ratio de fenêtre StdDev
input double   InpK            = 2.5;         // Multiplicateur d’écart‑type
input double   InpEpsilon      = 1e-8;        // Stabilité division
input ENUM_APPLIED_PRICE PriceType = PRICE_MEDIAN;
input ENUM_TIMEFRAMES TF = PERIOD_CURRENT;

double zBuffer[];

int handleMA, handleSTD;

int OnInit()
{
   SetIndexBuffer(0, zBuffer, INDICATOR_DATA);

   int stdDevPeriod = (int)MathMax(1, InpWindow * InpStdDevRatio);

   handleMA  = iMA(_Symbol, TF, InpWindow, 0, MODE_SMA, PriceType);
   handleSTD = iStdDev(_Symbol, TF, stdDevPeriod, 0, MODE_SMA, PriceType);

   if(handleMA == INVALID_HANDLE || handleSTD == INVALID_HANDLE)
   {
      Print("⛔ Erreur lors de la création des indicateurs internes.");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &ignored[])
{
   if(rates_total < InpWindow)
      return 0;

   double ma[], stddev[], high[], low[];
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(stddev, true);
   ArraySetAsSeries(zBuffer, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(CopyBuffer(handleMA, 0, 0, rates_total, ma) <= 0) return 0;
   if(CopyBuffer(handleSTD, 0, 0, rates_total, stddev) <= 0) return 0;
   if(CopyHigh(_Symbol, TF, 0, rates_total, high) <= 0) return 0;
   if(CopyLow(_Symbol, TF, 0, rates_total, low) <= 0) return 0;

   for(int i = 0; i < rates_total; i++)
   {
      double p = (high[i] + low[i]) / 2.0;
      double m = ma[i];
      double s = stddev[i];

      if(s > 0.0)
         zBuffer[i] = (p - m) / (s * InpK + InpEpsilon);
      else
         zBuffer[i] = 0.0;
   }

   // ➕ Affichage z-score temps réel (optionnel mais utile)
   if(rates_total > 1)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double livePrice = (bid + ask) / 2.0;

      double m = ma[1];
      double s = stddev[1];
      double zLive = (livePrice - m) / (s * InpK + InpEpsilon);

      Comment("Z-Score live = ", DoubleToString(zLive, 4));
     
   }

   return rates_total;
}
