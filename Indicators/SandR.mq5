//+------------------------------------------------------------------+
//|                                          LuxAlgoStyleSandR.mq5    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

input int LeftBars  = 15; // Nombre de bougies à gauche
input int RightBars = 15; // Nombre de bougies à droite
input int LineLength = 20; // Combien de bougies la ligne doit durer

int obj_counter = 0;

//+------------------------------------------------------------------+
//| Vérifie si un pivot haut est détecté                             |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &high[], int shift)
{
    double val = high[shift];
    for(int i=1; i<=LeftBars; i++) if(high[shift+i] >= val) return false;
    for(int i=1; i<=RightBars; i++) if(high[shift-i] >= val) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Vérifie si un pivot bas est détecté                              |
//+------------------------------------------------------------------+
bool IsPivotLow(const double &low[], int shift)
{
    double val = low[shift];
    for(int i=1; i<=LeftBars; i++) if(low[shift+i] <= val) return false;
    for(int i=1; i<=RightBars; i++) if(low[shift-i] <= val) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Trace une ligne horizontale courte à partir du pivot             |
//+------------------------------------------------------------------+
void CreatePivotLine(datetime start_time, datetime end_time, double price, color line_color)
{
    string name = "Line_" + IntegerToString(obj_counter++);
    if(ObjectCreate(0, name, OBJ_TREND, 0, start_time, price, end_time, price))
    {
        ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); // PAS de rayon infini
    }
}

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Calcul principal                                                 |
//+------------------------------------------------------------------+
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
    int limit = rates_total - RightBars - 1;

    for(int i = limit; i >= LeftBars; i--)
    {
        // Nouvelle résistance
        if(IsPivotHigh(high, i))
        {
            datetime start_time = time[i];
            datetime end_time = time[i + LineLength];
            CreatePivotLine(start_time, end_time, high[i], clrRed);
        }

        // Nouveau support
        if(IsPivotLow(low, i))
        {
            datetime start_time = time[i];
            datetime end_time = time[i + LineLength];
            CreatePivotLine(start_time, end_time, low[i], clrBlue);
        }
    }

    return(rates_total);
}
