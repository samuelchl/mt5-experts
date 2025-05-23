//+------------------------------------------------------------------+
//| Expert Advisor : ATR Pullback Strategy                           |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

enum TradeMode
{
   OnlyBuy = 0,
   OnlySell = 1,
   Both = 2
};

input TradeMode trade_mode = Both; // Mode de trading sélectionné

input double MinATR = 0.0005; // Seuil minimal de l'ATR pour filtrer les périodes de faible volatilité

input double coeffsl = 1.5;           
input double LotSize = 0.1;           // Taille du lot
input double RiskRewardRatio = 2.0;   // Ratio Risque/Rendement
input int ATR_Period = 14;            // Période de l'ATR
input int MA_Period = 50;             // Période de la Moyenne Mobile
input ENUM_MA_METHOD MA_Method = MODE_SMA; // Méthode de la Moyenne Mobile
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; // Période de temps

CTrade trade;

int atr_handle;
int ma_handle;

//+------------------------------------------------------------------+
//| Fonction d'initialisation de l'EA                                |
//+------------------------------------------------------------------+
int OnInit()
{
    // Création des handles pour les indicateurs
    atr_handle = iATR(_Symbol, Timeframe, ATR_Period);
    if (atr_handle == INVALID_HANDLE)
    {
        Print("Erreur lors de la création du handle ATR : ", GetLastError());
        return(INIT_FAILED);
    }

    ma_handle = iMA(_Symbol, Timeframe, MA_Period, 0, MA_Method, PRICE_CLOSE);
    if (ma_handle == INVALID_HANDLE)
    {
        Print("Erreur lors de la création du handle MA : ", GetLastError());
        return(INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Fonction appelée à chaque tick                                   |
//+------------------------------------------------------------------+
void OnTick()
{
    //Print("OnTick");
    // Vérifier s'il y a déjà une position ouverte
    if (PositionsTotal() > 0)
        return;

    // Récupérer les valeurs actuelles de l'ATR et de la MA
    double atr_value[], ma_value[];
    if (CopyBuffer(atr_handle, 0, 0, 1, atr_value) <= 0 ||
        CopyBuffer(ma_handle, 0, 0, 1, ma_value) <= 0)
    {
        Print("Erreur lors de la copie des données des indicateurs : ", GetLastError());
        return;
    }

    double current_atr = atr_value[0];
    double current_ma = ma_value[0];
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Filtrer les périodes de faible volatilité
    if (current_atr < MinATR)
    {
        Print("Volatilité trop faible (ATR = ", current_atr, "), aucune position ouverte.");
        return;
    }

    // Conditions d'achat
    if ((trade_mode == OnlyBuy || trade_mode == Both) &&
        current_price > current_ma &&
        current_price < current_ma + current_atr)
    {
        double sl = current_price - current_atr * coeffsl;
        double tp = current_price + current_atr * RiskRewardRatio;
        trade.Buy(LotSize, _Symbol, current_price, sl, tp, "Achat ATR Pullback");
    }

    // Conditions de vente
    else if ((trade_mode == OnlySell || trade_mode == Both) &&
             current_price < current_ma &&
             current_price > current_ma - current_atr)
    {
        double sl = current_price + current_atr * coeffsl;
        double tp = current_price - current_atr * RiskRewardRatio;
        trade.Sell(LotSize, _Symbol, current_price, sl, tp, "Vente ATR Pullback");
    }
}
