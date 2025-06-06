#property strict
#property indicator_chart_window

// Inputs
input int    range_window = 30;
input double touch_tolerance_pct = 0.2;
input double breakout_tolerance_pct = 0.3; // Multiplicateur de l'ATR pour le breakout
input double stop_loss_pct = 0.5;
input double marge_pct = 0.1;
input double LotFixe = 0.1;
input ulong  MagicNumber = 385764; // ✅ Ajout du Magic Number

input bool UseTrend = true;
input int    FastMAPeriod = 50;                   // EMA courte
input int    SlowMAPeriod = 200;                  // EMA longue

enum TrendMethod { Majority=0, Weighted=1, Hierarchy=2 };
input TrendMethod Method = Majority;              // méthode de calcul


// Variables globales
double rangeHigh = 0.0, rangeLow = 0.0;
bool rangeValide = false;

int trendHandle;



//+------------------------------------------------------------------+
int OnInit()
{
   if (UseTrend){
   // charger l’indicateur compilé (avec ses inputs s’ils diffèrent des defaults)
   trendHandle = iCustom(_Symbol, PERIOD_CURRENT,
                         "TrendFinder.ex5",   // ou .mq5 si c’est un EA local
                         FastMAPeriod, SlowMAPeriod, Method);
   if(trendHandle==INVALID_HANDLE)
     { 
         Print("❌ Impossible de charger TrendColorLabel"); 
         return INIT_FAILED; }
     }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!rangeValide)
   {
      if(DetectRange(rangeHigh, rangeLow))
      {
         rangeValide = true;
         //Print("📦 Nouveau range détecté : ", DoubleToString(rangeLow, _Digits), " - ", DoubleToString(rangeHigh, _Digits));
         DrawRangeBox(rangeHigh, rangeLow);
      }
   }
   else
   {
      if(PrixEnBreakout(rangeHigh, rangeLow))
      {
         //Print("❌ Breakout confirmé. Range reset.");
         rangeValide = false;
         ObjectDelete(0, "rangeBox");
         return;
      }
      
      int avgTrend = 0;
      
      if (UseTrend){
            //--- récupérer la dernière valeur du buffer 0
      double buf[1];
      int copied = CopyBuffer(trendHandle, 0, 0, 1, buf);
      if(copied!=1)
      {
         Print("⚠️ Erreur CopyBuffer trend: ",copied);
         return;
      }
      avgTrend = (int)buf[0];  // +1 = tendance haussière, -1 = baissière
      }

      double prix = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      bool canBuy  = prix <= rangeLow * (1 + marge_pct / 100.0);
      bool canSell = prix >= rangeHigh * (1 - marge_pct / 100.0);

      if(!PositionExistsForMagic(_Symbol, MagicNumber)) // ✅ Vérifie position active avec ce Magic
      {
         if(canBuy )
         {
         
            if (UseTrend && avgTrend<0)
               return;
         
            //Print("🟢 BUY au bas du range");
            tradeOpen(ORDER_TYPE_BUY);
         }
         else if(canSell)
         {
         
            if (UseTrend && avgTrend>0)
               return;
         
            //Print("🔴 SELL au haut du range");
            tradeOpen(ORDER_TYPE_SELL);
         }
      }
   }
}

//+------------------------------------------------------------------+
// Détection robuste du range
bool DetectRange(double &high, double &low)
{
   int touchesHaut = 0;
   int touchesBas = 0;

   int indexHigh = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, range_window, 1);
   int indexLow  = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, range_window, 1);

   high = iHigh(_Symbol, PERIOD_CURRENT, indexHigh);
   low  = iLow(_Symbol, PERIOD_CURRENT, indexLow);

   if ((high - low) < (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 20))
   {
      //Print("❌ Range trop étroit");
      return false;
   }

   double toleranceHigh = high * touch_tolerance_pct / 100.0;
   double toleranceLow  = low * touch_tolerance_pct / 100.0;

   for(int i = 1; i <= range_window; i++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);

      if(MathAbs(h - high) <= toleranceHigh)
         touchesHaut++;
      if(MathAbs(l - low) <= toleranceLow)
         touchesBas++;
   }

   int totalTouches = touchesHaut + touchesBas;
   //PrintFormat("📊 Touches haut: %d | Touches bas: %d | Total: %d", touchesHaut, touchesBas, totalTouches);

   return (touchesHaut >= 3 && touchesBas >= 3);
}

//+------------------------------------------------------------------+
// Breakout basé sur clôture + ATR + confirmation
bool PrixEnBreakout(double high, double low)
{
   static int breakoutCounter = 0;

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   double atr = GetATR(_Symbol, PERIOD_CURRENT, 14);
   double buffer = atr * breakout_tolerance_pct;

   bool breakoutHaut = close > (high + buffer);
   bool breakoutBas  = close < (low - buffer);

   if (breakoutHaut || breakoutBas)
   {
      breakoutCounter++;
      //Print("⚠️ Tentative cassure ", breakoutCounter, " : close=", DoubleToString(close, _Digits));
      
      if (breakoutCounter >= 2)
      {
         breakoutCounter = 0;
         return true;
      }
   }
   else
   {
      breakoutCounter = 0;
   }

   return false;
}

//+------------------------------------------------------------------+
// Ouvre une position avec SL/TP adaptés et MagicNumber
void tradeOpen(ENUM_ORDER_TYPE type)
{
   double price = SymbolInfoDouble(_Symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   double sl, tp;

   if(type == ORDER_TYPE_BUY)
   {
      sl = price - price * stop_loss_pct / 100.0;
      tp = rangeHigh;
   }
   else
   {
      sl = price + price * stop_loss_pct / 100.0;
      tp = rangeLow;
   }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.type     = type;
   request.volume   = LotFixe;
   request.price    = price;
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= 10;
   request.magic    = MagicNumber; // ✅ Affecte le Magic Number

   if(!OrderSend(request,result))
      Print("❌ Erreur envoi ordre : ", result.comment);
   else
      Print("✅ Trade ouvert avec Magic ", MagicNumber);
}

//+------------------------------------------------------------------+
// Get ATR avec CopyBuffer
double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period)
{
   int handle = iATR(symbol, timeframe, period);
   if(handle == INVALID_HANDLE)
   {
      Print("❌ Erreur création handle ATR");
      return 0.0;
   }

   double atrValue[];
   if(CopyBuffer(handle, 0, 0, 1, atrValue) <= 0)
   {
      Print("❌ Erreur CopyBuffer ATR");
      return 0.0;
   }

   return atrValue[0];
}

//+------------------------------------------------------------------+
// Vérifie si une position existe avec le Magic Number
bool PositionExistsForMagic(string symbol, ulong magic)
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) >= 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == (long)magic &&
            PositionGetString(POSITION_SYMBOL) == symbol)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
// Dessin du rectangle de range
void DrawRangeBox(double high, double low)
{
   datetime timeStart = iTime(_Symbol, PERIOD_CURRENT, range_window);
   datetime timeEnd   = TimeCurrent();

   ObjectCreate(0, "rangeBox", OBJ_RECTANGLE, 0, timeStart, high, timeEnd, low);
   ObjectSetInteger(0, "rangeBox", OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, "rangeBox", OBJPROP_STYLE, STYLE_DASH);
}


void OnDeinit(const int reason)
{
   if(trendHandle!=INVALID_HANDLE)
      IndicatorRelease(trendHandle);
}
