#property indicator_separate_window
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_label1  "Z-Score Median"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

input int      InpWindow   = 30;
input double   InpK        = 2.5;
input double   InpEpsilon  = 1e-8;

double zBuffer[];
double medianPrice[];
int handleMedian;

int OnInit()
{
   SetIndexBuffer(0, zBuffer, INDICATOR_DATA);
   ArraySetAsSeries(zBuffer, false);

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpWindow + 1);
   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   IndicatorSetString(INDICATOR_SHORTNAME, "Z-Score(" + IntegerToString(InpWindow) + ")");

   // On lit PRICE_MEDIAN avec iMA uniquement pour les prix
   handleMedian = iMA(_Symbol, PERIOD_CURRENT, 1, 0, MODE_SMA, PRICE_MEDIAN);
   if(handleMedian == INVALID_HANDLE)
   {
      Print("⛔ Erreur création handle iMA median");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(handleMedian != INVALID_HANDLE)
      IndicatorRelease(handleMedian);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < InpWindow + 2)
      return 0;

   int start = (prev_calculated > InpWindow) ? prev_calculated - 1 : InpWindow;

   ArraySetAsSeries(medianPrice, false);
   if(CopyBuffer(handleMedian, 0, 0, rates_total, medianPrice) <= 0)
   {
      Print("⛔ Erreur lecture PRICE_MEDIAN");
      return 0;
   }

   for(int i = start; i < rates_total; i++)
   {
      if(i - InpWindow + 1 < 0) continue; // sécurité
   
      double sum = 0.0, sumSq = 0.0;
   
      for(int j = 0; j < InpWindow; j++)
      {
         int idx = i - j; // lecture logique : du présent vers le passé
         double p = medianPrice[idx];
         sum   += p;
         sumSq += p * p;
      }
   
      double mean = sum / InpWindow;
      double variance = sumSq / InpWindow - mean * mean;
      double std = MathSqrt(MathMax(variance, 0.0));
   
      double priceNow = medianPrice[i];
      zBuffer[i] = (std > 0.0) ? (priceNow - mean) / (std * InpK + InpEpsilon) : 0.0;
   }
   

   return rates_total;
}
