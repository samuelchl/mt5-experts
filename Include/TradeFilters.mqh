#ifndef TRADEFILTERS_MQH
#define TRADEFILTERS_MQH

// === Enumération des filtres disponibles ===
enum FilterMode
{
   FILTER_NONE = 0,
   FILTER_RSI_BUY,
   FILTER_RSI_SELL,
   FILTER_RSI_BOTH,
   FILTER_HIGH_BUY,
   FILTER_HIGH_SELL,
   FILTER_HIGH_BOTH,
   FILTER_RSI_HIGH_BUY,
   FILTER_RSI_HIGH_SELL,
   FILTER_RSI_HIGH_BOTH
};

// === Contexte pour stocker les handles RSI ===
struct TradeFilterContext
{
   FilterMode filterMode;
   int rsiHandle;
   string symbol;
   ENUM_TIMEFRAMES timeframe;
   int rsiPeriod;

   // Paramètres de filtre
   double rsiBuyLevel;
   double rsiSellLevel;
   int highLowLookback;
   double highLowBufferPct;
};


bool InitTradeFilters(TradeFilterContext &ctx,
                      string symbol,
                      ENUM_TIMEFRAMES tf,
                      int rsiPeriod,
                      double _rsiBuyLevel = 30.0,
                      double _rsiSellLevel = 70.0,
                      int lookback = 50,
                      double bufferPct = 1.0,
                      FilterMode mode = FILTER_NONE)
{
   ctx.symbol = symbol;
   ctx.timeframe = tf;
   ctx.rsiPeriod = rsiPeriod;
   ctx.rsiBuyLevel = _rsiBuyLevel;
   ctx.rsiSellLevel = _rsiSellLevel;
   ctx.highLowLookback = lookback;
   ctx.highLowBufferPct = bufferPct;

   bool useRSI =
      mode == FILTER_RSI_BUY ||
      mode == FILTER_RSI_SELL ||
      mode == FILTER_RSI_BOTH ||
      mode == FILTER_RSI_HIGH_BUY ||
      mode == FILTER_RSI_HIGH_SELL ||
      mode == FILTER_RSI_HIGH_BOTH;

   if (useRSI)
   {
      ctx.rsiHandle = iRSI(symbol, tf, rsiPeriod, PRICE_CLOSE);
      if (ctx.rsiHandle == INVALID_HANDLE)
      {
         Print("Erreur lors de la création du handle RSI");
         return false;
      }
   }
   else
   {
      ctx.rsiHandle = INVALID_HANDLE;
   }

   return true;
}




// === Vérifie si RSI croise au-dessus d’un seuil (achat) ===
bool rsiBuySignal(TradeFilterContext &ctx, double level)
{
   double rsi[3];
   if (CopyBuffer(ctx.rsiHandle, 0, 1, 2, rsi) < 2)
      return false;

   return (rsi[1] < level && rsi[0] > level);
}

// === Vérifie si RSI croise en dessous d’un seuil (vente) ===
bool rsiSellSignal(TradeFilterContext &ctx, double level)
{
   double rsi[3];
   if (CopyBuffer(ctx.rsiHandle, 0, 1, 2, rsi) < 2)
      return false;

   return (rsi[1] > level && rsi[0] < level);
}

// === Vérifie si le prix est trop proche du high récent (achat) ===
bool isTooHighToBuy(string symbol, ENUM_TIMEFRAMES tf, int lookback, double bufferPercent)
{
   int idx = iHighest(symbol, tf, MODE_HIGH, lookback, 1);
   double recentHigh = iHigh(symbol, tf, idx);
   double price = iClose(symbol, tf, 1);
   double buffer = recentHigh * (bufferPercent / 100.0);
   return (price >= recentHigh - buffer);
}

// === Vérifie si le prix est trop proche du low récent (vente) ===
bool isTooLowToSell(string symbol, ENUM_TIMEFRAMES tf, int lookback, double bufferPercent)
{
   int idx = iLowest(symbol, tf, MODE_LOW, lookback, 1);
   double recentLow = iLow(symbol, tf, idx);
   double price = iClose(symbol, tf, 1);
   double buffer = recentLow * (bufferPercent / 100.0);
   return (price <= recentLow + buffer);
}

// === Peut-on acheter selon les filtres ? ===
bool canOpenBuy(TradeFilterContext &ctx)
{
   FilterMode mode = ctx.filterMode;
   bool rsiOk = true;
   bool highOk = true;

   if (mode == FILTER_RSI_BUY || mode == FILTER_RSI_BOTH || mode == FILTER_RSI_HIGH_BUY || mode == FILTER_RSI_HIGH_BOTH)
      rsiOk = rsiBuySignal(ctx, ctx.rsiBuyLevel);

   if (mode == FILTER_HIGH_BUY || mode == FILTER_HIGH_BOTH || mode == FILTER_RSI_HIGH_BUY || mode == FILTER_RSI_HIGH_BOTH)
      highOk = !isTooHighToBuy(ctx.symbol, ctx.timeframe, ctx.highLowLookback, ctx.highLowBufferPct);

   return (rsiOk && highOk);
}


// === Peut-on vendre selon les filtres ? ===
bool canOpenSell(TradeFilterContext &ctx)
{
   FilterMode mode = ctx.filterMode;
   bool rsiOk = true;
   bool lowOk = true;

   if (mode == FILTER_RSI_SELL || mode == FILTER_RSI_BOTH || mode == FILTER_RSI_HIGH_SELL || mode == FILTER_RSI_HIGH_BOTH)
      rsiOk = rsiSellSignal(ctx, ctx.rsiSellLevel);

   if (mode == FILTER_HIGH_SELL || mode == FILTER_HIGH_BOTH || mode == FILTER_RSI_HIGH_SELL || mode == FILTER_RSI_HIGH_BOTH)
      lowOk = !isTooLowToSell(ctx.symbol, ctx.timeframe, ctx.highLowLookback, ctx.highLowBufferPct);

   return (rsiOk && lowOk);
}


#endif // TRADEFILTERS_MQH
