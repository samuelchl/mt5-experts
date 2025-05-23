#property strict


string tick_file =  "tick.json";
string signal_file =  "signal.txt";

void OnTick()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ulong time = TimeCurrent();

   string tick = StringFormat("{\"symbol\": \"%s\", \"price\": %.5f, \"time\": %d}", _Symbol, bid, time);
   int fh = FileOpen(tick_file, FILE_WRITE | FILE_TXT);
   if (fh != INVALID_HANDLE)
   {
      FileWrite(fh, tick);
      FileClose(fh);
   }

   // Lire la réponse Python
   if (FileIsExist(signal_file))
   {
      int sh = FileOpen(signal_file, FILE_READ | FILE_TXT);
      if (sh != INVALID_HANDLE)
      {
         string signal = FileReadString(sh);
         FileClose(sh);

         if (signal == "BUY")
         {
         
           Print("Signal Python: BUY");
            trade(ORDER_TYPE_BUY);
         }
         else if (signal == "SELL")
         {
            Print("Signal Python: SELL");
            trade(ORDER_TYPE_SELL);
         }
      }
   }
}

void trade(const int type)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = 0.1;
   request.type = type;
   request.price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.deviation = 5;
   request.magic = 123456;
   request.comment = "Python hybrid bot";
   
   if (!OrderSend(request, result))
      Print("OrderSend failed: ", result.retcode);
   else
      Print("Order sent: ", result.retcode);
}