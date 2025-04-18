//+------------------------------------------------------------------+
//| Expert Advisor : ATR Pullback Strategy (version améliorée)      |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

enum TradeMode
{
   OnlyBuy = 0,
   OnlySell = 1,
   Both = 2
};

input TradeMode trade_mode = Both;

input double MinATR = 0.0005;          // ATR minimum pour éviter les ranges
input double coeffsl = 1.5;            // Coefficient multiplicateur pour le Stop Loss
input double LotSize = 0.1;            // Taille du lot
input double RiskRewardRatio = 2.0;    // Ratio Risque / Rendement
input int ATR_Period = 14;
input int MA_Period = 50;
input ENUM_MA_METHOD MA_Method = MODE_EMA; // EMA par défaut
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;

CTrade trade;

int atr_handle;
int ma_handle;

//+------------------------------------------------------------------+
int OnInit()
{
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
void OnTick()
{
    if (PositionsTotal() > 0)
        return;

    double atr_buffer[2], ma_buffer[2];
    if (CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) <= 0 ||
        CopyBuffer(ma_handle, 0, 0, 2, ma_buffer) <= 0)
    {
        Print("Erreur lors de la copie des buffers : ", GetLastError());
        return;
    }

    double current_atr = atr_buffer[0];
    if (current_atr < MinATR)
    {
        Print("ATR trop faible : ", current_atr);
        return;
    }

    double ma_now = ma_buffer[0];
    double ma_prev = ma_buffer[1];
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double distance = MathAbs(price - ma_now);

    // Pullback doit être modéré : entre 0.3x et 1.0x ATR
    if (distance < 0.3 * current_atr || distance > 1.0 * current_atr)
        return;

    bool ma_up = ma_now > ma_prev;
    bool ma_down = ma_now < ma_prev;

    // === BUY CONDITIONS ===
    if ((trade_mode == Both || trade_mode == OnlyBuy) &&
        price > ma_now &&
        ma_up)
    {
        double sl = price - coeffsl * current_atr;
        double tp = price + current_atr * RiskRewardRatio;
        trade.Buy(LotSize, _Symbol, price, sl, tp, "Buy ATR Pullback");
    }

    // === SELL CONDITIONS ===
    else if ((trade_mode == Both || trade_mode == OnlySell) &&
             price < ma_now &&
             ma_down)
    {
        double sl = price + coeffsl * current_atr;
        double tp = price - current_atr * RiskRewardRatio;
        trade.Sell(LotSize, _Symbol, price, sl, tp, "Sell ATR Pullback");
    }
}
