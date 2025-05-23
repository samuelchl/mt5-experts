//+------------------------------------------------------------------+
//|        Classe autonome pour calcul de la VaR d'un symbole        |
//+------------------------------------------------------------------+
class VarCalculator
  {
private:
   string  m_symbol;          // Exemple : "XAUUSD"
   int     m_period;          // Nombre de bougies (ex : 100)
   double  m_volatility;      // Volatilité calculée (écart-type)
   double  m_zscore;          // Niveau de confiance (ex : 2.33 pour 99%)
   double  m_tickValue;       // Valeur du point (par lot)
   ENUM_TIMEFRAMES     m_timeframe;       // Timeframe pour la volatilité (ex: PERIOD_H1)

public:
   // Constructeur
   void Init(string symbol, int period=100, double zscore=2.33, ENUM_TIMEFRAMES timeframe=PERIOD_H1)
     {
      m_symbol    = symbol;
      m_period    = period;
      m_zscore    = zscore;
      m_timeframe = timeframe;
      m_volatility= 0.0;
      m_tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
     }

   // Met à jour la volatilité historique
   bool UpdateVolatility()
     {
      double closes[];
      if(CopyClose(m_symbol, m_timeframe, 0, m_period, closes) != m_period)
          return false;

      // Calcul des rendements (log returns)
      double returns[];
      ArrayResize(returns, m_period-1);
      for(int i=1; i<m_period; i++)
         returns[i-1] = MathLog(closes[i] / closes[i-1]);

      m_volatility = StdDev(returns, m_period-1);
      return true;
     }

   // Calcul de la VaR pour une exposition donnée (en lots)
   double ComputeVaR(double lots)
     {
      // VaR = Z * sigma * valeur_exposition (en USD)
      // valeur_exposition = lots * valeur du point * nombre de points de volatilité
      // Ici, on prend la volatilité en rendement (log return), il faut ajuster selon besoin

      // On convertit la volatilité log en pourcentage de variation sur la période
      double variation = m_volatility; // (rendement journalier ou horaire selon timeframe)
      double valeur_expo = lots * m_tickValue * 100; // XAUUSD = 100 unités par lot

      double var = m_zscore * variation * valeur_expo;
      return MathAbs(var);
     }

   // Getters
   double GetVolatility() { return m_volatility; }
   double GetZScore()     { return m_zscore; }
   string GetSymbol()     { return m_symbol; }
   int    GetPeriod()     { return m_period; }
  };

// Fonction utilitaire d'écart-type (si tu ne veux pas importer MathStat)
double StdDev(const double &vals[], int size)
  {
   if(size<=1)
      return(0.0);
   double sum = 0.0, sum2 = 0.0;
   for(int i=0; i<size; i++)
     {
      sum  += vals[i];
      sum2 += vals[i]*vals[i];
     }
   double mean = sum/size;
   double variance = (sum2/size) - (mean*mean);
   if(variance<0) variance = 0.0;
   return(MathSqrt(variance));
  }
