//+------------------------------------------------------------------+
//|     Classe autonome pour calcul de la VaR d'un symbole (améliorée)   |
//+------------------------------------------------------------------+
class VarCalculatorV2
  {
private:
   string  m_symbol;
   int     m_period;
   double  m_volatility;
   double  m_zscore;
   double  m_tickValue;
   double  m_contractSize;
   ENUM_TIMEFRAMES m_timeframe;
   bool    m_isDaily;

public:
   // Constructeur avec option daily
   void Init(string symbol, int period=100, double zscore=2.33, ENUM_TIMEFRAMES timeframe=PERIOD_H1, bool dailyMode=false)
     {
      m_symbol     = symbol;
      m_period     = period;
      m_zscore     = zscore;
      m_timeframe  = timeframe;
      m_isDaily    = dailyMode;
      m_volatility = 0.0;

      m_tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      m_contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      
      PrintFormat("DEBUG — TickValue: %.5f | ContractSize: %.2f", m_tickValue, m_contractSize);
     }

   // Met à jour la volatilité historique (log returns)
bool UpdateVolatility()
  {
   double closes[];
   if(CopyClose(m_symbol, m_timeframe, 0, m_period, closes) != m_period)
      return false;

   double returns[];
   ArrayResize(returns, m_period - 1);

   for(int i = 1; i < m_period; i++)
     {
      if(closes[i - 1] <= 0.0)
         return false;

      returns[i - 1] = MathLog(closes[i] / closes[i - 1]);
     }

   // Ajoute ici
   PrintFormat("DEBUG: Premier log-return = %.6f, Dernier = %.6f",
               returns[0], returns[m_period - 2]);

   m_volatility = _StdDev(returns, m_period - 1);

   PrintFormat("DEBUG: Volatility calculée = %.6f", m_volatility);

   return true;
  }


   // Calcul VaR paramétrique (Z * sigma)
  double ComputeVaR(double lots)
  {
   if(m_volatility <= 0.0)
     {
      Print("ComputeVaR: volatilité nulle ou non initialisée.");
      return 0.0;
     }

   double variation = m_volatility;

   // Ajustement journalier si demandé
   if(m_isDaily && m_timeframe != PERIOD_D1)
     {
      int candlesPerDay = 24 * 60 * 60 / PeriodSeconds(m_timeframe);
      variation *= MathSqrt(candlesPerDay);
     }

   double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0 || tickValue <= 0)
     {
      Print("ComputeVaR: tickValue ou tickSize invalide.");
      return 0.0;
     }

   double valeur_expo = lots * tickValue / tickSize;
   double var = m_zscore * variation * valeur_expo;

   PrintFormat("ComputeVaR DEBUG — lots=%.2f | tickValue=%.5f | tickSize=%.5f | valeur_expo=%.2f | variation=%.6f | VaR=%.2f",
               lots, tickValue, tickSize, valeur_expo, variation, var);

   return MathAbs(var);
  }


   // VaR historique (empirique, percentile des pertes)
   double ComputeHistoricalVaR(double lots, double percentile=0.01)
     {
      double closes[];
      if(CopyClose(m_symbol, m_timeframe, 0, m_period, closes) != m_period)
         return -1.0;

      double returns[];
      ArrayResize(returns, m_period-1);
      for(int i=1; i<m_period; i++)
         returns[i-1] = MathLog(closes[i] / closes[i-1]);

      ArraySort(returns);
      int index = (int)(percentile * (m_period - 1));
      double worstReturn = returns[index];
      double valeur_expo = lots * m_contractSize;

      return MathAbs(worstReturn * valeur_expo);
     }

   // Getters
   double GetVolatility() { return m_volatility; }
   double GetZScore()     { return m_zscore; }
   string GetSymbol()     { return m_symbol; }
   int    GetPeriod()     { return m_period; }
  };

double _StdDev(const double &vals[], int size)
  {
   if(size <= 1)
      return 0.0;

   double sum = 0.0, sum2 = 0.0;
   for(int i = 0; i < size; i++)
     {
      sum  += vals[i];
      sum2 += vals[i] * vals[i];
     }

   double mean     = sum / size;
   double variance = (sum2 / size) - (mean * mean);

   //  Ce fix est vital
   if(variance < 1e-12)
      return 0.0;

   return MathSqrt(variance);
  }

