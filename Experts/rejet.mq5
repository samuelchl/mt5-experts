#property strict
#include <Trade\Trade.mqh>
CTrade trade;

// === INPUTS UTILISATEUR ===

// --- Détection du rejet MA ---
input int wmaFastPeriod       = 8;
input int wmaSlowPeriod       = 38;
input int wmaTrendPeriod      = 200;
input double seuilProximite   = 3.0;
input double seuilEcartement  = 6.0;

// --- Paramètres de trade ---
input double lotSize          = 0.1;
input double RiskRewardRatio  = 2.0;

// --- SL/TP dynamiques via ATR ---
input int atrPeriod           = 14;
input double atrSLMultiplier  = 2.0;
input double atrMinimum       = 0.5;       // 🔒 Pas de trade si ATR trop faible

// --- Règles comportementales ---
input int cooldownMinutes     = 30;        // ⏳ Délai min entre 2 trades
input double maxSpreadPoints  = 30;        // 🛑 Pas de trade si spread > seuil
input double minCandleBodyRatio = 0.3;     // 📏 Bougie de rejet doit avoir un vrai corps

// --- Type de moyenne mobile ---
input ENUM_MA_METHOD maMethod = MODE_LWMA;

input bool useCooldown         = true;
input bool useSpreadFilter     = true;
input bool useATRFilter        = true;
input bool useCandleFilter     = true;
input bool useTrendFilterBuy   = true;
input bool useTrendFilterSell  = true;

double proxMin = DBL_MAX;
double proxMax = DBL_MIN;
double ecartMin = DBL_MAX;
double ecartMax = DBL_MIN;

// === GLOBAL ===
string logFileName = "";
datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   InitLogFile();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Tick principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   if(PositionSelect(_Symbol)) return;

   // --- Cooldown
   if(useCooldown && TimeCurrent() - lastTradeTime < cooldownMinutes * 60)
   {
      Print("⏱️ Cooldown actif (", cooldownMinutes, "min)");
      return;
   }

   // --- Spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(useSpreadFilter && spread > maxSpreadPoints)
   {
      Print("📶 Spread trop élevé : ", spread, " > ", maxSpreadPoints);
      return;
   }

   // --- ATR
   int atrHandle = iATR(_Symbol, _Period, atrPeriod);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("❌ ATR handle invalide");
      return;
   }

   double atr[1];
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0)
   {
      Print("❌ Erreur lecture ATR");
      return;
   }

   double atrValue = atr[0];
   if(useATRFilter && atrValue < atrMinimum)
   {
      Print("📉 ATR trop faible : ", DoubleToString(atrValue, 2), " < ", atrMinimum);
      return;
   }

   // --- MA Tendance
   double ma38_now   = GetMAValue(wmaSlowPeriod, 0);
   double ma200_now  = GetMAValue(wmaTrendPeriod, 0);
   double ma200_prev = GetMAValue(wmaTrendPeriod, 1);

   // --- Bougie précédente
   double open[], close[], high[], low[];
   if(
      CopyOpen(_Symbol, _Period, 0, 2, open) <= 0 ||
      CopyClose(_Symbol, _Period, 0, 2, close) <= 0 ||
      CopyHigh(_Symbol, _Period, 0, 2, high) <= 0 ||
      CopyLow(_Symbol, _Period, 0, 2, low) <= 0
   )
   {
      Print("❌ Erreur récupération bougie");
      return;
   }

   double bodySize = MathAbs(open[1] - close[1]);
   double candleSize = high[1] - low[1];
   if(useCandleFilter && (candleSize == 0 || (bodySize / candleSize) < minCandleBodyRatio))
   {
      Print("🕯️ Bougie trop neutre (ratio ", DoubleToString(bodySize / candleSize, 2), ")");
      return;
   }

   // --- BUY
   if(RejetBrusqueBuy())
   {
      if(!useTrendFilterBuy || (ma38_now > ma200_now && ma200_now > ma200_prev))
      {
         double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         tradeOpen(ORDER_TYPE_BUY, entry, atrValue);
         lastTradeTime = TimeCurrent();
         Print("✅ BUY exécuté (filtré)");
      }
      else
      {
         Print("🚫 BUY rejeté : tendance MA non respectée");
      }
   }

   // --- SELL
   if(RejetBrusqueSell())
   {
      if(!useTrendFilterSell || (ma38_now < ma200_now && ma200_now < ma200_prev))
      {
         double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         tradeOpen(ORDER_TYPE_SELL, entry, atrValue);
         lastTradeTime = TimeCurrent();
         Print("✅ SELL exécuté (filtré)");
      }
      else
      {
         Print("🚫 SELL rejeté : tendance MA non respectée");
      }
   }
   
   int i = 1;
double d0 = MAMethodDiff(i);
double d1 = MAMethodDiff(i + 1);

double proximity  = MathAbs(d1);
double ecartement = d0 - d1;

if(proximity  < proxMin)  proxMin  = proximity;
if(proximity  > proxMax)  proxMax  = proximity;
if(ecartement < ecartMin) ecartMin = ecartement;
if(ecartement > ecartMax) ecartMax = ecartement;
}

//+------------------------------------------------------------------+
//| Détection rejet HAUT                                             |
//+------------------------------------------------------------------+
bool RejetBrusqueBuy()
{
   int i = 1;
   double d2 = MAMethodDiff(i + 2);
   double d1 = MAMethodDiff(i + 1);
   double d0 = MAMethodDiff(i);
   return (MathAbs(d2) > MathAbs(d1)) && (MathAbs(d1) < seuilProximite) && (d0 - d1 > seuilEcartement);
}

//+------------------------------------------------------------------+
//| Détection rejet BAS                                              |
//+------------------------------------------------------------------+
bool RejetBrusqueSell()
{
   int i = 1;
   double d2 = MAMethodDiff(i + 2);
   double d1 = MAMethodDiff(i + 1);
   double d0 = MAMethodDiff(i);
   return (MathAbs(d2) > MathAbs(d1)) && (MathAbs(d1) < seuilProximite) && (d1 - d0 > seuilEcartement);
}

//+------------------------------------------------------------------+
//| Différence MA rapide / lente                                     |
//+------------------------------------------------------------------+
double MAMethodDiff(int shift)
{
   return GetMAValue(wmaFastPeriod, shift) - GetMAValue(wmaSlowPeriod, shift);
}

//+------------------------------------------------------------------+
//| Obtenir une MA                                                   |
//+------------------------------------------------------------------+
double GetMAValue(int period, int shift)
{
   int handle = iMA(_Symbol, _Period, period, 0, maMethod, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return 0;

   double buffer[1];
   if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0) return 0;

   return buffer[0];
}

//+------------------------------------------------------------------+
//| Trade avec ATR SL/TP                                             |
//+------------------------------------------------------------------+
void tradeOpen(ENUM_ORDER_TYPE type, double entryPrice, double atrValue)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stopInPrice = atrSLMultiplier * atrValue;

   double sl, tp;
   if(type == ORDER_TYPE_BUY)
   {
      sl = entryPrice - stopInPrice;
      tp = entryPrice + stopInPrice * RiskRewardRatio;
   }
   else
   {
      sl = entryPrice + stopInPrice;
      tp = entryPrice - stopInPrice * RiskRewardRatio;
   }

   entryPrice = NormalizeDouble(entryPrice, digits);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.volume       = lotSize;
   request.type         = type;
   request.price        = entryPrice;
   request.sl           = sl;
   request.tp           = tp;
   request.deviation    = 10;
   request.type_filling = (SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE) == ORDER_FILLING_FOK)
                          ? ORDER_FILLING_FOK : ORDER_FILLING_IOC;

   string directionStr = (type == ORDER_TYPE_BUY) ? "BUY" : "SELL";

   if(!OrderSend(request, result))
   {
      string msg = "Erreur : " + IntegerToString(result.retcode) + " / " + result.comment;
      Print("❌ ", msg);
      LogTradeAttempt(_Symbol, directionStr, entryPrice, sl, tp, msg);
   }
   else
   {
      string msg = "SUCCESS (ticket: " + IntegerToString(result.order) + ")";
      Print("✅ ", msg);
      LogTradeAttempt(_Symbol, directionStr, entryPrice, sl, tp, msg);
   }
}

//+------------------------------------------------------------------+
//| Log initial                                                      |
//+------------------------------------------------------------------+
void InitLogFile()
{
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
   StringReplace(timestamp, ":", "-");
   StringReplace(timestamp, ".", "-");
   logFileName = "trade_log_" + timestamp + ".csv";

   int fileHandle = FileOpen(logFileName, FILE_WRITE | FILE_CSV);
   if(fileHandle != INVALID_HANDLE)
   {
      FileWrite(fileHandle, "Time", "Symbol", "Type", "Entry", "SL", "TP", "Result");
      FileClose(fileHandle);
   }
}

//+------------------------------------------------------------------+
//| Logging dans CSV                                                 |
//+------------------------------------------------------------------+
void LogTradeAttempt(string symbol, string direction, double entry, double sl, double tp, string result)
{
   int fileHandle = FileOpen(logFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(fileHandle != INVALID_HANDLE)
   {
      FileSeek(fileHandle, 0, SEEK_END);
      string timeStr = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      FileWrite(fileHandle, timeStr, symbol, direction,
                DoubleToString(entry, _Digits),
                DoubleToString(sl, _Digits),
                DoubleToString(tp, _Digits),
                result);
      FileClose(fileHandle);
   }
}

void OnDeinit(const int reason)
{
   
      Print("📊 Résumé des seuils observés pendant l'exécution :");
      Print("   ➤ SeuilProximité : min = ", DoubleToString(proxMin, 4),
            " | max = ", DoubleToString(proxMax, 4));
      Print("   ➤ SeuilÉcartement : min = ", DoubleToString(ecartMin, 4),
            " | max = ", DoubleToString(ecartMax, 4));
   
}