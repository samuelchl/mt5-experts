//+------------------------------------------------------------------+
//|                                                        range.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
// Structure pour contenir les données du range
struct RangeData
{
    double high;
    double low;
    double rangePips;
};

// Fonction pour scanner le range une seule fois
void GetRangeData(out RangeData &range, int candlesToCheck = 50)
{
    double highest = iHigh(_Symbol, _Period, 0);
    double lowest = iLow(_Symbol, _Period, 0);

    for (int i = 1; i < candlesToCheck; i++)
    {
        double high = iHigh(_Symbol, _Period, i);
        double low = iLow(_Symbol, _Period, i);

        if (high > highest) highest = high;
        if (low < lowest) lowest = low;
    }

    range.high = highest;
    range.low = lowest;
    range.rangePips = (highest - lowest) / _Point;
}
// Vérifie si le range est valide
bool IsRangeValid(RangeData range, double maxRangePips = 50)
{
    return (range.rangePips <= maxRangePips);
}

// Fonction principale appelée à chaque tick
void OnTick()
{
    // --- Paramètres ---
    int candlesToCheck = 50;
    double maxRangePips = 50;
    double buffer = 5 * _Point;  // marge de sécurité

    // --- Récupérer les données du range ---
    RangeData range = GetRangeData(candlesToCheck);

    // --- Vérifier si on est bien dans un range ---
    if (!IsRangeValid(range, maxRangePips))
        return;

    // --- Récupérer le prix actuel ---
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

//    // --- SELL en haut du range ---
//    if (price >= range.high - buffer && ConfirmSellConditions())
//    {
//        if (!PositionOpen("SELL"))
//            OpenSell(range.high, range.low);
//    }
//
//    // --- BUY en bas du range ---
//    if (price <= range.low + buffer && ConfirmBuyConditions())
//    {
//        if (!PositionOpen("BUY"))
//            OpenBuy(range.low, range.high);
//    }
//
//    // --- Gérer une cassure franche du range ---
//    if (BreakoutDetected(price, range))
//    {
//        CloseAllPositions();  // ou passer en mode breakout
//    }
}
