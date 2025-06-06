//+------------------------------------------------------------------+
//|                                         SandR_Visualiser.mq5     |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

#include <Trade\Trade.mqh>
CTrade trade;


// Paramètres réglables
input int LeftBars  = 15;
input int RightBars = 15;
input int LineLength = 20; // Combien de bougies la ligne dure

int obj_counter = 0;

//+------------------------------------------------------------------+
//| Détection Pivot Haut                                             |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &high[], int shift)
{
    double val = high[shift];
    for(int i=1; i<=LeftBars; i++) if(high[shift+i] >= val) return false;
    for(int i=1; i<=RightBars; i++) if(high[shift-i] >= val) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Détection Pivot Bas                                              |
//+------------------------------------------------------------------+
bool IsPivotLow(const double &low[], int shift)
{
    double val = low[shift];
    for(int i=1; i<=LeftBars; i++) if(low[shift+i] <= val) return false;
    for(int i=1; i<=RightBars; i++) if(low[shift-i] <= val) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Dessiner un niveau                                               |
//+------------------------------------------------------------------+
void CreatePivotLine(datetime start_time, datetime end_time, double price, color line_color)
{
    string name = "Line_" + IntegerToString(obj_counter++);
    
    if(ObjectCreate(0, name, OBJ_TREND, 0, start_time, price, end_time, price))
    {
        ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); // Ne pas étendre à l'infini
    }
}

//+------------------------------------------------------------------+
//| Fonction principale                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Forcer un trade pour activer le visuel
    if(OrdersTotal() == 0)
    {
        trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, 0.01, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0);
    }

    // Charger données
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    CopyRates(_Symbol, PERIOD_CURRENT, 0, LeftBars + RightBars + 100, rates);

    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    CopyHigh(_Symbol, PERIOD_CURRENT, 0, LeftBars + RightBars + 100, high);
    CopyLow(_Symbol, PERIOD_CURRENT, 0, LeftBars + RightBars + 100, low);

    // Détecter et tracer
    int limit = ArraySize(rates) - RightBars - 1;

    for(int i = limit; i >= LeftBars; i--)
    {
       if (i + LineLength < ArraySize(rates))
{
    datetime start_time = rates[i].time;
    datetime end_time = rates[i + LineLength].time;

    if(IsPivotHigh(high, i))
    {
        CreatePivotLine(start_time, end_time, high[i], clrRed);
    }

    if(IsPivotLow(low, i))
    {
        CreatePivotLine(start_time, end_time, low[i], clrBlue);
    }
}
    }
}
