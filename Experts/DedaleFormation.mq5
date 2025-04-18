//+------------------------------------------------------------------+
//|                                              DédaleFormation.mq5 |
//|                                   Copyright 2024, Brieuc Leysour |
//|                          https://www.youtube.com/@LETRADERPAUVRE |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Brieuc Leysour"
#property link      "https://www.youtube.com/@LETRADERPAUVRE"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Fichiers include                                                 |
//+------------------------------------------------------------------+

#include <Math/Stat/Math.mqh>
#include <Trade/Trade.mqh>


//+------------------------------------------------------------------+
//| Classes                                                          |       
//+------------------------------------------------------------------+
CTrade trade;






enum RISK_MODE_ENUM{


   Pourcentage,
   Argent,
   Fixe,


};


//+------------------------------------------------------------------+
//| Paramètres / variables d'entrée                                  |
//+------------------------------------------------------------------+
input group "PARAMÈTRES POINT PIVOTS"
input ENUM_TIMEFRAMES PIVOT_TIMEFRAME = PERIOD_W1;    // Timeframe points pivots
input int PIVOT_NUMBER = 2;                           // Nombre de points pivots
input int TARGET_PROBABILITY = 50;                    // Probabilité de SL


input group "PARAMÈTRES TDI"
input int RSI_PERIOD = 21;                            // Période RSI
input ENUM_APPLIED_PRICE RSI_APP_PRICE = PRICE_CLOSE; // Méthode de calcul du RSI
input ENUM_TIMEFRAMES TDI_TIMEFRAME0 = PERIOD_M15;    // Timeframe TDI 0
input ENUM_TIMEFRAMES TDI_TIMEFRAME1 = PERIOD_M30;    // Timeframe TDI 1
input ENUM_TIMEFRAMES TDI_TIMEFRAME2 = PERIOD_H1;     // Timeframe TDI 2
input ENUM_TIMEFRAMES TDI_TIMEFRAME3 = PERIOD_H4;     // Timeframe TDI 3
input ENUM_TIMEFRAMES TDI_TIMEFRAME4 = PERIOD_D1;     // Timeframe TDI 4
input int TDI_FAST_PERIOD = 2;                        // Tdi période rapide
input int TDI_SLOW_PERIOD = 7;                        // Tdi période lente
input int TDI_MIDDLE_PERIOD = 34;                     // Tdi période milieu
input int TDI_ANGLE_MIN = 20;                         // Angle minimal
input int TDI_ANGLE_MAX = 80;                         // Angle maximal


input group "PARAMÈTRES SIGNAL"
input bool TDI_TIMEFRAME0_CROSS = false;              // Croisement TDI 0
input bool TDI_TIMEFRAME1_CROSS = false;              // Croisement TDI 1
input bool TDI_TIMEFRAME2_CROSS = false;              // Croisement TDI 2
input bool TDI_TIMEFRAME3_CROSS = false;              // Croisement TDI 3
input bool TDI_TIMEFRAME4_CROSS = false;              // Croisement TDI 4
input bool TDI_TIMEFRAME0_TREND = false;              // Tendance TDI 0
input bool TDI_TIMEFRAME1_TREND = false;              // Tendance TDI 1
input bool TDI_TIMEFRAME2_TREND = false;              // Tendance TDI 2
input bool TDI_TIMEFRAME3_TREND = false;              // Tendance TDI 3
input bool TDI_TIMEFRAME4_TREND = false;              // Tendance TDI 4
input bool TDI_TIMEFRAME0_ANGLE = false;              // Angle TDI 0
input bool TDI_TIMEFRAME1_ANGLE = false;              // Angle TDI 1
input bool TDI_TIMEFRAME2_ANGLE = false;              // Angle TDI 2
input bool TDI_TIMEFRAME3_ANGLE = false;              // Angle TDI 3
input bool TDI_TIMEFRAME4_ANGLE = false;              // Angle TDI 4
input int TDI_SHIFT = 1;                              // Shift du TDI



input group "PARAMÈTRES RISQUE"
input double FIXED_LOT_SIZE = 0.5;                    // Taille de lot fixe
input RISK_MODE_ENUM RISK_MODE = 0;                   // Mode de calcul du risque
input double RISK_PCT = 1;                            // Pourcentage du solde
input double RISK_CURRENCY = 1000;                    // Risque en argent


input group "PARAMÈTRES DIVERS"
input int MAGIC_NUMBER = 0;                           // Nombre d'identification de l'algorithme
input bool IS_NEGSWAP_ALLOWED = false;                // Activer les swaps négatifs
input double SPREAD_MAX = 2;                          // Spread maximal
input double SL_DISTANCE_MIN = 20;                    // Distance SL minimale
input double TP_DISTANCE_MIN = 20;                    // Distance TP minimale


//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
int rsi_handle[5];
double ask, bid;

double sl_distance_min = SL_DISTANCE_MIN * _Point * 10;
double tp_distance_min = TP_DISTANCE_MIN * _Point * 10;




//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   
   if(InitializeIndicators() == 0)
      return(INIT_FAILED);
   
   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   
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
   UpdateBidAsk();
  
   ExecuteTrade();
  
   
  }
//+------------------------------------------------------------------+





int InitializeIndicators(){

   ENUM_TIMEFRAMES tdi_timeframes[5] = {TDI_TIMEFRAME0,TDI_TIMEFRAME1,TDI_TIMEFRAME2,
                                        TDI_TIMEFRAME3,TDI_TIMEFRAME4};
   
   for(int i=0; i<5; i++){
   
      rsi_handle[i] = iRSI(_Symbol,tdi_timeframes[i],RSI_PERIOD,RSI_APP_PRICE);
   
   
      if(rsi_handle[i] == INVALID_HANDLE)
         return 0;
   
   }


   return 1;
}




double SupportPivot(int pivot_index){

   double high = iHigh(_Symbol,PIVOT_TIMEFRAME,1);
   double low = iLow(_Symbol,PIVOT_TIMEFRAME,1);
   double close = iClose(_Symbol,PIVOT_TIMEFRAME,1);
   
   double support_pivot[];

   ArrayResize(support_pivot,PIVOT_NUMBER+1);

   support_pivot[0] = (high + low + close) / 3;
   support_pivot[1] = 2 * support_pivot[0] - high;
      
   for(int i = 2; i<ArraySize(support_pivot); i++){
   
      support_pivot[i] = support_pivot[0] - (high - low) * (i-1);
   
   
   }
   
   
   
   
   return NormalizeDouble(support_pivot[pivot_index],_Digits);
   
}









double ResistancePivot(int pivot_index){

   double high = iHigh(_Symbol,PIVOT_TIMEFRAME,1);
   double low = iLow(_Symbol,PIVOT_TIMEFRAME,1);
   double close = iClose(_Symbol,PIVOT_TIMEFRAME,1);
   
   double resistance_pivot[];

   ArrayResize(resistance_pivot,PIVOT_NUMBER+1);

   resistance_pivot[0] = (high + low + close) / 3;
   resistance_pivot[1] = 2 * resistance_pivot[0] - low;
      
   for(int i = 2; i<ArraySize(resistance_pivot); i++){
   
      resistance_pivot[i] = resistance_pivot[0] + (high - low) * (i-1);
      
   
   }
   
   
   
   
   return NormalizeDouble(resistance_pivot[pivot_index],_Digits);
   
}







//+------------------------------------------------------------------+
//| Retourne la valeur de la moyenne mobile suivant les paramètres
//| period = période de la moyenne mobile demandée
//| timeframe_index = timeframe de la moyenne mobile du tdi
//| shift = bougie demandée                                           
//+------------------------------------------------------------------+

double CalculateTdiMa(int period, int timeframe_index, int shift){


   double ma;

   double rsi[];
   CopyBuffer(rsi_handle[timeframe_index],0,0,period+2,rsi);

   double tdi[];
   ArrayCopy(tdi,rsi,0,2-shift,period);
   
   
   ma = NormalizeDouble(MathMean(tdi),1);
   
   return ma;

}





//+------------------------------------------------------------------+
//| Calculer l'angle du tdi                                          |
//+------------------------------------------------------------------+

double CalculateTdiAngle(int timeframe_index){
   
   double fast_angle;
   double slow_angle;
   double angle;


   double fast_ma[2];
   fast_ma[0] = CalculateTdiMa(TDI_FAST_PERIOD,timeframe_index,0);
   fast_ma[1] = CalculateTdiMa(TDI_FAST_PERIOD,timeframe_index,1);   
   
   double slow_ma[2];
   slow_ma[0] = CalculateTdiMa(TDI_SLOW_PERIOD,timeframe_index,0);
   slow_ma[1] = CalculateTdiMa(TDI_SLOW_PERIOD,timeframe_index,1);   
   
   
   
   
   fast_angle = (MathArctan(fast_ma[0] - fast_ma[1]) * 180) / M_PI;
   
   slow_angle = (MathArctan(slow_ma[0] - slow_ma[1]) * 180) / M_PI;
   
   angle = (slow_angle + (fast_angle * RSI_PERIOD / NormalizeDouble(TDI_MIDDLE_PERIOD,1))) /
           (1 + RSI_PERIOD / NormalizeDouble(TDI_MIDDLE_PERIOD,1));
   
   
   
   
   return NormalizeDouble(angle,1);

}






//+------------------------------------------------------------------+
//| Retourne vrai si un signal est détecté, faux sinon
//| 0 = buy, 1 = vente                                                               
//+------------------------------------------------------------------+
bool CheckTradeSignal(bool direction){

   bool cross_condition[5];

   bool trend_condition[5];
   
   bool angle_condition[5];
   
   
   int cross_condition_sum = 0;
   
   int trend_condition_sum = 0;
   
   int angle_condition_sum = 0;
   
   
   
   double cross_check[5] = {TDI_TIMEFRAME0_CROSS, TDI_TIMEFRAME1_CROSS, TDI_TIMEFRAME2_CROSS, 
                            TDI_TIMEFRAME3_CROSS, TDI_TIMEFRAME4_CROSS};
   
   double trend_check[5] = {TDI_TIMEFRAME0_TREND, TDI_TIMEFRAME1_TREND, TDI_TIMEFRAME2_TREND, 
                            TDI_TIMEFRAME3_TREND, TDI_TIMEFRAME4_TREND};

   double angle_check[5] = {TDI_TIMEFRAME0_ANGLE, TDI_TIMEFRAME1_ANGLE, TDI_TIMEFRAME2_ANGLE, 
                            TDI_TIMEFRAME3_ANGLE, TDI_TIMEFRAME4_ANGLE};
   
   
   int cross_check_sum = (int)MathSum(cross_check);
   
   int trend_check_sum = (int)MathSum(trend_check);
   
   int angle_check_sum = (int)MathSum(angle_check);
   
   
   
   
   double tdi_angle[5];
   double tdi_fast_ma[5][3];
   double tdi_slow_ma[5][3];
   double tdi_middle_ma[5][3];
   
   
   
   
   for(int timeframe = 0; timeframe < 5; timeframe++){
   
   
      tdi_angle[timeframe] = CalculateTdiAngle(timeframe);
      
      
   
      for(int shift = 0; shift < 3; shift++){
      
         
         tdi_fast_ma[timeframe][shift] = CalculateTdiMa(TDI_FAST_PERIOD,timeframe,shift);
         tdi_slow_ma[timeframe][shift] = CalculateTdiMa(TDI_SLOW_PERIOD,timeframe,shift);
         tdi_middle_ma[timeframe][shift] = CalculateTdiMa(TDI_MIDDLE_PERIOD,timeframe,shift);
      
      
         
      
      }
   // ------ COndition
   
   
      if(cross_check[timeframe]){
         
         
         
         if((!direction && tdi_fast_ma[timeframe][TDI_SHIFT + 1] < tdi_slow_ma[timeframe][TDI_SHIFT + 1] && 
            tdi_fast_ma[timeframe][TDI_SHIFT] > tdi_slow_ma[timeframe][TDI_SHIFT]) ||
            (direction && tdi_fast_ma[timeframe][TDI_SHIFT + 1] > tdi_slow_ma[timeframe][TDI_SHIFT + 1] && 
            tdi_fast_ma[timeframe][TDI_SHIFT] < tdi_slow_ma[timeframe][TDI_SHIFT])){
            
            cross_condition[timeframe] = true;
            
         }
         else{
         
            cross_condition[timeframe] = false;
            
         }
      }
      else{
      
         cross_condition[timeframe] = false;
         
      }
      
      
      
      
      
      
      if(trend_check[timeframe]){
         
         
         if((!direction && tdi_middle_ma[timeframe][TDI_SHIFT+1] < tdi_middle_ma[timeframe][TDI_SHIFT]) ||
            (direction && tdi_middle_ma[timeframe][TDI_SHIFT+1] > tdi_middle_ma[timeframe][TDI_SHIFT])){
            
            
            trend_condition[timeframe] = true;
            
         }      
         else{
            
            trend_condition[timeframe] = false;
         
         }
      
      }
      else{
            
         trend_condition[timeframe] = false;
         
      }
      
      if(angle_check[timeframe]){
         
         
         if((!direction && tdi_angle[timeframe] >= TDI_ANGLE_MIN && tdi_angle[timeframe] <= TDI_ANGLE_MAX) ||
            (direction && tdi_angle[timeframe] <= (-TDI_ANGLE_MIN) && tdi_angle[timeframe] >= (-TDI_ANGLE_MAX))){
            
            angle_condition[timeframe] = true;
            
         }
         else{
         
            angle_condition[timeframe] = false;
      
         }
      }
      else{
      
         angle_condition[timeframe] = false;
      }      
   
   
   
      cross_condition_sum += cross_condition[timeframe];
      trend_condition_sum += trend_condition[timeframe];
      angle_condition_sum += angle_condition[timeframe];
   
   
   // -----
   }
   
   
   
   if(cross_check_sum == cross_condition_sum && trend_check_sum == trend_condition_sum && 
      angle_check_sum == angle_condition_sum){
   
      return true;
      
   }
   else{
   
      return false;
   
   }
   
   
}




//+------------------------------------------------------------------+
//| Retourne une valeur de prix
//| info = "sl", "tp",
//| direction : 0 =buy, 1 = sell                                                                 
//+------------------------------------------------------------------+
double GetTradeInfo(bool direction, string info){


   double sl = 0, tp = 0;

   double sl_size[];
   double tp_size[];
   double sl_probability[];
   double proba_difference[];
   
   int proba_number = (int)MathPow(PIVOT_NUMBER,2);
   
   
   ArrayResize(sl_size,PIVOT_NUMBER);
   ArrayResize(tp_size,PIVOT_NUMBER);
   ArrayResize(sl_probability,proba_number);
   ArrayResize(proba_difference,proba_number);

   for(int i = 0; i < PIVOT_NUMBER; i++){
   
      if(!direction){
         
         sl_size[i] = MathAbs((SupportPivot(i+1) - bid) / _Point / 10);
         tp_size[i] = MathAbs((ResistancePivot(i+1) - ask) / _Point / 10);
      
      
      }
      else{
      
         sl_size[i] = MathAbs((ResistancePivot(i+1) - ask) / _Point / 10);      
         tp_size[i] = MathAbs((SupportPivot(i+1) - bid) / _Point / 10);
      
      }
   
      sl_size[i] = NormalizeDouble(sl_size[i],2);
      tp_size[i] = NormalizeDouble(tp_size[i],2);
   
   
   }

   for(int i = 0 ; i<PIVOT_NUMBER; i++){
   
   
      for(int j = 0; j<PIVOT_NUMBER; j++){
      
      
         int index = i * PIVOT_NUMBER + j;
         
         
         if((!direction && bid > SupportPivot(j+1) && ask < ResistancePivot(i+1)) ||
            (direction && bid > SupportPivot(i+1) && ask < ResistancePivot(j+1))){
         
            
            sl_probability[index] = tp_size[i] / (tp_size[i] + sl_size[j]);
            sl_probability[index] = NormalizeDouble(sl_probability[index]*100,2);
      
      
         }
         else{
            
            sl_probability[index] = 151;
         
         }
         
         
         proba_difference[index] = MathAbs(sl_probability[index] - TARGET_PROBABILITY);
         proba_difference[index] = NormalizeDouble(proba_difference[index],2);
         
         
         
         
         if(MathMin(proba_difference) == proba_difference[index]){
         
            if(!direction){
            
               sl = SupportPivot(j+1);
               tp = ResistancePivot(i+1);
               
            }
            else{
            
               sl = ResistancePivot(j+1);
               tp = SupportPivot(i+1);
               
            }
            
         
         }
         
         
         
      // -------- j   
      }
   // ------ i
   }

   
   
   if(info == "sl")
      return sl;
   else
      return tp;

}




void UpdateBidAsk(){

   bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

}






void ExecuteTrade(){

   double sl = 0, tp = 0;
   

   
      
   if(CheckTradeSignal(0) && !IsTradeOpen(0) && IsTradeAllowed(0)){
   
      sl = GetTradeInfo(0,"sl");
      tp = GetTradeInfo(0,"tp");
   
      trade.Buy(CalculateLotSize(bid - sl),_Symbol,ask,sl,tp);
   }
   if(CheckTradeSignal(1) && !IsTradeOpen(1) && IsTradeAllowed(1)){
    
      sl = GetTradeInfo(1,"sl");
      tp = GetTradeInfo(1,"tp");

      trade.Sell(CalculateLotSize(sl - ask),_Symbol,bid,sl,tp);
   }


}





//+------------------------------------------------------------------+
//| Retourne la taille de position en nombre de lots
//| sl_distance = SL- ASK, bid - SL                                                                 
//+------------------------------------------------------------------+

double CalculateLotSize(double sl_distance){


   double tick_size = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double volume_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   
   
   
   double risk_volume_step = (sl_distance/tick_size)*tick_value*volume_step;
   
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   double risk = 0;
   double lot_size = 0;
   
         
   
   
   switch(RISK_MODE){
   
   
      case 0:
      
         risk = RISK_PCT*account_balance/100;
         
         lot_size = MathFloor(risk/risk_volume_step)*volume_step;
      
      
         break;
   
   
      case 1:
      
         risk = RISK_CURRENCY;
         
         lot_size = MathFloor(risk/risk_volume_step)*volume_step;
         
      
         break;
   
      
      
      case 2:
   
         lot_size = FIXED_LOT_SIZE;
      
   
         break;
   
   }
   
      
   
   


   return NormalizeDouble(lot_size,2);

}








bool IsTradeOpen(bool direction){

   for(int i = PositionsTotal()-1; i>=0; i--){
   
      ulong position_ticket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(position_ticket)){
      
         if(PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER && PositionGetSymbol(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == direction){
         
            
            return true;
         
         }
      
      }
      
  
   
   }
   
   return false;
}









bool IsTradeAllowed(bool direction){


   double swap_long = SymbolInfoDouble(_Symbol,SYMBOL_SWAP_LONG);
   double swap_short = SymbolInfoDouble(_Symbol,SYMBOL_SWAP_SHORT);

   double sl = 0, tp = 0;

   if(!direction){
      sl = GetTradeInfo(0,"sl");
      tp = GetTradeInfo(0,"tp");
   }
   else{
      sl = GetTradeInfo(1,"sl");
      tp = GetTradeInfo(1,"tp");
   }   
   
   double spread = (ask - bid) / _Point;



   if(!direction){
   
      if(IsTradeOpen(1))
         return false;

      if(!IS_NEGSWAP_ALLOWED && swap_long <= 0)
         return false;
   
      if(bid < sl + sl_distance_min || ask > tp - tp_distance_min)
         return false;
   
   
   }
   else{
   
      if(IsTradeOpen(0))
         return false;
         
         
      if(!IS_NEGSWAP_ALLOWED && swap_short <= 0)
         return false;
   
      if(bid < tp + tp_distance_min || ask > sl - sl_distance_min)
         return false;
   
   
   }


   if(spread > SPREAD_MAX * 10)
      return false;
      
      
      
      
   return true;

}



