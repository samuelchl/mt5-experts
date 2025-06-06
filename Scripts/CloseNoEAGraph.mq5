//+------------------------------------------------------------------+
//| Script pour fermer tous les graphiques sans Expert Advisor      |
//+------------------------------------------------------------------+
#include <ChartObjects\ChartObjectsTxtControls.mqh>
#property script_show_inputs

void OnStart()
{
  // Parcours de tous les ID de graphiques
  for(long id = ChartFirst(); id != -1; id = ChartNext(id))
  {
    // Si aucun Expert Advisor n’est attaché à ce graphique
    if(StringLen(ChartGetString(id, CHART_EXPERT_NAME)) == 0)
    {
      // Fermer la fenêtre
      ChartClose(id);
    }
  }
}
