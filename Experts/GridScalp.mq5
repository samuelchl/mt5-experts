//+------------------------------------------------------------------+
//|                                                    GridScalp.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"


#include <Trade/Trade.mqh>
CTrade obj_Trade;

enum ClosureMode{
   CLOSE_BY_PROFITS,
   CLOSE_BY_POINTS
}

input ClosureMode closureMode = CLOSE_BY_POINTS;
input double inpLotSize = 0.01;
input long inpMagicNo = 122346;
input int inpTp_points = 200;
input int inpGridSize = 1000;
input double inpMultiplier = 2.0;
input int inpBreakEvenPts = 50;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   
  }
//+------------------------------------------------------------------+
