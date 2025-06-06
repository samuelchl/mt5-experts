//+------------------------------------------------------------------+
//| DailyProfitLimiter.mqh                                          |
//+------------------------------------------------------------------+

#include <SamBotUtils.mqh>
class DailyProfitLimiter
{
private:
    datetime currentDay;
    datetime firstDay;
    double startOfDayBalance;
    bool firstDayPassed;
    bool tradingStoppedToday;
    double maxProfitPercent ;

public:
    DailyProfitLimiter()
    {
        currentDay = 0;
        firstDay = 0;
        startOfDayBalance = 0.0;
        firstDayPassed = false;
        tradingStoppedToday = false;
        maxProfitPercent = 0.0;
    }

    void OnTick(bool active = true,double negSeuil = -0.005,double PosSeuil = 0.01, double trailingBuffer = 0.002)
    {
            datetime now = TimeCurrent();
          MqlDateTime timeStruct;
          TimeToStruct(now, timeStruct);
          int today = timeStruct.day;

        if(currentDay != today)
        {
            currentDay = today;
            startOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            tradingStoppedToday = false;

            if(firstDay == 0)
                firstDay = today;
            else if(!firstDayPassed && today != firstDay)
            {
                firstDayPassed = true;
                Print(" Deuxième jour atteint. Contrôle des gains/pertes activé.");
            }
        }

        if(firstDayPassed && active)
            CheckLimits(negSeuil,PosSeuil,trailingBuffer);
    }

    bool IsTradingStopped()
    {
        return tradingStoppedToday;
    }

private:
    void CheckLimits(double negSeuil = -0.005, double PosSeuil = 0.01, double trailingBuffer = 0.002)
{
    double realized = AccountInfoDouble(ACCOUNT_PROFIT);
    double floating = GetTotalFloatingProfit();
    double totalProfit = realized + floating;
    double percentChange = totalProfit / startOfDayBalance;

    // Limite de perte (toujours active)
    if (percentChange <= negSeuil)
    {
        //Print("Perte journalière de ", DoubleToString(negSeuil * 100, 2), "% atteinte. Trading stoppé.");
        tradingStoppedToday = true;
        CloseAllPositions();
        return;
    }

    // Gestion du trailing si buffer actif
    if (trailingBuffer > 0.0)
    {
        // Activation initiale
        if (maxProfitPercent == 0.0 && percentChange >= PosSeuil)
        {
            maxProfitPercent = percentChange;
            /*Print("Seuil de gain atteint : ", DoubleToString(percentChange * 100, 2), "%");
            Print("Activation du trailing profit avec buffer de ", DoubleToString(trailingBuffer * 100, 2), "%");*/
            return;
        }

        // Suivi du max et détection du repli
        if (maxProfitPercent > 0.0)
        {
            if (percentChange > maxProfitPercent)
            {
                maxProfitPercent = percentChange;
                //Print("Nouveau max journalier atteint : ", DoubleToString(maxProfitPercent * 100, 2), "%");
            }
            else if (percentChange <= maxProfitPercent - trailingBuffer)
            {
                /*Print("Repli du profit détecté. Max: ", DoubleToString(maxProfitPercent * 100, 2),
                      "% / Actuel: ", DoubleToString(percentChange * 100, 2),
                      "% → arrêt du trading.");*/
                tradingStoppedToday = true;
                CloseAllPositions();
                return;
            }
        }
    }
    else // Si pas de trailing, comportement classique
    {
        if (percentChange >= PosSeuil)
        {
            //Print("Gain journalier de ", DoubleToString(PosSeuil * 100, 2), "% atteint. Trading stoppé.");
            tradingStoppedToday = true;
            CloseAllPositions();
            return;
        }
    }
}


    double GetTotalFloatingProfit()
    {
        double total = 0.0;
        int totalPositions = PositionsTotal();

        for(int i = 0; i < totalPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket))
                total += PositionGetDouble(POSITION_PROFIT);
        }

        return total;
    }

    void CloseAllPositions()
    {
        int total = PositionsTotal();

        for(int i = total - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket))
            {
            
            
                  SamBotUtils::tradeClose(PositionGetString(POSITION_SYMBOL) , PositionGetInteger(POSITION_MAGIC) , ticket);
                // À adapter à ta fonction de fermeture réelle
                // Exemple :
                // if(PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER &&
                //    PositionGetString(POSITION_SYMBOL) == _Symbol)
                // {
                //     SamBotUtils::tradeClose(_Symbol, MAGIC_NUMBER, ticket);
                // }
            }
        }
    }
};
