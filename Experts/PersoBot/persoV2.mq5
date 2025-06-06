//+------------------------------------------------------------------+
//|       Strategie_WMA_Tendance.mq5  Complet avec logique WMA200   |
//+------------------------------------------------------------------+
#property strict

input ENUM_TIMEFRAMES TF = PERIOD_M15;                // Recommandé : M15 ou M30

// Risque et position
input bool GestionDynamiqueLot = true;
input double RisqueParTradePct = 1.5;
input double LotFixe = 0.1;

// Stop Loss & TP dynamiques (basés sur ATR)
input bool utiliser_sl_atr = true;
input double sl_atr_multiplier = 2.0;

bool utiliser_tp_auto = true;
input double ratio_risque_gain = 3.0;

// Trailing stop (classique ou ATR)
input bool utiliser_trailing_stop = true;
input double trailing_stop_pips = 30;
input bool utiliser_trailing_atr = true;
input double trailing_atr_multiplier = 2.0;

// Moyennes mobiles
input double seuil_rejet_pct = 0.2;

// TP partiels
input bool utiliser_prise_profit_partielle = true;
input int nb_tp_partiels = 3;

// Limitation quotidienne
input bool limiter_perte_journaliere = true;
input double perte_max_jour_eur = 1000.0;

// Volatilité minimale requise
input int atr_period = 14;
input double atr_min_pips = 10.0; //  Volatilité minimale 




int handle_ATR;
double ATR_Buffer[];



int handle_WMA8, handle_WMA38, handle_WMA200;
double WMA8[], WMA38[], WMA200[];

int tp_partiel_count = 0;

int OnInit()
{
      handle_ATR = iATR(_Symbol, TF, atr_period);
      if(handle_ATR == INVALID_HANDLE)
      {
          Print("Erreur lors de la création de l'ATR");
          return(INIT_FAILED);
      }

    handle_WMA8 = iMA(_Symbol, TF, 8, 0, MODE_LWMA, PRICE_CLOSE);
    handle_WMA38 = iMA(_Symbol, TF, 38, 0, MODE_LWMA, PRICE_CLOSE);
    handle_WMA200 = iMA(_Symbol, TF, 200, 0, MODE_LWMA, PRICE_CLOSE);

    if(handle_WMA8 == INVALID_HANDLE || handle_WMA38 == INVALID_HANDLE || handle_WMA200 == INVALID_HANDLE)
    {
        Print("Erreur handle MA");
        return(INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

void OnTick()
{
    static datetime lastTime = 0;
    datetime currentTime = iTime(_Symbol, TF, 0);
    if(currentTime == lastTime) return;
    lastTime = currentTime;

    // ⛔ Vérifier perte journalière
    if(limiter_perte_journaliere)
    {
        datetime debut_journee = TimeCurrent() - (TimeCurrent() % 86400);
        double profit_journee = CalculerProfitDepuis(debut_journee);
        if(profit_journee <= -perte_max_jour_eur)
        {
            Print("⛔ Perte journalière dépassée, pause trading");
            return;
        }
    }

    // ✅ Mise à jour ATR (volatilité)
    if(CopyBuffer(handle_ATR, 0, 0, 1, ATR_Buffer) <= 0)
    {
        Print("Erreur lecture ATR");
        return;
    }

    double atr_en_pips = ATR_Buffer[0] / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(atr_en_pips < atr_min_pips)
    {
        Print("📉 ATR trop bas (", atr_en_pips, " pips), trade ignoré.");
        return;
    }

    // ✅ MAJ des WMA
    CopyBuffer(handle_WMA8, 0, 0, 2, WMA8);
    CopyBuffer(handle_WMA38, 0, 0, 2, WMA38);
    CopyBuffer(handle_WMA200, 0, 0, 2, WMA200);

    // ✅ Détection tendance LT
    bool tendance_haussiere  = (WMA8[1] > WMA200[1]) && (WMA38[1] > WMA200[1]);
    bool tendance_baissiere  = (WMA8[1] < WMA200[1]) && (WMA38[1] < WMA200[1]);

    // ✅ Vérification de la pente de la WMA200 (nouveau filtre)
    double pente_WMA200 = WMA200[0] - WMA200[1];
    if(tendance_haussiere && pente_WMA200 < 0)
    {
        Print("📉 Pente WMA200 descendante, on évite un faux BUY");
        return;
    }
    if(tendance_baissiere && pente_WMA200 > 0)
    {
        Print("📈 Pente WMA200 montante, on évite un faux SELL");
        return;
    }

    // ✅ Rejets WMA
    bool rejet38  = IsRejet(WMA8, WMA38, seuil_rejet_pct);
    bool rejet200 = IsRejet(WMA8, WMA200, seuil_rejet_pct);

    // ✅ Signaux autorisés uniquement si tendance + double rejet
    bool signal_buy  = tendance_haussiere && rejet38 && rejet200;
    bool signal_sell = tendance_baissiere && rejet38 && rejet200;

    // ✅ Entrée si aucune position
    if(!PositionSelect(_Symbol))
    {
        if(signal_buy)  { tp_partiel_count = 0; tradeOpen(ORDER_TYPE_BUY); }
        if(signal_sell) { tp_partiel_count = 0; tradeOpen(ORDER_TYPE_SELL); }
    }

    // ✅ Suivi des positions
    if(utiliser_trailing_stop)           GererTrailingStop();
    if(utiliser_prise_profit_partielle)  GererPrisesProfitsPartielles();
}



void tradeOpen(ENUM_ORDER_TYPE type)
{
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double price = (type == ORDER_TYPE_BUY)
                   ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // SL basé sur ATR
    double sl_pips;
    if(utiliser_sl_atr)
    {
        if(CopyBuffer(handle_ATR, 0, 0, 1, ATR_Buffer) <= 0)
        {
            Print("Erreur lecture ATR pour SL");
            return;
        }
        sl_pips = ATR_Buffer[0] / point * sl_atr_multiplier;
    }
    else
    {
        Print("SL ATR désactivé mais aucun SL fourni  abandon.");
        return;
    }

    // TP basé sur SL × ratio
    double tp_pips;
    if(utiliser_tp_auto)
    {
        tp_pips = sl_pips * ratio_risque_gain;
    }
    else
    {
        Print("TP auto désactivé mais aucun TP fourni  abandon.");
        return;
    }

    double sl = sl_pips * point;
    double tp = tp_pips * point;

    double sl_price = (type == ORDER_TYPE_BUY) ? price - sl : price + sl;
    double tp_price = (type == ORDER_TYPE_BUY) ? price + tp : price - tp;

    double lot = (GestionDynamiqueLot) ? CalculerLotSize(sl_pips) : LotFixe;

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lot;
    request.type = type;
    request.price = price;
    request.sl = NormalizeDouble(sl_price, _Digits);
    request.tp = NormalizeDouble(tp_price, _Digits);
    request.deviation = 10;

    if(!OrderSend(request, result))
        Print("❌ Erreur d'ouverture : ", result.comment);
}



double CalculerLotSize(double slPips)
{
    double valeurTick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tailleTick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double montantRisque = balance * RisqueParTradePct / 100.0;
    double lot = montantRisque / (slPips * (valeurTick / tailleTick));

    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lot = MathFloor(lot / lotStep) * lotStep;

    return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lot)), 2);
}


void GererTrailingStop()
{
    if(!PositionSelect(_Symbol)) return;

    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    ulong ticket = PositionGetInteger(POSITION_TICKET);
    double prix_ouverture = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl_actuel = PositionGetDouble(POSITION_SL);

    double prix_actuel = (type == POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    double trailing_distance;

    if(utiliser_trailing_atr)
    {
        if(CopyBuffer(handle_ATR, 0, 0, 1, ATR_Buffer) <= 0)
        {
            Print("Erreur lecture ATR");
            return;
        }
        trailing_distance = ATR_Buffer[0] * trailing_atr_multiplier;
    }
    else
    {
        trailing_distance = trailing_stop_pips * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    }

    double nouveau_sl = (type == POSITION_TYPE_BUY)
                        ? prix_actuel - trailing_distance
                        : prix_actuel + trailing_distance;

    bool conditions_ok = false;

    if(type == POSITION_TYPE_BUY)
    {
        conditions_ok = (prix_actuel > prix_ouverture + trailing_distance) &&
                        (nouveau_sl > sl_actuel || sl_actuel == 0);
    }
    else
    {
        conditions_ok = (prix_actuel < prix_ouverture - trailing_distance) &&
                        (nouveau_sl < sl_actuel || sl_actuel == 0);
    }

    if(conditions_ok)
    {
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);

        request.action   = TRADE_ACTION_SLTP;
        request.symbol   = _Symbol;
        request.position = ticket;
        request.sl       = NormalizeDouble(nouveau_sl, _Digits);
        request.tp       = PositionGetDouble(POSITION_TP);

        if(!OrderSend(request, result))
            Print("Erreur trailing stop : ", result.comment);
    }
}



void GererPrisesProfitsPartielles()
{
    if(!PositionSelect(_Symbol) || nb_tp_partiels <= 0) return;

    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double prix_ouverture = PositionGetDouble(POSITION_PRICE_OPEN);
    double prix_tp = PositionGetDouble(POSITION_TP);
    double prix_actuel = (type == POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    double distance_totale = MathAbs(prix_tp - prix_ouverture);
    double seuil = distance_totale / nb_tp_partiels;

    double volume_total = PositionGetDouble(POSITION_VOLUME);
    double volume_step = NormalizeDouble(volume_total / nb_tp_partiels, 2);
    double volume_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    if(volume_step < volume_min) return;

    double progression = MathAbs(prix_actuel - prix_ouverture);

    if(tp_partiel_count < nb_tp_partiels && progression >= seuil * (tp_partiel_count + 1))
    {
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);

        request.action = TRADE_ACTION_DEAL;
        request.symbol = _Symbol;
        request.position = PositionGetInteger(POSITION_TICKET);
        request.volume = volume_step;
        request.price = prix_actuel;
        request.deviation = 10;
        request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

        if(OrderSend(request, result))
            tp_partiel_count++;
    }
}

double CalculerProfitDepuis(datetime depuis)
{
    double profit = 0.0;
    HistorySelect(depuis, TimeCurrent());
    for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
        profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
    }
    return profit;
}

// Fonction de détection de rejet (comme dans le Pine Script)
bool IsRejet(const double &fast[],const double &slow[], double seuil_pct)
{
    double seuil = slow[1] * seuil_pct / 100.0;
    bool proche = MathAbs(fast[1] - slow[1]) <= seuil;

    double ecart_actuel = fast[0] - slow[0];
    double ecart_prec = fast[1] - slow[1];
    bool changement_direction = (ecart_actuel - ecart_prec) > 0;

    return proche && changement_direction;
}
