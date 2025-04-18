#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

//--- Classe stateless contenant toutes les fonctions
class SamBotUtils
{
public:
   // 1) Fonction de rejet (inspirée de Pine)
   static bool isRejet3WMA(double fast0, double fast1,
                           double slow0, double slow1,
                           double trend,
                           string sens, double seuil)
   {
      double diffNow  = fast0 - slow0;
      double diffPrev = fast1 - slow1;
      double ecart    = MathAbs(diffNow);
      bool proche     = ecart <= MathAbs(slow0 * seuil / 100.0);

      bool rejet = false;
      if(sens == "up")
         rejet = (diffPrev < 0 && diffNow > 0 && fast0 > trend && slow0 > trend);
      else if(sens == "down")
         rejet = (diffPrev > 0 && diffNow < 0 && fast0 < trend && slow0 < trend);

      return rejet && proche;
   }
   
      // Fonction de rejet (inspirée de Pine)
   static bool isRejet3WMARenforce(double fast0, double fast1, double slow0, double slow1, double trend,
                    string sens, double seuil)
   {
      double diffNow  = fast0 - slow0;
      double diffPrev = fast1 - slow1;
      double ecart    = MathAbs(diffNow);
      bool proche     = ecart <= MathAbs(slow0 * seuil / 100.0);
   
      bool rejet = false;
      if(sens == "up")
         rejet = (diffPrev < 0 && diffNow > 0 && fast0 > trend && slow0 > trend);
      else if(sens == "down")
         rejet = (diffPrev > 0 && diffNow < 0 && fast0 < trend && slow0 < trend);
   
      return rejet && proche;
   }


   // 2) Vérifie s'il existe une position ouverte pour ce MAGIC/SYM
   static bool IsTradeOpen(const string symbol, const ulong MAGIC_NUMBER)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong position_ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(position_ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER
               && PositionGetString(POSITION_SYMBOL) == symbol )
               return true;
         }
      }
      return false;
   }

   // 3) Calcul de la taille de lot
   static double CalculerLotSize(const string symbol,
                                 double slPips,
                                 bool   GestionDynamiqueLot,
                                 double LotFixe,
                                 double RisqueParTradePct)
   {
      if(!GestionDynamiqueLot)
         return(LotFixe);

      double valeurTick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tailleTick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);

      double montantRisque = balance * RisqueParTradePct / 100.0;
      double lot = montantRisque / (slPips * (valeurTick / tailleTick));

      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMax(minLot, MathMin(maxLot, lot));
      return NormalizeDouble(lot, 2);
   }

   // 4) Ouverture d’un ordre
   static void tradeOpen(const string      symbol,
                         const ulong       MAGIC_NUMBER,
                         ENUM_ORDER_TYPE   type,
                         double            sl_pct,
                         double            tp_pct,
                         bool              GestionDynamiqueLot,
                         double            LotFixe,
                         double            RisqueParTradePct)
   {
      double price = SymbolInfoDouble(symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
      double sl    = price - (type==ORDER_TYPE_BUY?1:-1)*price*sl_pct/100.0;
      double tp    = price + (type==ORDER_TYPE_BUY?1:-1)*price*tp_pct/100.0;
      if(type == ORDER_TYPE_SELL && tp < 0)
         tp = 1.0;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = symbol;
      request.magic    = MAGIC_NUMBER;
      request.type     = type;
      double slPips    = MathAbs(price - sl) / SymbolInfoDouble(symbol, SYMBOL_POINT) / 10.0;
      request.volume   = CalculerLotSize(symbol, slPips, GestionDynamiqueLot, LotFixe, RisqueParTradePct);
      request.price    = price;
      request.sl       = NormalizeDouble(sl, _Digits);
      request.tp       = NormalizeDouble(tp, _Digits);
      request.deviation= 10;

      if(!OrderSend(request, result))
         Print("Erreur ouverture ordre : ", result.comment);
   }

   // 5) Fermeture complète d’un ticket
   static void tradeClose(const string symbol,
                          const ulong  MAGIC_NUMBER,
                          const ulong  ticket)
   {
      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      if(!PositionSelectByTicket(ticket))
         return;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double price = SymbolInfoDouble(symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);

      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = symbol;
      request.position = ticket;
      request.volume   = PositionGetDouble(POSITION_VOLUME);
      request.price    = price;
      request.type     = (type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      request.deviation= 10;

      if(!OrderSend(request, result))
         Print("Erreur fermeture ordre : ", result.comment);
   }

   // 6) Trailing Stop
   static void GererTrailingStop(const string symbol,
                                 const ulong  MAGIC_NUMBER,
                                 bool          utiliser_trailing_stop,
                                 double        trailing_stop_pct)
   {
      if(!utiliser_trailing_stop) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;

         if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER
            || PositionGetString(POSITION_SYMBOL) != symbol)
            continue;

         double prix_actuel_bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double prix_actuel_ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         double prix_position   = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl_actuel       = PositionGetDouble(POSITION_SL);
         ENUM_POSITION_TYPE type= (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         double nouveau_sl;

         if(type == POSITION_TYPE_BUY)
            nouveau_sl = prix_actuel_bid - (prix_actuel_bid * trailing_stop_pct / 100.0);
         else
            nouveau_sl = prix_actuel_ask + (prix_actuel_ask * trailing_stop_pct / 100.0);

         if((type == POSITION_TYPE_BUY  && nouveau_sl > prix_position && (nouveau_sl > sl_actuel || sl_actuel == 0)) ||
            (type == POSITION_TYPE_SELL && nouveau_sl < prix_position && (nouveau_sl < sl_actuel || sl_actuel == 0)))
            ModifierSL(symbol, ticket, nouveau_sl);
      }
   }

   // 7) Fonction pour modifier le SL
   static void ModifierSL(const string symbol,
                          ulong  ticket,
                          double nouveau_sl)
   {
      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action   = TRADE_ACTION_SLTP;
      request.symbol   = symbol;
      request.position = ticket;
      request.sl       = NormalizeDouble(nouveau_sl, _Digits);
      request.tp       = PositionGetDouble(POSITION_TP);

      if(!OrderSend(request, result))
         Print("Erreur Trailing Stop : ", result.comment);
   }

   // 8) Prises profit partielles
   static void GererPrisesProfitsPartielles(const string symbol,
                                            const ulong  MAGIC_NUMBER,
                                            bool          utiliser_prise_profit_partielle,
                                            double        tranche_prise_profit_pct,
                                            int           nb_tp_partiel)
   {
      if(!utiliser_prise_profit_partielle)
         return;

      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      int    prec    = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

      int totalPos = PositionsTotal();
      for(int i = totalPos - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;

         if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER
            || PositionGetString(POSITION_SYMBOL) != symbol)
            continue;

         double prixOuverture  = PositionGetDouble(POSITION_PRICE_OPEN);
         double prixTPFinal    = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volumeInitial  = PositionGetDouble(POSITION_VOLUME);
         double volumeRestant  = volumeInitial;

         for(int n = 1; n <= nb_tp_partiel; n++)
         {
            double pct     = tranche_prise_profit_pct * n;
            double tpLevel = (typePos == POSITION_TYPE_BUY)
                              ? prixOuverture + pct * (prixTPFinal - prixOuverture)
                              : prixOuverture - pct * (prixOuverture - prixTPFinal);
            double prixActu = (typePos == POSITION_TYPE_BUY)
                              ? SymbolInfoDouble(symbol, SYMBOL_BID)
                              : SymbolInfoDouble(symbol, SYMBOL_ASK);

            if((typePos == POSITION_TYPE_BUY  && prixActu >= tpLevel) ||
               (typePos == POSITION_TYPE_SELL && prixActu <= tpLevel))
            {
               double volToClose = NormalizeDouble(volumeInitial * tranche_prise_profit_pct, prec);
               if(volToClose < minLot)
                  volToClose = minLot;
               if(volumeRestant - volToClose < minLot)
                  volToClose = volumeRestant - minLot;
               if(volToClose >= minLot)
               {
                  FermerPartiellement(symbol, ticket, volToClose);
                  volumeRestant -= volToClose;
               }
            }
         }
      }
   }


   // Dans SamBotUtils.mqh, remplacez la méthode GererPrisesProfitsPartielles par : 




   // 9) Fonction pour fermer partiellement une position
   static void FermerPartiellement(const string symbol,
                                   ulong        ticket,
                                   double       volume_a_fermer)
   {
      if(volume_a_fermer < 0.01)
         return;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      if(!PositionSelectByTicket(ticket))
         return;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double prix = SymbolInfoDouble(symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);

      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = symbol;
      request.position = ticket;
      request.volume   = NormalizeDouble(volume_a_fermer, 2);
      request.price    = prix;
      request.type     = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.deviation= 10;

      if(!OrderSend(request, result))
         Print("Erreur prise profit partielle : ", result.comment);
   }
   
   // 8) Prises profit partielles (ancienne logique, sans décrémenter volume_restant)
static void GererPrisesProfitsPartielles2(const string symbol,
                                         const ulong  MAGIC_NUMBER,
                                         bool          utiliser_prise_profit_partielle,
                                         double        tranche_prise_profit_pct,
                                         int           nb_tp_partiel)
{
   if(!utiliser_prise_profit_partielle)
      return;

   int totalPos = PositionsTotal();
   for(int idx = totalPos - 1; idx >= 0; idx--)
   {
      ulong ticket = PositionGetTicket(idx);
      if(!PositionSelectByTicket(ticket))
         continue;

      // filtrage magic + symbole
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER ||
         PositionGetString (POSITION_SYMBOL)!= symbol)
         continue;

      double prixOuverture = PositionGetDouble(POSITION_PRICE_OPEN);
      double prixTPFinal   = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)
                                   PositionGetInteger(POSITION_TYPE);
      double volumeInitial = PositionGetDouble(POSITION_VOLUME);
      double volumeRestant = volumeInitial;

      // cours actuel
      double prixActuBid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double prixActuAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);

      // boucle sur chaque tranche
      for(int n = 1; n <= nb_tp_partiel; n++)
      {
         double niveauPct = tranche_prise_profit_pct * n;

         if(typePos == POSITION_TYPE_BUY)
         {
            double tpLevel = prixOuverture + niveauPct * (prixTPFinal - prixOuverture);
            // condition identique à l'ancienne
            if(prixActuBid >= tpLevel
               && volumeRestant >= volumeInitial * (1.0 - tranche_prise_profit_pct * n))
            {
               // volume à fermer = fraction fixe du volume initial
               double volToClose = volumeInitial * tranche_prise_profit_pct;
               FermerPartiellement2(symbol, ticket, volToClose);
            }
         }
         else // SELL
         {
            double tpLevel = prixOuverture - niveauPct * (prixOuverture - prixTPFinal);
            if(prixActuAsk <= tpLevel
               && volumeRestant >= volumeInitial * (1.0 - tranche_prise_profit_pct * n))
            {
               double volToClose = volumeInitial * tranche_prise_profit_pct;
               FermerPartiellement2(symbol, ticket, volToClose);
            }
         }
      }
   }
}


// 9) Fonction pour fermer partiellement une position (ancienne logique + minLot)
static void FermerPartiellement2(const string symbol,
                                ulong        ticket,
                                double       volume_a_fermer)
{
   // Récupération du lot minimum et du pas
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   // Précision décimale à appliquer
   int    prec    = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

   // Si la tranche demandée est inférieure au lot min, on ferme minLot
   double volToClose = volume_a_fermer < minLot ? minLot : volume_a_fermer;
   // On normalise au pas
   volToClose = NormalizeDouble(volToClose, prec);

   // Si après arrondi on est sous le lot min, on renonce
   if(volToClose < minLot)
      return;

   // Sélection de la position
   if(!PositionSelectByTicket(ticket))
      return;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double prix = SymbolInfoDouble(
      symbol,
      type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK
   );

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = symbol;
   request.position  = ticket;
   request.volume    = volToClose;
   request.price     = prix;
   request.type      = (type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.deviation = 10;

   if(!OrderSend(request, result))
      Print("Erreur prise profit partielle : ", result.comment);
}

// 8) Prises profit partielles (ancienne logique, sans état interne)
static void GererPrisesProfitsPartielles3(
   const string symbol,
   const ulong  MAGIC_NUMBER,
   bool          utiliser_prise_profit_partielle,
   double        tranche_prise_profit_pct,
   int           nb_tp_partiel)
{
   if(!utiliser_prise_profit_partielle)
      return;

   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   int    prec    = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

   int totalPos = PositionsTotal();
   for(int i = totalPos - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      // filtrage magic + symbole
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER ||
         PositionGetString (POSITION_SYMBOL)!= symbol)
         continue;

      double prixOuverture = PositionGetDouble(POSITION_PRICE_OPEN);
      double prixTPFinal   = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE typePos      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volumeInitial            = PositionGetDouble(POSITION_VOLUME);
      double volumeRestant            = volumeInitial;

      for(int n = 1; n <= nb_tp_partiel; n++)
      {
         double pct = tranche_prise_profit_pct * n;
         double tpLevel = (typePos == POSITION_TYPE_BUY)
                          ? prixOuverture + pct * (prixTPFinal - prixOuverture)
                          : prixOuverture - pct * (prixOuverture - prixTPFinal);
         
         double prixActu = (typePos == POSITION_TYPE_BUY)
                           ? SymbolInfoDouble(symbol, SYMBOL_BID)
                           : SymbolInfoDouble(symbol, SYMBOL_ASK);

         if((typePos == POSITION_TYPE_BUY  && prixActu >= tpLevel) ||
            (typePos == POSITION_TYPE_SELL && prixActu <= tpLevel))
         {
            // volume fixe = fraction du volume initial
            double volToClose = NormalizeDouble(volumeInitial * tranche_prise_profit_pct, prec);
            if(volToClose < minLot)
               volToClose = minLot;
            if(volumeRestant - volToClose < minLot)
               volToClose = volumeRestant - minLot;
            if(volToClose >= minLot)
            {
               FermerPartiellement3(symbol, ticket, volToClose);
               volumeRestant -= volToClose;
            }
         }
      }
   }
}

// 9) Fermer partiellement (ancienne logique, normalisation à 2 décimales)
static void FermerPartiellement3(
   const string symbol,
   ulong        ticket,
   double       volume_a_fermer)
{
   // seuil rigide 0.01
   if(volume_a_fermer < 0.01)
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double prix = SymbolInfoDouble(
      symbol,
      type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK
   );

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = symbol;
   request.position  = ticket;
   request.volume    = NormalizeDouble(volume_a_fermer, 2);
   request.price     = prix;
   request.type      = (type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.deviation = 10;

   if(!OrderSend(request, result))
      Print("Erreur prise profit partielle : ", result.comment);
}

};



