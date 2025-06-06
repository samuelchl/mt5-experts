//+------------------------------------------------------------------+
//|                                                  IdealSpread.mq5|
//|          Script oneshot : liste des symboles spreads idéaux     |
//+------------------------------------------------------------------+
#property copyright "VotreNom"
#property link      ""
#property version   "1.00"
#property script_show_inputs

input double MaxSpreadPips = 2.0;    // Spread max en pips
input double MaxSpreadRel  = 0.0002; // Spread max en relatif (0.02 %)

void OnStart()
{
   int total = SymbolsTotal(true);  // symboles visibles dans Market Watch
   PrintFormat("Recherche de spreads ≤ %.1f pips et ≤ %.4f %% …",
               MaxSpreadPips, MaxSpreadRel*100);

   for(int i=0; i<total; i++)
   {
      string sym = SymbolName(i, true);
      if(!SymbolSelect(sym, true))    // s’assurer que le symbole est chargé
         continue;

      // 1) Spread en points via SymbolInfoInteger (integer)
      long sp_pts = SymbolInfoInteger(sym, SYMBOL_SPREAD);

      // 2) Taille du point et bid via SymbolInfoDouble (double)
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
      if(bid <= 0.0) 
         continue;  // pas de cotation valide

      // 3) Nombre de décimales via SymbolInfoInteger
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

      // 4) Conversions
      double sp_price = sp_pts * point;                            // spread en prix
      double pip_fac  = (digits==5 || digits==3) ? 10.0 : 1.0;      // 10 ticks = 1 pip sur 5/3 déc.
      double sp_pips  = sp_pts / pip_fac;                          // spread en pips
      double sp_rel   = sp_price / bid;                            // spread relatif au prix

      // 5) Filtrage et affichage
      if(sp_pips <= MaxSpreadPips && sp_rel <= MaxSpreadRel)
         PrintFormat("%-10s : %5.1f pts / %4.1f pips / %.4f %%", 
                     sym, (double)sp_pts, sp_pips, sp_rel*100);
   }

   Print("→ Recherche terminée.");
}
