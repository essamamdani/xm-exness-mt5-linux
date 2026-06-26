//+------------------------------------------------------------------+
//|  AccountBridge.mq5 — writes account, price, positions, orders   |
//|  and history to JSON files for the REST API.                    |
//|  Attach to any chart; it runs automatically.                    |
//+------------------------------------------------------------------+
#property version "1.2"
#property strict

input int    UpdateSec   = 1;            // Update every N seconds
input int    HistoryDays = 7;            // How many days of closed history to export

int OnInit()
{
   Print("AccountBridge OnInit start on ", Symbol());
   EventSetTimer(UpdateSec);
   Print("AccountBridge OnInit done");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer() { WriteAll(); }
void OnTick()  { WriteAll(); }

void WriteAll()
{
   WriteAccount();
   WriteSymbol(Symbol());
   WritePositions();
   WriteOrders();
   WriteHistory();
}

//--- helper -------------------------------------------------------
string JsonString(string s)
{
   // Minimal escaping for quotes and backslashes
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   return s;
}

//--- Account JSON -------------------------------------------------
void WriteAccount()
{
   int h = FileOpen("account.json", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("AccountBridge: failed to open account.json, err=", GetLastError());
      return;
   }

   string j = "{\n";
   j += "  \"login\":       " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))         + ",\n";
   j += "  \"name\":        \"" + JsonString(AccountInfoString(ACCOUNT_NAME))              + "\",\n";
   j += "  \"server\":      \"" + JsonString(AccountInfoString(ACCOUNT_SERVER))            + "\",\n";
   j += "  \"currency\":    \"" + JsonString(AccountInfoString(ACCOUNT_CURRENCY))          + "\",\n";
   j += "  \"balance\":     "   + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),   2)  + ",\n";
   j += "  \"equity\":      "   + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),    2)  + ",\n";
   j += "  \"margin\":      "   + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN),    2)  + ",\n";
   j += "  \"free_margin\": "   + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2) + ",\n";
   j += "  \"profit\":      "   + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT),    2)  + ",\n";
   j += "  \"leverage\":    "   + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE))    + ",\n";
   j += "  \"timestamp\":   \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS)      + "\"\n";
   j += "}\n";

   FileWriteString(h, j);
   FileClose(h);
}

//--- Symbol JSON --------------------------------------------------
void WriteSymbol(string symbol)
{
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      SymbolSelect(symbol, true);
      if(!SymbolInfoTick(symbol, tick))
      {
         Print("AccountBridge: no tick for ", symbol, " err=", GetLastError());
         return;
      }
   }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread_pts = (point > 0) ? (tick.ask - tick.bid) / point : 0;

   int h = FileOpen(symbol + ".json", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("AccountBridge: failed to open ", symbol, ".json err=", GetLastError());
      return;
   }

   string j = "{\n";
   j += "  \"symbol\":      \"" + symbol                                          + "\",\n";
   j += "  \"bid\":         "   + DoubleToString(tick.bid,  digits)               + ",\n";
   j += "  \"ask\":         "   + DoubleToString(tick.ask,  digits)               + ",\n";
   j += "  \"last\":        "   + DoubleToString(tick.last, digits)               + ",\n";
   j += "  \"spread_pts\":  "   + DoubleToString(spread_pts, 1)                   + ",\n";
   j += "  \"volume\":      "   + IntegerToString(tick.volume)                    + ",\n";
   j += "  \"tick_time\":   \"" + TimeToString(tick.time, TIME_DATE|TIME_SECONDS) + "\",\n";
   j += "  \"timestamp\":   \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\"\n";
   j += "}\n";

   FileWriteString(h, j);
   FileClose(h);
}

//--- Positions JSON -----------------------------------------------
void WritePositions()
{
   int h = FileOpen("positions.json", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return;

   string j = "[\n";
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long type = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double swap = PositionGetDouble(POSITION_SWAP);
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);

      if(i > 0) j += ",\n";
      j += "  {\n";
      j += "    \"ticket\":         " + IntegerToString((long)ticket)            + ",\n";
      j += "    \"symbol\":         \"" + symbol                              + "\",\n";
      j += "    \"type\":           \"" + (type == POSITION_TYPE_BUY ? "BUY" : "SELL") + "\",\n";
      j += "    \"volume\":         " + DoubleToString(volume, 2)             + ",\n";
      j += "    \"open_price\":     " + DoubleToString(open_price, 6)         + ",\n";
      j += "    \"current_price\":  " + DoubleToString(current_price, 6)      + ",\n";
      j += "    \"sl\":             " + DoubleToString(sl, 6)                 + ",\n";
      j += "    \"tp\":             " + DoubleToString(tp, 6)                 + ",\n";
      j += "    \"profit\":         " + DoubleToString(profit, 2)             + ",\n";
      j += "    \"swap\":           " + DoubleToString(swap, 2)               + ",\n";
      j += "    \"open_time\":      \"" + TimeToString(open_time, TIME_DATE|TIME_SECONDS) + "\"\n";
      j += "  }";
   }
   j += "\n]\n";

   FileWriteString(h, j);
   FileClose(h);
}

//--- Pending Orders JSON ------------------------------------------
void WriteOrders()
{
   int h = FileOpen("orders.json", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return;

   string j = "[\n";
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      long type = OrderGetInteger(ORDER_TYPE);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      double sl = OrderGetDouble(ORDER_SL);
      double tp = OrderGetDouble(ORDER_TP);
      datetime setup_time = (datetime)OrderGetInteger(ORDER_TIME_SETUP);

      if(i > 0) j += ",\n";
      j += "  {\n";
      j += "    \"ticket\":      " + IntegerToString((long)ticket)   + ",\n";
      j += "    \"symbol\":      \"" + symbol                     + "\",\n";
      j += "    \"type\":        \"" + OrderTypeString(type)      + "\",\n";
      j += "    \"volume\":      " + DoubleToString(volume, 2)    + ",\n";
      j += "    \"price\":       " + DoubleToString(price, 6)     + ",\n";
      j += "    \"sl\":          " + DoubleToString(sl, 6)        + ",\n";
      j += "    \"tp\":          " + DoubleToString(tp, 6)        + ",\n";
      j += "    \"setup_time\":  \"" + TimeToString(setup_time, TIME_DATE|TIME_SECONDS) + "\"\n";
      j += "  }";
   }
   j += "\n]\n";

   FileWriteString(h, j);
   FileClose(h);
}

//--- Closed History JSON ------------------------------------------
void WriteHistory()
{
   int h = FileOpen("history.json", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return;

   datetime from_time = TimeCurrent() - HistoryDays * 24 * 60 * 60;
   HistorySelect(from_time, TimeCurrent());

   string j = "[\n";
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0) continue;

      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      datetime close_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

      if(i > 0) j += ",\n";
      j += "  {\n";
      j += "    \"ticket\":      " + IntegerToString((long)ticket)   + ",\n";
      j += "    \"symbol\":      \"" + symbol                     + "\",\n";
      j += "    \"type\":        \"" + DealTypeString(type)       + "\",\n";
      j += "    \"volume\":      " + DoubleToString(volume, 2)    + ",\n";
      j += "    \"price\":       " + DoubleToString(price, 6)     + ",\n";
      j += "    \"profit\":      " + DoubleToString(profit, 2)    + ",\n";
      j += "    \"swap\":        " + DoubleToString(swap, 2)      + ",\n";
      j += "    \"commission\":  " + DoubleToString(commission, 2)+ ",\n";
      j += "    \"entry\":       \"" + EntryString(entry)         + "\",\n";
      j += "    \"close_time\":  \"" + TimeToString(close_time, TIME_DATE|TIME_SECONDS) + "\"\n";
      j += "  }";
   }
   j += "\n]\n";

   FileWriteString(h, j);
   FileClose(h);
}

//--- Helpers ------------------------------------------------------
string OrderTypeString(long type)
{
   switch(type)
   {
      case ORDER_TYPE_BUY:            return "BUY";
      case ORDER_TYPE_SELL:           return "SELL";
      case ORDER_TYPE_BUY_LIMIT:      return "BUY_LIMIT";
      case ORDER_TYPE_SELL_LIMIT:     return "SELL_LIMIT";
      case ORDER_TYPE_BUY_STOP:       return "BUY_STOP";
      case ORDER_TYPE_SELL_STOP:      return "SELL_STOP";
      case ORDER_TYPE_BUY_STOP_LIMIT: return "BUY_STOP_LIMIT";
      case ORDER_TYPE_SELL_STOP_LIMIT:return "SELL_STOP_LIMIT";
   }
   return "UNKNOWN";
}

string DealTypeString(long type)
{
   if(type == DEAL_TYPE_BUY)  return "BUY";
   if(type == DEAL_TYPE_SELL) return "SELL";
   return "UNKNOWN";
}

string EntryString(long entry)
{
   if(entry == DEAL_ENTRY_IN)  return "IN";
   if(entry == DEAL_ENTRY_OUT) return "OUT";
   if(entry == DEAL_ENTRY_INOUT) return "INOUT";
   if(entry == DEAL_ENTRY_OUT_BY) return "OUT_BY";
   return "UNKNOWN";
}
