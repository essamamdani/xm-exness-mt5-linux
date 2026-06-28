//+------------------------------------------------------------------+
//|  AccountBridge.mq5 — writes account, price, positions, orders   |
//|  and history to JSON files for the REST API.                    |
//|  Also reads *.cmd command files sent by the API to trade.       |
//|  Attach to any chart; it runs automatically.                    |
//+------------------------------------------------------------------+
#property version "1.3"
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

void OnTimer() { WriteAll(); ProcessCommands(); }
void OnTick()  { WriteAll(); }

void WriteAll()
{
   WriteAccount();
   WriteSymbol(Symbol());
   WriteBars(Symbol());
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

//--- Bars JSON ----------------------------------------------------
ENUM_TIMEFRAMES TimeframeFromString(string tf)
{
   if(tf == "1m")  return PERIOD_M1;
   if(tf == "5m")  return PERIOD_M5;
   if(tf == "15m") return PERIOD_M15;
   if(tf == "30m") return PERIOD_M30;
   if(tf == "1h")  return PERIOD_H1;
   if(tf == "4h")  return PERIOD_H4;
   if(tf == "1d")  return PERIOD_D1;
   if(tf == "1w")  return PERIOD_W1;
   if(tf == "1mo") return PERIOD_MN1;
   return PERIOD_CURRENT;
}

void WriteBars(string symbol)
{
   string tfs[] = {"1m", "5m", "15m", "30m", "1h", "4h", "1d", "1w", "1mo"};
   int counts[] = {500, 500, 500, 500, 500, 500, 500, 250, 120};
   int n = ArraySize(tfs);

   SymbolSelect(symbol, true);
   for(int i = 0; i < n; i++)
   {
      ENUM_TIMEFRAMES tf = TimeframeFromString(tfs[i]);
      MqlRates rates[];
      int copied = CopyRates(symbol, tf, 0, counts[i], rates);
      if(copied <= 0)
         continue;

      string fname = "bars_" + tfs[i] + ".json";
      int h = FileOpen(fname, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(h == INVALID_HANDLE)
         continue;

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      string j = "{\n";
      j += "  \"source\": \"mt5\",\n";
      j += "  \"symbol\": \"" + symbol + "\",\n";
      j += "  \"timeframe\": \"" + tfs[i] + "\",\n";
      j += "  \"count\": " + IntegerToString(copied) + ",\n";
      j += "  \"bars\": [\n";
      for(int k = 0; k < copied; k++)
      {
         if(k > 0) j += ",\n";
         j += "    {\n";
         j += "      \"Date\": \"" + TimeToString(rates[k].time, TIME_DATE|TIME_SECONDS) + "\",\n";
         j += "      \"Open\": " + DoubleToString(rates[k].open, digits)  + ",\n";
         j += "      \"High\": " + DoubleToString(rates[k].high, digits)  + ",\n";
         j += "      \"Low\": "  + DoubleToString(rates[k].low, digits)   + ",\n";
         j += "      \"Close\": "+ DoubleToString(rates[k].close, digits) + ",\n";
         j += "      \"Volume\": "+ IntegerToString((long)rates[k].tick_volume) + "\n";
         j += "    }";
      }
      j += "\n  ]\n";
      j += "}\n";

      FileWriteString(h, j);
      FileClose(h);
   }
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
      long magic = PositionGetInteger(POSITION_MAGIC);
      string comment = PositionGetString(POSITION_COMMENT);
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
      j += "    \"magic\":          " + IntegerToString(magic)                + ",\n";
      j += "    \"comment\":        \"" + JsonString(comment)                  + "\",\n";
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
      long magic = OrderGetInteger(ORDER_MAGIC);
      string comment = OrderGetString(ORDER_COMMENT);
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
      j += "    \"magic\":       " + IntegerToString(magic)       + ",\n";
      j += "    \"comment\":     \"" + JsonString(comment)         + "\",\n";
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
      long order = HistoryDealGetInteger(ticket, DEAL_ORDER);
      long position_id = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
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
      j += "    \"order\":       " + IntegerToString(order)       + ",\n";
      j += "    \"position_id\": " + IntegerToString(position_id) + ",\n";
      j += "    \"magic\":       " + IntegerToString(magic)       + ",\n";
      j += "    \"comment\":     \"" + JsonString(comment)         + "\",\n";
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
   switch((int)type)
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

//--- Trade helpers ------------------------------------------------
string TradeRetcodeMsg(MqlTradeResult &res)
{
   return StringFormat("trade error %d", res.retcode);
}

ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol)
{
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

bool MarketOrder(string symbol, ENUM_ORDER_TYPE type, double volume,
                 double sl, double tp, string comment, ulong magic,
                 int deviation, ulong &out_ticket, string &out_msg)
{
   SymbolSelect(symbol, true);
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      out_msg = "no tick for " + symbol;
      return false;
   }

   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = symbol;
   req.volume       = volume;
   req.type         = type;
   req.price        = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   req.sl           = sl;
   req.tp           = tp;
   req.deviation    = deviation;
   req.magic        = magic;
   req.comment      = comment;
   req.type_filling = GetFillingMode(symbol);

   if(!OrderSend(req, res))
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   out_ticket = res.order;
   return true;
}

bool PendingOrder(string symbol, ENUM_ORDER_TYPE type, double volume,
                  double price, double sl, double tp, string comment,
                  ulong magic, ulong &out_ticket, string &out_msg)
{
   SymbolSelect(symbol, true);
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      out_msg = "no tick for " + symbol;
      return false;
   }

   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = symbol;
   req.volume       = volume;
   req.type         = type;
   req.price        = price;
   req.sl           = sl;
   req.tp           = tp;
   req.magic        = magic;
   req.comment      = comment;
   req.type_time    = ORDER_TIME_GTC;
   req.type_filling = GetFillingMode(symbol);

   if(!OrderSend(req, res))
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   out_ticket = res.order;
   return true;
}

bool ClosePosition(ulong ticket, string &out_msg)
{
   if(!PositionSelectByTicket(ticket))
   {
      out_msg = "position not found";
      return false;
   }

   string symbol = PositionGetString(POSITION_SYMBOL);
   long pos_type = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      out_msg = "no tick for " + symbol;
      return false;
   }

   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action        = TRADE_ACTION_DEAL;
   req.symbol        = symbol;
   req.volume        = volume;
   req.type          = (pos_type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price         = (req.type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   req.position      = ticket;
   req.type_filling  = GetFillingMode(symbol);

   if(!OrderSend(req, res))
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   return true;
}

bool CancelOrder(ulong ticket, string &out_msg)
{
   if(!OrderSelect(ticket))
   {
      out_msg = "order not found";
      return false;
   }

   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_REMOVE;
   req.order  = ticket;

   if(!OrderSend(req, res))
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   return true;
}

bool ModifyPositionSLTP(ulong ticket, bool has_sl, double sl, bool has_tp, double tp, string &out_msg)
{
   if(!PositionSelectByTicket(ticket))
   {
      out_msg = "position not found";
      return false;
   }

   string symbol = PositionGetString(POSITION_SYMBOL);
   double new_sl = has_sl ? sl : PositionGetDouble(POSITION_SL);
   double new_tp = has_tp ? tp : PositionGetDouble(POSITION_TP);

   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = symbol;
   req.position = ticket;
   req.sl       = new_sl;
   req.tp       = new_tp;

   if(!OrderSend(req, res))
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
   {
      out_msg = TradeRetcodeMsg(res);
      return false;
   }
   return true;
}

//--- Trade command processing -------------------------------------
void ProcessCommands()
{
   ProcessCommandFile("command.txt");
}

void ProcessCommandFile(string fname)
{
   int h = FileOpen(fname, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return;

   string action = "";
   string symbol = "";
   string comment = "";
   string cmd_id = "";
   double volume = 0.0;
   double price = 0.0;
   double sl = 0.0;
   double tp = 0.0;
   bool has_sl = false;
   bool has_tp = false;
   int deviation = 10;
   ulong magic = 0;
   ulong ticket = 0;

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      int pos = StringFind(line, "=");
      if(pos < 0)
         continue;
      string key = StringSubstr(line, 0, pos);
      string val = StringSubstr(line, pos + 1);
      if(key == "action")      action = val;
      else if(key == "symbol") symbol = val;
      else if(key == "volume") volume = StringToDouble(val);
      else if(key == "price")  price = StringToDouble(val);
      else if(key == "sl")     { sl = StringToDouble(val); has_sl = true; }
      else if(key == "tp")     { tp = StringToDouble(val); has_tp = true; }
      else if(key == "deviation") deviation = (int)StringToInteger(val);
      else if(key == "comment")   comment = val;
      else if(key == "magic")     magic = (ulong)StringToInteger(val);
      else if(key == "ticket")    ticket = (ulong)StringToInteger(val);
      else if(key == "command_id") cmd_id = val;
   }
   FileClose(h);

   bool ok = false;
   string msg = "";
   ulong result_ticket = 0;

   if(action == "market_buy")
   {
      ok = MarketOrder(symbol, ORDER_TYPE_BUY, volume, sl, tp, comment, magic, deviation, result_ticket, msg);
   }
   else if(action == "market_sell")
   {
      ok = MarketOrder(symbol, ORDER_TYPE_SELL, volume, sl, tp, comment, magic, deviation, result_ticket, msg);
   }
   else if(action == "buy_limit" || action == "sell_limit" ||
           action == "buy_stop"  || action == "sell_stop")
   {
      ENUM_ORDER_TYPE otype;
      if(action == "buy_limit")      otype = ORDER_TYPE_BUY_LIMIT;
      else if(action == "sell_limit") otype = ORDER_TYPE_SELL_LIMIT;
      else if(action == "buy_stop")   otype = ORDER_TYPE_BUY_STOP;
      else                            otype = ORDER_TYPE_SELL_STOP;

      if(price <= 0)
         msg = "invalid price for pending order";
      else
         ok = PendingOrder(symbol, otype, volume, price, sl, tp, comment, magic, result_ticket, msg);
   }
   else if(action == "close")
   {
      ok = ClosePosition(ticket, msg);
      if(ok) result_ticket = ticket;
   }
   else if(action == "cancel")
   {
      ok = CancelOrder(ticket, msg);
      if(ok) result_ticket = ticket;
   }
   else if(action == "modify_sl")
   {
      ok = ModifyPositionSLTP(ticket, has_sl, sl, has_tp, tp, msg);
      if(ok) result_ticket = ticket;
   }
   else
   {
      msg = "unknown action: " + action;
   }

   WriteResult(cmd_id, ok, result_ticket, msg);
   FileDelete(fname, FILE_COMMON);
}

void WriteResult(string cmd_id, bool ok, ulong ticket, string msg)
{
   if(cmd_id == "")
      return;

   string fname = "result_" + cmd_id + ".json";
   int h = FileOpen(fname, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("AccountBridge: failed to write result file ", fname, " err=", GetLastError());
      return;
   }

   string ok_str = ok ? "true" : "false";
   string j = "{\n";
   j += "  \"ok\": " + ok_str + ",\n";
   j += "  \"ticket\": " + IntegerToString((long)ticket) + ",\n";
   j += "  \"message\": \"" + JsonString(msg) + "\"\n";
   j += "}\n";

   FileWriteString(h, j);
   FileClose(h);
}
