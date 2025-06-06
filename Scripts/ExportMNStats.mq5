//+------------------------------------------------------------------+
//|                                           ExportMNStats.mq5      |
//| Script MT5 : stats groupées par Magic & Symbol, ratios, export  |
//+------------------------------------------------------------------+
#property script_show_inputs

void OnStart()
{
   // 1) Sélection de tout l'historique
   if(!HistorySelect(0,TimeCurrent()))
   {
      Print("Erreur de sélection de l'historique");
      return;
   }
   int total=HistoryDealsTotal();
   if(total<=0)
   {
      Print("Pas de deals historiques.");
      return;
   }

   // 2) Tableaux pour les groupes (Magic+Symbol) et leurs stats
   long     grpMagic[];
   string   grpSymbol[];
   int      tradesCount[];
   double   totalProfit[], winProfit[], lossAmount[], commissionTotal[], swapTotal[];
   int      winCount[], lossCount[];
   double   sumSqProfit[];
   double   maxProfitDeal[], maxLossDeal[];
   double   maxDailyProfit[], maxDailyLoss[];
   datetime maxDailyProfitDate[], maxDailyLossDate[];

   // 3) Tableaux « plats » pour agréger le profit par (groupe, jour)
   datetime dailyDays[];
   int      dailyGroupIdx[];
   double   dailyProfits[];

   // 4) Parcours de tous les deals
   for(int i=0; i<total; i++)
   {
      // récupérer ticket & infos
      ulong   ticket     = HistoryDealGetTicket(i);
      long    magic      = (long)HistoryDealGetInteger (ticket, DEAL_MAGIC);
      string  symbol     =            HistoryDealGetString  (ticket, DEAL_SYMBOL);
      double  profit     =            HistoryDealGetDouble  (ticket, DEAL_PROFIT);
      double  commission =            HistoryDealGetDouble  (ticket, DEAL_COMMISSION);
      double  swap_      =            HistoryDealGetDouble  (ticket, DEAL_SWAP);
      datetime dt        = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      datetime day       = dt - (dt % 86400); // minuit

      // --- créer / trouver le groupe correspondant
      int idx=-1;
      for(int j=0; j<ArraySize(grpMagic); j++)
         if(grpMagic[j]==magic && grpSymbol[j]==symbol)
         {
            idx=j;
            break;
         }
      if(idx<0)
      {
         // nouveau groupe
         idx = ArraySize(grpMagic);
         ArrayResize(grpMagic,         idx+1);
         ArrayResize(grpSymbol,        idx+1);
         ArrayResize(tradesCount,      idx+1);
         ArrayResize(totalProfit,      idx+1);
         ArrayResize(winProfit,        idx+1);
         ArrayResize(lossAmount,       idx+1);
         ArrayResize(commissionTotal,  idx+1);
         ArrayResize(swapTotal,        idx+1);
         ArrayResize(winCount,         idx+1);
         ArrayResize(lossCount,        idx+1);
         ArrayResize(sumSqProfit,      idx+1);
         ArrayResize(maxProfitDeal,    idx+1);
         ArrayResize(maxLossDeal,      idx+1);
         ArrayResize(maxDailyProfit,   idx+1);
         ArrayResize(maxDailyLoss,     idx+1);
         ArrayResize(maxDailyProfitDate,idx+1);
         ArrayResize(maxDailyLossDate,  idx+1);

         grpMagic[idx]           = magic;
         grpSymbol[idx]          = symbol;
         tradesCount[idx]        = 0;
         totalProfit[idx]        = 0.0;
         winProfit[idx]          = 0.0;
         lossAmount[idx]         = 0.0;
         commissionTotal[idx]    = 0.0;
         swapTotal[idx]          = 0.0;
         winCount[idx]           = 0;
         lossCount[idx]          = 0;
         sumSqProfit[idx]        = 0.0;
         maxProfitDeal[idx]      = -DBL_MAX;
         maxLossDeal[idx]        =  DBL_MAX;
         maxDailyProfit[idx]     = -DBL_MAX;
         maxDailyLoss[idx]       =  DBL_MAX;
         maxDailyProfitDate[idx] =  0;
         maxDailyLossDate[idx]   =  0;
      }

      // --- mise à jour des stats globales
      tradesCount[idx]++;
      totalProfit[idx]     += profit;
      commissionTotal[idx] += commission;
      swapTotal[idx]       += swap_;
      sumSqProfit[idx]     += profit*profit;
      if(profit>0) { winProfit[idx] += profit; winCount[idx]++; }
      else if(profit<0) { lossAmount[idx] += profit; lossCount[idx]++; }
      if(profit>maxProfitDeal[idx]) maxProfitDeal[idx] = profit;
      if(profit<maxLossDeal[idx])   maxLossDeal[idx]   = profit;

      // --- cumul journalier (plat)
      int di=-1;
      for(int k=0; k<ArraySize(dailyDays); k++)
         if(dailyGroupIdx[k]==idx && dailyDays[k]==day)
         {
            di=k;
            break;
         }
      if(di<0)
      {
         di = ArraySize(dailyDays);
         ArrayResize(dailyDays,     di+1);
         ArrayResize(dailyGroupIdx, di+1);
         ArrayResize(dailyProfits,  di+1);
         dailyDays[di]      = day;
         dailyGroupIdx[di]  = idx;
         dailyProfits[di]   = 0.0;
      }
      dailyProfits[di] += profit;
      // MAJ max journalier
      if(dailyProfits[di] > maxDailyProfit[idx])
      {
         maxDailyProfit[idx]     = dailyProfits[di];
         maxDailyProfitDate[idx] = day;
      }
      if(dailyProfits[di] < maxDailyLoss[idx])
      {
         maxDailyLoss[idx]       = dailyProfits[di];
         maxDailyLossDate[idx]   = day;
      }
   }

   // 5) Construire le suffixe date-heure pour le fichier
   datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now, tm);
   string y  = IntegerToString(tm.year);
   string mo = (tm.mon<10?"0":"") + IntegerToString(tm.mon);
   string da = (tm.day<10?"0":"") + IntegerToString(tm.day);
   string ho = (tm.hour<10?"0":"") + IntegerToString(tm.hour);
   string mi = (tm.min<10?"0":"") + IntegerToString(tm.min);
   string se = (tm.sec<10?"0":"") + IntegerToString(tm.sec);
   string suffix = y+mo+da+"_"+ho+mi+se;
   string fname  = "ExportMNStats_"+suffix+".csv";

   // 6) Ouvrir le fichier et écrire l’en-tête
   int file = FileOpen(fname, FILE_WRITE|FILE_ANSI);
   if(file==INVALID_HANDLE)
   {
      Print("Impossible d'ouvrir ", fname);
      return;
   }
   FileWriteString(file,
     "Magic;Symbol;Trades;TotalProfit;WinProfit;LossAmount;Commission;Swap;"
     "WinCount;LossCount;WinRate%;ProfitFactor;AvgDeal;AvgWin;AvgLoss;"
     "WinLossCountRatio;AvgWinAvgLossRatio;Expectancy;StdDev;SharpeRatio;"
     "MaxDealProfit;MaxDealLoss;MaxDailyProfit;DateMaxDailyProfit;"
     "MaxDailyLoss;DateMaxDailyLoss\n"
   );

   // 7) Calcul des ratios et écriture ligne par ligne
   int G = ArraySize(grpMagic);
   for(int m=0; m<G; m++)
   {
      double wr   = tradesCount[m]>0 ? (double)winCount[m]/tradesCount[m]*100.0 : 0.0;
      double pf   = lossAmount[m]<0 ? winProfit[m]/(-lossAmount[m])           : 0.0;
      double avgD = tradesCount[m]>0 ? totalProfit[m]/tradesCount[m]         : 0.0;
      double avgW = winCount[m]>0    ? winProfit[m]/winCount[m]              : 0.0;
      double avgL = lossCount[m]>0   ? lossAmount[m]/lossCount[m]            : 0.0;
      double wlR  = lossCount[m]>0   ? (double)winCount[m]/lossCount[m]      : 0.0;
      double awl  = avgL<0           ? avgW/(-avgL)                         : 0.0;
      double expc = (wr/100.0)*avgW + (1.0-wr/100.0)*avgL;
      double var  = tradesCount[m]>0 ? sumSqProfit[m]/tradesCount[m] - avgD*avgD : 0.0;
      double sd   = var>0            ? MathSqrt(var)                         : 0.0;
      double sr   = sd>0             ? avgD/sd                                : 0.0;

      string line =
         IntegerToString(grpMagic[m]) + ";" +
         grpSymbol[m]                + ";" +
         IntegerToString(tradesCount[m]) + ";" +
         DoubleToString(totalProfit[m],2) + ";" +
         DoubleToString(winProfit[m],2)   + ";" +
         DoubleToString(lossAmount[m],2)  + ";" +
         DoubleToString(commissionTotal[m],2) + ";" +
         DoubleToString(swapTotal[m],2)        + ";" +
         IntegerToString(winCount[m])     + ";" +
         IntegerToString(lossCount[m])    + ";" +
         DoubleToString(wr,2)             + ";" +
         DoubleToString(pf,2)             + ";" +
         DoubleToString(avgD,2)           + ";" +
         DoubleToString(avgW,2)           + ";" +
         DoubleToString(avgL,2)           + ";" +
         DoubleToString(wlR,2)            + ";" +
         DoubleToString(awl,2)            + ";" +
         DoubleToString(expc,2)           + ";" +
         DoubleToString(sd,2)             + ";" +
         DoubleToString(sr,2)             + ";" +
         DoubleToString(maxProfitDeal[m],2) + ";" +
         DoubleToString(maxLossDeal[m],2)   + ";" +
         DoubleToString(maxDailyProfit[m],2) + ";" +
         TimeToString(maxDailyProfitDate[m],TIME_DATE) + ";" +
         DoubleToString(maxDailyLoss[m],2)    + ";" +
         TimeToString(maxDailyLossDate[m],TIME_DATE)   + "\n";

      FileWriteString(file, line);
   }

   FileClose(file);
   Print("Export terminé : Files\\", fname);
}
