//+------------------------------------------------------------------+
//|                     TrendColorLabel.mq5                          |
//|   Affiche M1|M3|M5|M15|M30|H1|H4|AVG, chacun en couleur Up/Dn    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window


#property indicator_buffers 1
#property indicator_plots   1

// propriété du plot (même si on ne l'affiche pas à l'écran)
#property indicator_label1  "GlobalTrend"
#property indicator_type1   DRAW_NONE    // pas de courbe
#property indicator_color1  clrWhite

double GlobalTrendBuffer[];  // ← le buffer qui va recevoir +1/–1


//--- inputs
input int    FastMAPeriod = 50;                   // EMA courte
input int    SlowMAPeriod = 200;                  // EMA longue
enum TrendMethod { Majority=0, Weighted=1, Hierarchy=2 };
input TrendMethod Method = Majority;              // méthode de calcul

//--- Timeframes, labels et poids (pour Weighted)
static const ENUM_TIMEFRAMES Tfs[]   = {
  PERIOD_M1, PERIOD_M3, PERIOD_M5,
  PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4
};
static const string Labels[]         = {
  "M1","M3","M5","M15","M30","H1","H4"
};
static const double Weights[]        = {
  1.0,  3.0,  5.0, 15.0, 30.0, 60.0, 240.0
};

//--- position de base et espacement
#define BASE_X       30     // marge X depuis le coin
#define BASE_Y       30     // marge Y depuis le coin
#define X_SPACING    40     // espacement horizontal entre labels

//--- couleurs
#define UP_COLOR     clrDarkGreen
#define DN_COLOR     clrRed
#define BG_COLOR     clrDarkSlateGray

//--- nom de base des objets
#define BASE_NAME    "TrendTF"

//+------------------------------------------------------------------+
//| Calcule l’EMA manuelle sur 'period' closes de 'tf'               |
//+------------------------------------------------------------------+
double GetEMA(ENUM_TIMEFRAMES tf,int period)
{
  int bars = period+1;
  double arr[];
  if(CopyClose(_Symbol, tf, 1, bars, arr) != bars)
     return(0.0);
  ArraySetAsSeries(arr, true);
  double k = 2.0/(period+1), ema = 0.0;
  // SMA initiale
  for(int i=1; i<bars; i++) ema += arr[i];
  ema /= period;
  // EMA itérée
  for(int i=0; i<period; i++) ema = arr[i]*k + ema*(1.0-k);
  return(ema);
}

//+------------------------------------------------------------------+
//| Calcule la tendance globale (+1 Up / -1 Dn)                      |
//+------------------------------------------------------------------+
int GetGlobalTrend()
{
  int    cntBull=0, cntBear=0;
  double sumW=0.0;
  int    dirH4=0, dirH1=0;

  for(int i=0; i<ArraySize(Tfs); i++)
  {
    double maF = GetEMA(Tfs[i], FastMAPeriod);
    double maS = GetEMA(Tfs[i], SlowMAPeriod);
    int dir = (maF>maS ? +1 : -1);
    // Majority
    if(dir>0) cntBull++; else cntBear++;
    // Weighted
    sumW += Weights[i]*dir;
    // Hierarchy
    if(Tfs[i]==PERIOD_H4) dirH4 = dir;
    if(Tfs[i]==PERIOD_H1) dirH1 = dir;
  }

  int globalDir = 0;
  switch(Method)
  {
    case Majority:
      if(cntBull>cntBear)      globalDir=+1;
      else if(cntBear>cntBull) globalDir=-1;
      break;
    case Weighted:
      globalDir = (sumW>0 ? +1 : -1);
      break;
    case Hierarchy:
      if(dirH4!=0)      globalDir=dirH4;
      else if(dirH1!=0) globalDir=dirH1;
      else              globalDir=(cntBull>=cntBear?+1:-1);
      break;
  }
  // par défaut Up si ex æquo
  return(globalDir==0 ? +1 : globalDir);
}

//+------------------------------------------------------------------+
//| Crée les labels pour chaque TF et pour AVG                      |
//+------------------------------------------------------------------+
void CreateLabels()
{
  // supprime d'anciens objets
  for(int i=0; i<ArraySize(Tfs); i++)
    ObjectDelete(0, BASE_NAME + "_" + Labels[i]);
  ObjectDelete(0, BASE_NAME + "_AVG");

  // crée un label par timeframe
  for(int i=0; i<ArraySize(Tfs); i++)
  {
    string name = BASE_NAME + "_" + Labels[i];
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  BASE_X + i * X_SPACING);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  BASE_Y);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   12);
    ObjectSetInteger(0, name, OBJPROP_BACK,       true);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    BG_COLOR);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
  }

  // crée le label AVG
  {
    int i = ArraySize(Tfs);
    string name = BASE_NAME + "_AVG";
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  BASE_X + i * X_SPACING);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  BASE_Y);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   12);
    ObjectSetInteger(0, name, OBJPROP_BACK,       true);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    BG_COLOR);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
  }
}

//+------------------------------------------------------------------+
//| Met à jour le texte et la couleur de chaque label               |
//+------------------------------------------------------------------+
int UpdateLabels()
{
  int globalDir = GetGlobalTrend();

  // pour chaque timeframe
  for(int i=0; i<ArraySize(Tfs); i++)
  {
    double maF = GetEMA(Tfs[i], FastMAPeriod);
    double maS = GetEMA(Tfs[i], SlowMAPeriod);
    int dir    = (maF>maS ? +1 : -1);

    string name = BASE_NAME + "_" + Labels[i];
    // affichage "M1|" "M3|" ... 
    string txt  = Labels[i] + "|";
    color  col  = (dir>0 ? UP_COLOR : DN_COLOR);

    ObjectSetString(0, name, OBJPROP_TEXT,  txt);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
  }

  // mise à jour du label AVG
  {
    string name = BASE_NAME + "_AVG";
    string txt  = "AVG";
    color  col  = (globalDir>0 ? UP_COLOR : DN_COLOR);

    ObjectSetString(0, name, OBJPROP_TEXT,  txt);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
  }
  
  return globalDir;
}

//+------------------------------------------------------------------+
//| Initialisation                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
  CreateLabels();
  UpdateLabels();
  
  //--- lier le buffer 0
SetIndexBuffer(0, GlobalTrendBuffer, INDICATOR_DATA);
  
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Recalcul à chaque tick                                          |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &t[], const double &o[],
                const double &h[], const double &l[],
                const double &c[], const long &tv[],
                const long &v[], const int &spr[])
{
  int dir = UpdateLabels();
  // 1) Position de la bougie “courante” dans l’array (barre la plus récente)
   int idx = rates_total - 1;
   
   // 3) Écriture dans le buffer
   GlobalTrendBuffer[idx] = (double)dir;
   
  return(rates_total);
}
//+------------------------------------------------------------------+
