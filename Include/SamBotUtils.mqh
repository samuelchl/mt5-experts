//─────────────────────────────────────────────────────────────────────────────
// SamBotUtils.mqh
//─────────────────────────────────────────────────────────────────────────────
#ifndef __SAM_BOT_UTILS_MQH__
#define __SAM_BOT_UTILS_MQH__

#include <Object.mqh>                 // pour CObject
#include <Trade/PositionInfo.mqh>     // pour PositionGet…
#include <Trade/SymbolInfo.mqh>       // pour SymbolInfoDouble
#include <Trade/Trade.mqh>            // pour OrderSend, MqlTradeRequest/Result

class SamBotUtils
{
private:
   // paramètres de prise de profit partielle
   string   m_symbol;
   ulong    m_magic;
   double   m_tranchePct;
   int      m_nbTpPartiel;
   bool     m_usePartial;
   // autres paramètres
   bool     m_gestionDynamiqueLot;
   double   m_lotFixe;
   double   m_risqueParTradePct;
   bool     m_useTrailingStop;
   double   m_trailingStopPct;

public:
   // Constructeur
   SamBotUtils(
     const string symbol,
     const ulong  magic,
     const double tranchePct,
     const int    nbTpPartiel,
     const bool   usePartial,
     const bool   gestionDynamiqueLot,
     const double lotFixe,
     const double risqueParTradePct,
     const bool   useTrailingStop,
     const double trailingStopPct
   )
   : m_symbol(symbol),
     m_magic(magic),
     m_tranchePct(tranchePct),
     m_nbTpPartiel(nbTpPartiel),
     m_usePartial(usePartial),
     m_gestionDynamiqueLot(gestionDynamiqueLot),
     m_lotFixe(lotFixe),
     m_risqueParTradePct(risqueParTradePct),
     m_useTrailingStop(useTrailingStop),
     m_trailingStopPct(trailingStopPct)
   {}

   // 1) Fermeture partielle
   void FermerPartiellement(double volume_a_fermer)
   {
      double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      int    precLot = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

      if(volume_a_fermer < minLot) 
         return;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double price = SymbolInfoDouble(
                       m_symbol,
                       type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK
                     );

      request.action        = TRADE_ACTION_DEAL;
      request.symbol        = m_symbol;
      request.position      = PositionGetInteger(POSITION_TICKET);
      request.volume        = NormalizeDouble(volume_a_fermer, precLot);
      request.price         = price;
      request.type          = (type == POSITION_TYPE_BUY)
                              ? ORDER_TYPE_SELL
                              : ORDER_TYPE_BUY;
      request.deviation     = 10;
      request.type_filling  = ORDER_FILLING_FOK;
      request.type_time     = ORDER_TIME_GTC;

      if(!OrderSend(request, result))
         Print("Erreur prise profit partielle : ", result.comment);
   }

   // 2) Ouverture d’un ordre
   void TradeOpen(ENUM_ORDER_TYPE type, double sl_pct, double tp_pct)
   {
      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      double price = SymbolInfoDouble(
                       m_symbol,
                       type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID
                     );
      double sl = price - (type==ORDER_TYPE_BUY ? 1 : -1)*price*sl_pct/100.0;
      double tp = price + (type==ORDER_TYPE_BUY ? 1 : -1)*price*tp_pct/100.0;
      if(type == ORDER_TYPE_SELL && tp < 0) 
         tp = 1.0;

      request.action        = TRADE_ACTION_DEAL;
      request.symbol        = m_symbol;
      request.magic         = m_magic;
      request.type          = type;
      // calcul du volume selon SL en pips
      double slPips         = MathAbs(price - sl)
                              / SymbolInfoDouble(m_symbol, SYMBOL_POINT)
                              / 10.0;
      request.volume        = CalculerLotSize(slPips);
      request.price         = price;
      request.sl            = NormalizeDouble(sl, _Digits);
      request.tp            = NormalizeDouble(tp, _Digits);
      request.deviation     = 10;
      request.type_filling  = ORDER_FILLING_FOK;
      request.type_time     = ORDER_TIME_GTC;

      if(!OrderSend(request, result))
         Print("Erreur ouverture ordre : ", result.comment);
   }

   // 3) Fermeture complète d’un ticket
   void TradeClose(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
         return;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double price = SymbolInfoDouble(
                       m_symbol,
                       type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK
                     );

      request.action        = TRADE_ACTION_DEAL;
      request.symbol        = m_symbol;
      request.position      = ticket;
      request.volume        = PositionGetDouble(POSITION_VOLUME);
      request.price         = price;
      request.type          = (type == POSITION_TYPE_BUY)
                              ? ORDER_TYPE_SELL
                              : ORDER_TYPE_BUY;
      request.deviation     = 10;
      request.type_filling  = ORDER_FILLING_FOK;
      request.type_time     = ORDER_TIME_GTC;

      if(!OrderSend(request, result))
         Print("Erreur fermeture ordre : ", result.comment);
   }

   // 4) Calcul de lot size
   double CalculerLotSize(double slPips)
   {
      if(!m_gestionDynamiqueLot)
         return(m_lotFixe);

      double valeurTick   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tailleTick   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
      double montantRisque= balance * m_risqueParTradePct / 100.0;
      double lot = montantRisque
                   / (slPips * (valeurTick / tailleTick));

      double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMax(minLot, MathMin(maxLot, lot));
      return NormalizeDouble(lot, 2);
   }

   // 5) Modification de Stop Loss
   void ModifierSL(ulong ticket, double nouveau_sl)
   {
      if(!PositionSelectByTicket(ticket))
         return;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action        = TRADE_ACTION_SLTP;
      request.symbol        = m_symbol;
      request.position      = ticket;
      request.sl            = NormalizeDouble(nouveau_sl, _Digits);
      request.tp            = PositionGetDouble(POSITION_TP);
      request.type_filling  = ORDER_FILLING_FOK;
      request.type_time     = ORDER_TIME_GTC;

      if(!OrderSend(request, result))
         Print("Erreur Trailing Stop : ", result.comment);
   }

   // 6) Trailing Stop
   void GererTrailingStop()
   {
      if(!m_useTrailingStop)
         return;

      int totalPos = PositionsTotal();
      for(int i = totalPos - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic
            || PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         ENUM_POSITION_TYPE type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double prix_actuel_bid       = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double prix_actuel_ask       = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double prix_position         = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl_actuel             = PositionGetDouble(POSITION_SL);

         double nouveau_sl = 0;
         if(type == POSITION_TYPE_BUY)
         {
            nouveau_sl = prix_actuel_bid - (prix_actuel_bid * m_trailingStopPct / 100.0);
            if(nouveau_sl > prix_position && (nouveau_sl > sl_actuel || sl_actuel == 0))
               ModifierSL(ticket, nouveau_sl);
         }
         else // SELL
         {
            nouveau_sl = prix_actuel_ask + (prix_actuel_ask * m_trailingStopPct / 100.0);
            if(nouveau_sl < prix_position && (nouveau_sl < sl_actuel || sl_actuel == 0))
               ModifierSL(ticket, nouveau_sl);
         }
      }
   }

   // 7) Prises profit partielles (nouvelle logique)
   void GererPrisesProfitsPartielles()
   {
      if(!m_usePartial)
         return;

      double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      int    prec    = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

      int totalPos = PositionsTotal();
      for(int i = totalPos - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic
            || PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         double prixOuvert    = PositionGetDouble(POSITION_PRICE_OPEN);
         double prixTPFinal   = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE typePos     = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volumeInitial = PositionGetDouble(POSITION_VOLUME);
         double volumeRestant = volumeInitial;

         for(int n = 1; n <= m_nbTpPartiel; n++)
         {
            double pct     = m_tranchePct * n;
            double tpLevel = (typePos == POSITION_TYPE_BUY)
                              ? prixOuvert + pct * (prixTPFinal - prixOuvert)
                              : prixOuvert - pct * (prixOuvert - prixTPFinal);

            double prixActu = (typePos == POSITION_TYPE_BUY)
                              ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                              : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

            if(((typePos == POSITION_TYPE_BUY)  && prixActu >= tpLevel) ||
               ((typePos == POSITION_TYPE_SELL) && prixActu <= tpLevel))
            {
               // volume prévu par tranche
               double volToClose = NormalizeDouble(volumeInitial * m_tranchePct, prec);
               // on garantit au moins le lot min
               if(volToClose < minLot)
                  volToClose = minLot;
               // on ne ferme pas plus que ce qu'il reste
               if(volToClose > volumeRestant)
                  volToClose = volumeRestant;

               // si rien à fermer, on sort
               if(volToClose < minLot)
                  continue;

               FermerPartiellement(volToClose);
               volumeRestant -= volToClose;
            }
         }
      }
      
    }

   // 8) Vérifie s'il existe au moins une position ouverte pour ce MAGIC/SYM
   bool IsTradeOpen() const
   {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetInteger(POSITION_MAGIC) == m_magic
            && PositionGetString(POSITION_SYMBOL) == m_symbol)
            return true;
      }
      return false;
   }
};

#endif // __SAM_BOT_UTILS_MQH__
