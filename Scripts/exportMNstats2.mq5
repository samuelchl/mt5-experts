//+------------------------------------------------------------------+
//|                                           ExportMNStats.mq5      |
//| Script MT5 : stats group�es par Magic & Symbol, ratios, export  |
//+------------------------------------------------------------------+
#property script_show_inputs

// Correspondance position_ticket -> magic
ulong positionTickets[];
long  positionMagics[];

// Recherche magic via ticket position
long FindMagicByPosition(ulong pos_ticket)
{
   int size = ArraySize(positionTickets);
   for(int i=0; i<size; i++)
      if(positionTickets[i] == pos_ticket)
         return positionMagics[i];
   return 0;
}

// Retourne ann�e + num�ro semaine (approximation)
int GetYearWeek(datetime dt)
{
   MqlDateTime tm;
   TimeToStruct(dt, tm);

   MqlDateTime tmYearStart = tm;
   tmYearStart.mon = 1; tmYearStart.day = 1;
   tmYearStart.hour = 0; tmYearStart.min = 0; tmYearStart.sec = 0;

   datetime yearStart = StructToTime(tmYearStart);
   int dayOfYear = int((dt - yearStart) / 86400) + 1;
   int week = (dayOfYear - 1) / 7 + 1;

   return tm.year * 100 + week;
}

// --- Structures breakdown journalier par Magic ---
datetime dayMagicDays[];
long     dayMagicMagic[];
int      dayMagicTradesCount[];
double   dayMagicTotalProfit[], dayMagicWinProfit[], dayMagicLossAmount[];
double   dayMagicCommissionTotal[], dayMagicSwapTotal[];
int      dayMagicWinCount[], dayMagicLossCount[];
double   dayMagicSumSqProfit[];
double   dayMagicMaxProfitDeal[], dayMagicMaxLossDeal[];

// --- Structures breakdown hebdo par Magic ---
int      weekMagicWeeks[];
long     weekMagicMagic[];
int      weekMagicTradesCount[];
double   weekMagicTotalProfit[], weekMagicWinProfit[], weekMagicLossAmount[];
double   weekMagicCommissionTotal[], weekMagicSwapTotal[];
int      weekMagicWinCount[], weekMagicLossCount[];
double   weekMagicSumSqProfit[];
double   weekMagicMaxProfitDeal[], weekMagicMaxLossDeal[];

// Trouve ou cr�e index dans breakdown journalier Magic
int FindOrAddDayMagicIndex(long magic, datetime day)
{
   int size = ArraySize(dayMagicMagic);
   for(int i=0; i<size; i++)
      if(dayMagicMagic[i] == magic && dayMagicDays[i] == day)
         return i;

   ArrayResize(dayMagicMagic, size + 1);
   ArrayResize(dayMagicDays, size + 1);
   ArrayResize(dayMagicTradesCount, size + 1);
   ArrayResize(dayMagicTotalProfit, size + 1);
   ArrayResize(dayMagicWinProfit, size + 1);
   ArrayResize(dayMagicLossAmount, size + 1);
   ArrayResize(dayMagicCommissionTotal, size + 1);
   ArrayResize(dayMagicSwapTotal, size + 1);
   ArrayResize(dayMagicWinCount, size + 1);
   ArrayResize(dayMagicLossCount, size + 1);
   ArrayResize(dayMagicSumSqProfit, size + 1);
   ArrayResize(dayMagicMaxProfitDeal, size + 1);
   ArrayResize(dayMagicMaxLossDeal, size + 1);

   dayMagicMagic[size] = magic;
   dayMagicDays[size] = day;
   dayMagicTradesCount[size] = 0;
   dayMagicTotalProfit[size] = 0.0;
   dayMagicWinProfit[size] = 0.0;
   dayMagicLossAmount[size] = 0.0;
   dayMagicCommissionTotal[size] = 0.0;
   dayMagicSwapTotal[size] = 0.0;
   dayMagicWinCount[size] = 0;
   dayMagicLossCount[size] = 0;
   dayMagicSumSqProfit[size] = 0.0;
   dayMagicMaxProfitDeal[size] = -DBL_MAX;
   dayMagicMaxLossDeal[size] = DBL_MAX;

   return size;
}

// Trouve ou cr�e index dans breakdown hebdo Magic
int FindOrAddWeekMagicIndex(long magic, int week)
{
   int size = ArraySize(weekMagicMagic);
   for(int i=0; i<size; i++)
      if(weekMagicMagic[i] == magic && weekMagicWeeks[i] == week)
         return i;

   ArrayResize(weekMagicMagic, size + 1);
   ArrayResize(weekMagicWeeks, size + 1);
   ArrayResize(weekMagicTradesCount, size + 1);
   ArrayResize(weekMagicTotalProfit, size + 1);
   ArrayResize(weekMagicWinProfit, size + 1);
   ArrayResize(weekMagicLossAmount, size + 1);
   ArrayResize(weekMagicCommissionTotal, size + 1);
   ArrayResize(weekMagicSwapTotal, size + 1);
   ArrayResize(weekMagicWinCount, size + 1);
   ArrayResize(weekMagicLossCount, size + 1);
   ArrayResize(weekMagicSumSqProfit, size + 1);
   ArrayResize(weekMagicMaxProfitDeal, size + 1);
   ArrayResize(weekMagicMaxLossDeal, size + 1);

   weekMagicMagic[size] = magic;
   weekMagicWeeks[size] = week;
   weekMagicTradesCount[size] = 0;
   weekMagicTotalProfit[size] = 0.0;
   weekMagicWinProfit[size] = 0.0;
   weekMagicLossAmount[size] = 0.0;
   weekMagicCommissionTotal[size] = 0.0;
   weekMagicSwapTotal[size] = 0.0;
   weekMagicWinCount[size] = 0;
   weekMagicLossCount[size] = 0;
   weekMagicSumSqProfit[size] = 0.0;
   weekMagicMaxProfitDeal[size] = -DBL_MAX;
   weekMagicMaxLossDeal[size] = DBL_MAX;

   return size;
}

void OnStart()
{
   // S�lection historique
   if(!HistorySelect(0, TimeCurrent()))
   {
      Print("Erreur de s�lection de l'historique");
      return;
   }
   int total = HistoryDealsTotal();
   if(total <= 0)
   {
      Print("Pas de deals historiques.");
      return;
   }

   // Construction position_ticket -> magic
   for(int i=0; i<total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      ulong pos_ticket = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

      if(magic != 0 && pos_ticket != 0)
      {
         bool exists = false;
         int size = ArraySize(positionTickets);
         for(int j=0; j<size; j++)
            if(positionTickets[j] == pos_ticket)
            {
               exists = true;
               break;
            }
         if(!exists)
         {
            ArrayResize(positionTickets, size + 1);
            ArrayResize(positionMagics, size + 1);
            positionTickets[size] = pos_ticket;
            positionMagics[size] = magic;
         }
      }
   }

   // Structures principales Magic+Symbol
   long     grpMagic[];
   string   grpSymbol[];
   int      tradesCount[];
   double   totalProfit[], winProfit[], lossAmount[], commissionTotal[], swapTotal[];
   int      winCount[], lossCount[];
   double   sumSqProfit[];
   double   maxProfitDeal[], maxLossDeal[];
   double   maxDailyProfit[], maxDailyLoss[];
   datetime maxDailyProfitDate[], maxDailyLossDate[];

   datetime dailyDays[];
   int      dailyGroupIdx[];
   double   dailyProfits[];

   // Parcours deals
   for(int i=0; i<total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      ulong pos_ticket = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

      if(magic == 0 && pos_ticket != 0)
         magic = FindMagicByPosition(pos_ticket);

      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap_ = HistoryDealGetDouble(ticket, DEAL_SWAP);
      datetime dt = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      datetime day = dt - (dt % 86400);

      // Magic+Symbol
      int idx = -1;
      for(int j=0; j<ArraySize(grpMagic); j++)
         if(grpMagic[j] == magic && grpSymbol[j] == symbol)
         {
            idx = j;
            break;
         }
      if(idx < 0)
      {
         idx = ArraySize(grpMagic);
         ArrayResize(grpMagic, idx + 1);
         ArrayResize(grpSymbol, idx + 1);
         ArrayResize(tradesCount, idx + 1);
         ArrayResize(totalProfit, idx + 1);
         ArrayResize(winProfit, idx + 1);
         ArrayResize(lossAmount, idx + 1);
         ArrayResize(commissionTotal, idx + 1);
         ArrayResize(swapTotal, idx + 1);
         ArrayResize(winCount, idx + 1);
         ArrayResize(lossCount, idx + 1);
         ArrayResize(sumSqProfit, idx + 1);
         ArrayResize(maxProfitDeal, idx + 1);
         ArrayResize(maxLossDeal, idx + 1);
         ArrayResize(maxDailyProfit, idx + 1);
         ArrayResize(maxDailyLoss, idx + 1);
         ArrayResize(maxDailyProfitDate, idx + 1);
         ArrayResize(maxDailyLossDate, idx + 1);

         grpMagic[idx] = magic;
         grpSymbol[idx] = symbol;
         tradesCount[idx] = 0;
         totalProfit[idx] = 0.0;
         winProfit[idx] = 0.0;
         lossAmount[idx] = 0.0;
         commissionTotal[idx] = 0.0;
         swapTotal[idx] = 0.0;
         winCount[idx] = 0;
         lossCount[idx] = 0;
         sumSqProfit[idx] = 0.0;
         maxProfitDeal[idx] = -DBL_MAX;
         maxLossDeal[idx] = DBL_MAX;
         maxDailyProfit[idx] = -DBL_MAX;
         maxDailyLoss[idx] = DBL_MAX;
         maxDailyProfitDate[idx] = 0;
         maxDailyLossDate[idx] = 0;
      }

      // Mise � jour Magic+Symbol
      tradesCount[idx]++;
      totalProfit[idx] += profit;
      commissionTotal[idx] += commission;
      swapTotal[idx] += swap_;
      sumSqProfit[idx] += profit * profit;
      if(profit > 0) { winProfit[idx] += profit; winCount[idx]++; }
      else if(profit < 0) { lossAmount[idx] += profit; lossCount[idx]++; }
      if(profit > maxProfitDeal[idx]) maxProfitDeal[idx] = profit;
      if(profit < maxLossDeal[idx]) maxLossDeal[idx] = profit;

      // Agr�gats journaliers Magic+Symbol
      int di = -1;
      for(int k=0; k<ArraySize(dailyDays); k++)
         if(dailyGroupIdx[k] == idx && dailyDays[k] == day)
         {
            di = k;
            break;
         }
      if(di < 0)
      {
         di = ArraySize(dailyDays);
         ArrayResize(dailyDays, di + 1);
         ArrayResize(dailyGroupIdx, di + 1);
         ArrayResize(dailyProfits, di + 1);
         dailyDays[di] = day;
         dailyGroupIdx[di] = idx;
         dailyProfits[di] = 0.0;
      }
      dailyProfits[di] += profit;

      if(dailyProfits[di] > maxDailyProfit[idx])
      {
         maxDailyProfit[idx] = dailyProfits[di];
         maxDailyProfitDate[idx] = day;
      }
      if(dailyProfits[di] < maxDailyLoss[idx])
      {
         maxDailyLoss[idx] = dailyProfits[di];
         maxDailyLossDate[idx] = day;
      }

      // Breakdown journalier Magic
      int idxDay = FindOrAddDayMagicIndex(magic, day);
      dayMagicTradesCount[idxDay]++;
      dayMagicTotalProfit[idxDay] += profit;
      dayMagicCommissionTotal[idxDay] += commission;
      dayMagicSwapTotal[idxDay] += swap_;
      dayMagicSumSqProfit[idxDay] += profit * profit;
      if(profit > 0) { dayMagicWinProfit[idxDay] += profit; dayMagicWinCount[idxDay]++; }
      else if(profit < 0) { dayMagicLossAmount[idxDay] += profit; dayMagicLossCount[idxDay]++; }
      if(profit > dayMagicMaxProfitDeal[idxDay]) dayMagicMaxProfitDeal[idxDay] = profit;
      if(profit < dayMagicMaxLossDeal[idxDay]) dayMagicMaxLossDeal[idxDay] = profit;

      // Breakdown hebdo Magic
      int weekKey = GetYearWeek(day);
      int idxWeek = FindOrAddWeekMagicIndex(magic, weekKey);
      weekMagicTradesCount[idxWeek]++;
      weekMagicTotalProfit[idxWeek] += profit;
      weekMagicCommissionTotal[idxWeek] += commission;
      weekMagicSwapTotal[idxWeek] += swap_;
      weekMagicSumSqProfit[idxWeek] += profit * profit;
      if(profit > 0) { weekMagicWinProfit[idxWeek] += profit; weekMagicWinCount[idxWeek]++; }
      else if(profit < 0) { weekMagicLossAmount[idxWeek] += profit; weekMagicLossCount[idxWeek]++; }
      if(profit > weekMagicMaxProfitDeal[idxWeek]) weekMagicMaxProfitDeal[idxWeek] = profit;
      if(profit < weekMagicMaxLossDeal[idxWeek]) weekMagicMaxLossDeal[idxWeek] = profit;
   }

   // Construction suffixe date/heure pour fichiers
   datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now, tm);
   string y = IntegerToString(tm.year);
   string mo = (tm.mon < 10 ? "0" : "") + IntegerToString(tm.mon);
   string da = (tm.day < 10 ? "0" : "") + IntegerToString(tm.day);
   string ho = (tm.hour < 10 ? "0" : "") + IntegerToString(tm.hour);
   string mi = (tm.min < 10 ? "0" : "") + IntegerToString(tm.min);
   string se = (tm.sec < 10 ? "0" : "") + IntegerToString(tm.sec);
   string suffix = y + mo + da + "_" + ho + mi + se;

   // Export principal Magic+Symbol
   string fname = "ExportMNStats_" + suffix + ".csv";
   int file = FileOpen(fname, FILE_WRITE | FILE_ANSI);
   if(file == INVALID_HANDLE)
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

   int G = ArraySize(grpMagic);
   for(int m=0; m<G; m++)
   {
      double wr   = tradesCount[m] > 0 ? (double)winCount[m] / tradesCount[m] * 100.0 : 0.0;
      double pf   = lossAmount[m] < 0 ? winProfit[m] / (-lossAmount[m])           : 0.0;
      double avgD = tradesCount[m] > 0 ? totalProfit[m] / tradesCount[m]         : 0.0;
      double avgW = winCount[m] > 0    ? winProfit[m] / winCount[m]              : 0.0;
      double avgL = lossCount[m] > 0   ? lossAmount[m] / lossCount[m]            : 0.0;
      double wlR  = lossCount[m] > 0   ? (double)winCount[m] / lossCount[m]      : 0.0;
      double awl  = avgL < 0           ? avgW / (-avgL)                         : 0.0;
      double expc = (wr / 100.0) * avgW + (1.0 - wr / 100.0) * avgL;
      double var  = tradesCount[m] > 0 ? sumSqProfit[m] / tradesCount[m] - avgD * avgD : 0.0;
      double sd   = var > 0            ? MathSqrt(var)                         : 0.0;
      double sr   = sd > 0             ? avgD / sd                            : 0.0;

      string line =
         IntegerToString(grpMagic[m]) + ";" +
         grpSymbol[m]                + ";" +
         IntegerToString(tradesCount[m]) + ";" +
         DoubleToString(totalProfit[m], 2) + ";" +
         DoubleToString(winProfit[m], 2)   + ";" +
         DoubleToString(lossAmount[m], 2)  + ";" +
         DoubleToString(commissionTotal[m], 2) + ";" +
         DoubleToString(swapTotal[m], 2)        + ";" +
         IntegerToString(winCount[m])     + ";" +
         IntegerToString(lossCount[m])    + ";" +
         DoubleToString(wr, 2)             + ";" +
         DoubleToString(pf, 2)             + ";" +
         DoubleToString(avgD, 2)           + ";" +
         DoubleToString(avgW, 2)           + ";" +
         DoubleToString(avgL, 2)           + ";" +
         DoubleToString(wlR, 2)            + ";" +
         DoubleToString(awl, 2)            + ";" +
         DoubleToString(expc, 2)           + ";" +
         DoubleToString(sd, 2)             + ";" +
         DoubleToString(sr, 2)             + ";" +
         DoubleToString(maxProfitDeal[m], 2) + ";" +
         DoubleToString(maxLossDeal[m], 2)   + ";" +
         DoubleToString(maxDailyProfit[m], 2) + ";" +
         TimeToString(maxDailyProfitDate[m], TIME_DATE) + ";" +
         DoubleToString(maxDailyLoss[m], 2)    + ";" +
         TimeToString(maxDailyLossDate[m], TIME_DATE)   + "\n";

      FileWriteString(file, line);
   }
   FileClose(file);
   Print("Export Magic+Symbol termin� : Files\\", fname);

   // Export breakdown journalier Magic
   string fnameDay = "ExportMNStats_DayMagic_" + suffix + ".csv";
   int fileDay = FileOpen(fnameDay, FILE_WRITE | FILE_ANSI);
   if(fileDay == INVALID_HANDLE)
   {
      Print("Impossible d'ouvrir ", fnameDay);
      return;
   }
   FileWriteString(fileDay,
      "Magic;Date;Trades;TotalProfit;WinProfit;LossAmount;Commission;Swap;WinCount;LossCount;WinRate%;ProfitFactor;AvgDeal;AvgWin;AvgLoss;WinLossCountRatio;AvgWinAvgLossRatio;Expectancy;StdDev;SharpeRatio;MaxDealProfit;MaxDealLoss\n"
   );
   int sizeDay = ArraySize(dayMagicMagic);
   for(int i=0; i<sizeDay; i++)
   {
      double wr   = dayMagicTradesCount[i] > 0 ? (double)dayMagicWinCount[i] / dayMagicTradesCount[i] * 100.0 : 0.0;
      double pf   = dayMagicLossAmount[i] < 0 ? dayMagicWinProfit[i] / (-dayMagicLossAmount[i])               : 0.0;
      double avgD = dayMagicTradesCount[i] > 0 ? dayMagicTotalProfit[i] / dayMagicTradesCount[i]               : 0.0;
      double avgW = dayMagicWinCount[i] > 0    ? dayMagicWinProfit[i] / dayMagicWinCount[i]                    : 0.0;
      double avgL = dayMagicLossCount[i] > 0   ? dayMagicLossAmount[i] / dayMagicLossCount[i]                 : 0.0;
      double wlR  = dayMagicLossCount[i] > 0   ? (double)dayMagicWinCount[i] / dayMagicLossCount[i]           : 0.0;
      double awl  = avgL < 0                     ? avgW / (-avgL)                                             : 0.0;
      double expc = (wr / 100.0) * avgW + (1.0 - wr / 100.0) * avgL;
      double var  = dayMagicTradesCount[i] > 0 ? dayMagicSumSqProfit[i] / dayMagicTradesCount[i] - avgD * avgD : 0.0;
      double sd   = var > 0                      ? MathSqrt(var)                                               : 0.0;
      double sr   = sd > 0                       ? avgD / sd                                                  : 0.0;

      string dateStr = TimeToString(dayMagicDays[i], TIME_DATE);

      string line =
         IntegerToString(dayMagicMagic[i]) + ";" +
         dateStr + ";" +
         IntegerToString(dayMagicTradesCount[i]) + ";" +
         DoubleToString(dayMagicTotalProfit[i], 2) + ";" +
         DoubleToString(dayMagicWinProfit[i], 2) + ";" +
         DoubleToString(dayMagicLossAmount[i], 2) + ";" +
         DoubleToString(dayMagicCommissionTotal[i], 2) + ";" +
         DoubleToString(dayMagicSwapTotal[i], 2) + ";" +
         IntegerToString(dayMagicWinCount[i]) + ";" +
         IntegerToString(dayMagicLossCount[i]) + ";" +
         DoubleToString(wr, 2) + ";" +
         DoubleToString(pf, 2) + ";" +
         DoubleToString(avgD, 2) + ";" +
         DoubleToString(avgW, 2) + ";" +
         DoubleToString(avgL, 2) + ";" +
         DoubleToString(wlR, 2) + ";" +
         DoubleToString(awl, 2) + ";" +
         DoubleToString(expc, 2) + ";" +
         DoubleToString(sd, 2) + ";" +
         DoubleToString(sr, 2) + ";" +
         DoubleToString(dayMagicMaxProfitDeal[i], 2) + ";" +
         DoubleToString(dayMagicMaxLossDeal[i], 2) + "\n";

      FileWriteString(fileDay, line);
   }
   FileClose(fileDay);
   Print("Export breakdown journalier Magic termin� : Files\\", fnameDay);

   // Export breakdown hebdo Magic
   string fnameWeek = "ExportMNStats_WeekMagic_" + suffix + ".csv";
   int fileWeek = FileOpen(fnameWeek, FILE_WRITE | FILE_ANSI);
   if(fileWeek == INVALID_HANDLE)
   {
      Print("Impossible d'ouvrir ", fnameWeek);
      return;
   }
   FileWriteString(fileWeek,
      "Magic;YearWeek;Trades;TotalProfit;WinProfit;LossAmount;Commission;Swap;WinCount;LossCount;WinRate%;ProfitFactor;AvgDeal;AvgWin;AvgLoss;WinLossCountRatio;AvgWinAvgLossRatio;Expectancy;StdDev;SharpeRatio;MaxDealProfit;MaxDealLoss\n"
   );
   int sizeWeek = ArraySize(weekMagicMagic);
   for(int i=0; i<sizeWeek; i++)
   {
      double wr   = weekMagicTradesCount[i] > 0 ? (double)weekMagicWinCount[i] / weekMagicTradesCount[i] * 100.0 : 0.0;
      double pf   = weekMagicLossAmount[i] < 0 ? weekMagicWinProfit[i] / (-weekMagicLossAmount[i])               : 0.0;
      double avgD = weekMagicTradesCount[i] > 0 ? weekMagicTotalProfit[i] / weekMagicTradesCount[i]               : 0.0;
      double avgW = weekMagicWinCount[i] > 0    ? weekMagicWinProfit[i] / weekMagicWinCount[i]                    : 0.0;
      double avgL = weekMagicLossCount[i] > 0   ? weekMagicLossAmount[i] / weekMagicLossCount[i]                 : 0.0;
      double wlR  = weekMagicLossCount[i] > 0   ? (double)weekMagicWinCount[i] / weekMagicLossCount[i]           : 0.0;
      double awl  = avgL < 0                      ? avgW / (-avgL)                                             : 0.0;
      double expc = (wr / 100.0) * avgW + (1.0 - wr / 100.0) * avgL;
      double var  = weekMagicTradesCount[i] > 0 ? weekMagicSumSqProfit[i] / weekMagicTradesCount[i] - avgD * avgD : 0.0;
      double sd   = var > 0                       ? MathSqrt(var)                                               : 0.0;
      double sr   = sd > 0                        ? avgD / sd                                                  : 0.0;

      string line =
         IntegerToString(weekMagicMagic[i]) + ";" +
         IntegerToString(weekMagicWeeks[i]) + ";" +
         IntegerToString(weekMagicTradesCount[i]) + ";" +
         DoubleToString(weekMagicTotalProfit[i], 2) + ";" +
         DoubleToString(weekMagicWinProfit[i], 2) + ";" +
         DoubleToString(weekMagicLossAmount[i], 2) + ";" +
         DoubleToString(weekMagicCommissionTotal[i], 2) + ";" +
         DoubleToString(weekMagicSwapTotal[i], 2) + ";" +
         IntegerToString(weekMagicWinCount[i]) + ";" +
         IntegerToString(weekMagicLossCount[i]) + ";" +
         DoubleToString(wr, 2) + ";" +
         DoubleToString(pf, 2) + ";" +
         DoubleToString(avgD, 2) + ";" +
         DoubleToString(avgW, 2) + ";" +
         DoubleToString(avgL, 2) + ";" +
         DoubleToString(wlR, 2) + ";" +
         DoubleToString(awl, 2) + ";" +
         DoubleToString(expc, 2) + ";" +
         DoubleToString(sd, 2) + ";" +
         DoubleToString(sr, 2) + ";" +
         DoubleToString(weekMagicMaxProfitDeal[i], 2) + ";" +
         DoubleToString(weekMagicMaxLossDeal[i], 2) + "\n";

      FileWriteString(fileWeek, line);
   }
   FileClose(fileWeek);
   Print("Export breakdown hebdo Magic termin� : Files\\", fnameWeek);
}
