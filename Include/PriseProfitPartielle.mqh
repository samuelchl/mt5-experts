enum PriseProfitPartielleMode
{
    MODE_ACTUEL = 0,
    MODE_VOLUME_FIXE,
    MODE_NIVEAUX_PRIX_SEULS,
    MODE_VOLUME_PROGRESSIF
};

class PriseProfitPartielle
{
private:
    string             m_symbol;
    ulong              m_magicNumber;
    bool               m_utiliser;
    double             m_tranchePct;
    int                m_nbTpPartiel;
    PriseProfitPartielleMode m_mode;
    bool               m_mettreSLBreakeven;
    bool               m_closeIfVolumeLow;
    double             m_percentToCloseTrade;

    double GetMinLot() { return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN); }
    double GetLotStep() { return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP); }
    int    GetPrecision() { return (int)MathRound(-MathLog(GetLotStep())/MathLog(10.0)); }

public:
    // Constructeur
    void Init(const string symbol, ulong magicNumber,
              bool utiliserPriseProfitPartielle, double tranchePct,
              int nbTpPartiel, PriseProfitPartielleMode mode,
              bool mettreSLBreakeven = false,
              bool closeIfVolumeLow = false,
              double percentToCloseTrade = 0.20)
    {
        m_symbol = symbol;
        m_magicNumber = magicNumber;
        m_utiliser = utiliserPriseProfitPartielle;
        m_tranchePct = tranchePct;
        m_nbTpPartiel = nbTpPartiel;
        m_mode = mode;
        m_mettreSLBreakeven = mettreSLBreakeven;
        m_closeIfVolumeLow = closeIfVolumeLow;
        m_percentToCloseTrade = percentToCloseTrade;
    }

    // Méthode publique principale à appeler à chaque tick ou intervalle
    void Gerer()
    {
        if(!m_utiliser)
            return;

        switch(m_mode)
        {
            case MODE_ACTUEL:
                GererActuel();
                break;
            case MODE_VOLUME_FIXE:
                GererVolumeFixe();
                break;
            case MODE_NIVEAUX_PRIX_SEULS:
                GererNiveauxPrixSeuls();
                break;
            case MODE_VOLUME_PROGRESSIF:
                GererVolumeProgressif();
                break;
            default:
                Print("Mode prise partielle inconnu");
                break;
        }
    }

private:
    void GererActuel()
    {
        // Exemple simplifié, adapte selon ta fonction actuelle
        int totalPos = PositionsTotal();
        for(int i = totalPos - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(!PositionSelectByTicket(ticket))
                continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber
               || PositionGetString(POSITION_SYMBOL) != m_symbol)
                continue;

            double prixOuverture  = PositionGetDouble(POSITION_PRICE_OPEN);
            double prixTPFinal    = PositionGetDouble(POSITION_TP);
            ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double volumeInitial  = PositionGetDouble(POSITION_VOLUME);
            double volumeRestant  = volumeInitial;

            double slActuel = PositionGetDouble(POSITION_SL);

            double minLot  = GetMinLot();
            int prec      = GetPrecision();

            double prixActu = (typePos == POSITION_TYPE_BUY)
                              ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                              : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

            for(int n = 1; n <= m_nbTpPartiel; n++)
            {
                double pct     = m_tranchePct * n;
                double tpLevel = (typePos == POSITION_TYPE_BUY)
                                  ? prixOuverture + pct * (prixTPFinal - prixOuverture)
                                  : prixOuverture - pct * (prixOuverture - prixTPFinal);

                if((typePos == POSITION_TYPE_BUY  && prixActu >= tpLevel) ||
                   (typePos == POSITION_TYPE_SELL && prixActu <= tpLevel))
                {
                    double volToClose = NormalizeDouble(volumeInitial * m_tranchePct, prec);
                    if(volToClose < minLot)
                        volToClose = minLot;
                    if(volumeRestant - volToClose < minLot)
                        volToClose = volumeRestant - minLot;

                    if(volToClose >= minLot)
                    {
                        FermerPartiellement(m_symbol, ticket, volToClose);
                        volumeRestant -= volToClose;

                        AjusterStopLossAuBreakeven(m_symbol, ticket, prixOuverture, typePos, slActuel, m_mettreSLBreakeven);
                    }
                }
            }
        }
    }

   void GererVolumeFixe()
   {
       int totalPos = PositionsTotal();
       double minLot  = GetMinLot();
       int prec      = GetPrecision();
   
       for(int i = totalPos - 1; i >= 0; i--)
       {
           ulong ticket = PositionGetTicket(i);
           if(!PositionSelectByTicket(ticket))
               continue;
   
           if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber
              || PositionGetString(POSITION_SYMBOL) != m_symbol)
               continue;
   
           double volumeInitial  = PositionGetDouble(POSITION_VOLUME);
           double slActuel       = PositionGetDouble(POSITION_SL);
           ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
           // Ici, on peut récupérer le volume restant (actuel), mais souvent c'est le volume actuel de la position
           double volumeRestant = volumeInitial;
   
           // Calcul du volume à fermer : fraction fixe de volume initial
           double volToClose = NormalizeDouble(volumeInitial * m_tranchePct, prec);
   
           // Ne pas fermer moins que le lot minimum
           if(volToClose < minLot)
               volToClose = minLot;
   
           // S'assurer qu'après fermeture, il reste au moins le lot minimum (sinon fermer complètement)
           if(volumeRestant - volToClose < minLot)
               volToClose = volumeRestant;
   
           if(volToClose >= minLot)
           {
               FermerPartiellement(m_symbol, ticket, volToClose);
               PrintFormat("Fermeture partielle de %.2f lots sur la position %d (mode volume fixe)", volToClose, ticket);
   
               // Ajuster SL si demandé
               double prixOuverture  = PositionGetDouble(POSITION_PRICE_OPEN);
               AjusterStopLossAuBreakeven(m_symbol, ticket, prixOuverture, typePos, slActuel, m_mettreSLBreakeven);
           }
       }
   }


   void GererNiveauxPrixSeuls()
{
    int totalPos = PositionsTotal();
    double minLot  = GetMinLot();
    int prec      = GetPrecision();

    for(int i = totalPos - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket))
            continue;

        if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber
           || PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

        double prixOuverture  = PositionGetDouble(POSITION_PRICE_OPEN);
        double prixTPFinal    = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double volumeInitial  = PositionGetDouble(POSITION_VOLUME);
        double volumeRestant  = volumeInitial;

        // Récupérer les tranches déjà fermées via le commentaire, format: "tp_taken=1,2,3"
        string comment = PositionGetString(POSITION_COMMENT);
        int takenPos = StringFind(comment, "tp_taken=");
        string takenList = "";
        if(takenPos >= 0)
        {
            int startIndex = takenPos + StringLen("tp_taken=");
            takenList = StringSubstr(comment, startIndex);
        }

        int takenTranches[];
        if(takenList != "")
        {
            StringSplit(takenList, ',', takenTranches);
        }

        double prixActu = (typePos == POSITION_TYPE_BUY)
                          ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                          : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

        for(int n = 1; n <= m_nbTpPartiel; n++)
        {
            // Vérifier si tranche n est déjà prise
            bool trancheDejaPrise = false;
            for(int t=0; t < ArraySize(takenTranches); t++)
            {
                if(takenTranches[t] == n)
                {
                    trancheDejaPrise = true;
                    break;
                }
            }
            if(trancheDejaPrise)
                continue;

            double pct     = m_tranchePct * n;
            double tpLevel = (typePos == POSITION_TYPE_BUY)
                              ? prixOuverture + pct * (prixTPFinal - prixOuverture)
                              : prixOuverture - pct * (prixOuverture - prixTPFinal);

            if((typePos == POSITION_TYPE_BUY  && prixActu >= tpLevel) ||
               (typePos == POSITION_TYPE_SELL && prixActu <= tpLevel))
            {
                double volToClose = NormalizeDouble(volumeInitial * m_tranchePct, prec);
                if(volToClose < minLot)
                    volToClose = minLot;
                if(volumeRestant - volToClose < minLot)
                    volToClose = volumeRestant - minLot;

                if(volToClose >= minLot)
                {
                    // Préparer commentaire précis pour la fermeture partielle
                    string com = StringFormat("PrisePartielle tranche %d", n);

                    // Fermer partiellement avec commentaire
                    FermerPartiellement(m_symbol, ticket, volToClose, com);
                    volumeRestant -= volToClose;

                    // Mettre à jour la liste des tranches prises dans le commentaire de la position
                    string newComment = comment;
                    if(takenList == "")
                        newComment += " tp_taken=" + IntegerToString(n);
                    else
                        newComment += "," + IntegerToString(n);

                    // Modifier la position pour mettre à jour le commentaire
                    if(!PositionModify(ticket, 0, 0, 0, 0, newComment))
                        Print("Erreur mise à jour commentaire position pour tranches prises");

                    // Ajuster le SL au breakeven si besoin
                    AjusterStopLossAuBreakeven(m_symbol, ticket, prixOuverture, typePos, PositionGetDouble(POSITION_SL), m_mettreSLBreakeven);
                }
                break; // On ne prend qu’une tranche par appel
            }
        }
    }
}



    void GererVolumeProgressif()
    {
        // Implémenter la logique pour prise partielle avec volume progressif selon prix
    }

    // Exemples de fonctions utilitaires à implémenter / adapter
    void FermerPartiellement(string symbol, ulong ticket, double volume)
    {
        // Appel à ta fonction de fermeture partielle ici
    }

    void AjusterStopLossAuBreakeven(string symbol, ulong ticket, double prixOuverture, ENUM_POSITION_TYPE typePos, double slActuel, bool activer)
    {
        // Appel à ta fonction d'ajustement SL ici
    }
    
    
       // 9) Fonction pour fermer partiellement une position, avec commentaire optionnel
   static void FermerPartiellement(const string symbol,
                                   ulong        ticket,
                                   double       volume_a_fermer,
                                   string       commentaire = "")
   {
       if(volume_a_fermer < 0.01)
           return;
   
       MqlTradeRequest request = {};
       MqlTradeResult  result  = {};
   
       if(!PositionSelectByTicket(ticket))
           return;
   
       ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
       double prix = SymbolInfoDouble(symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);
   
       request.action    = TRADE_ACTION_DEAL;
       request.symbol    = symbol;
       request.position  = ticket;
       request.volume    = NormalizeDouble(volume_a_fermer, 2);
       request.price     = prix;
       request.type      = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
       request.deviation = 10;
   
       if(commentaire != "")
           request.comment = commentaire;
   
       if(!OrderSend(request, result))
           Print("Erreur prise profit partielle : ", result.comment);
   }

};
