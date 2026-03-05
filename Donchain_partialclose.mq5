//+------------------------------------------------------------------+
//|                                         Donchian_BreakOut_EA.mq5 |
//+------------------------------------------------------------------+
#property copyright "Nick"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>


input group "--- Donchian Settings ---"
input int    InpDonchianPeriod = 90;   // Donchian Channel Period
input int    InpFlatPeriods    = 30;    // Required Flat Periods Before Breakout

input group "--- Risk & Trade Settings ---"
input double InpRiskPercent    = 1.0;  // Risk per trade (% of Equity)
input int    InpSLCandles      = 0;    // Candles back for SL (1 = previous candle)
input double InpRewardRisk     = 4.0;  // Reward to Risk Ratio (Min 1.0)
input ulong  InpMagicNumber    = 88888;

input group "--- Session Filter ---"
input bool   InpUseSession     = false; // Use Session Filter
input int    InpSessionStartH  = 8;     // Session Start Hour (0-23)
input int    InpSessionStartM  = 0;     // Session Start Minute (0-59)
input int    InpSessionEndH    = 17;    // Session End Hour (0-23)
input int    InpSessionEndM    = 0;     // Session End Minute (0-59)

input group "--- Martingale Settings ---"
input double InpMartingaleRatio = 1.0;  // Martingale Multiplier (1.0 = No Martingale)

input group "News Filter Configuration"
input bool   EnableNewsFilter = false;                           // Enable Economic News Filter
input int    NewsMinutesBefore = 5;                              // Minutes before news to restrict
input int    NewsMinutesAfter = 5;                               // Minutes after news to restrict
input bool   RestrictNewTradesDuringNews = true;                 // Block new trades during news window
input bool   CloseOpenTradesBeforeHighImpactNews = false;        // Close all trades before news
input string SymbolCurrencyOverride = "";                        // Manual currency override e.g. "USD,JPY"
enum ENUM_NEWS_IMPORTANCE_MODE
  {
   NEWS_HIGH_ONLY = 0,
   NEWS_MODERATE_ONLY,
   NEWS_HIGH_AND_MODERATE
  };
input ENUM_NEWS_IMPORTANCE_MODE NewsImportanceMode = NEWS_HIGH_ONLY; // Importance levels

// Cache reload interval
input int CacheReloadHours = 6;                                  // Reload calendar cache (hours)


// News Testing helpers (Simple simulation for Part 1 demonstration)
input group "Testing Parameters"
input bool EnableNewsTesting = false;                             // Enable news testing simulation with Current symbol
input string TestNewsTime = "2025.12.15 14:30:00";                // Simulated news time (yyyy.MM.dd HH:mm:ss)
input int TestNewsDuration = 10;                                  // Simulated window length (minutes)
input bool TestNewsNow = false;                                   // Manual immediate trigger



CTrade trade;
CPositionInfo posInfo;
MqlCalendarValue TodayEvents[]; // Stores calendar events for the trading day
datetime lastCalendarLoad = 0;     // TimeStamp of the last calendar update into our above value

datetime lastBarTime = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

double GetHighestHigh(string symbol, ENUM_TIMEFRAMES tf, int count, int start)
{
   double high[];
   ArraySetAsSeries(high, true);
   if(CopyHigh(symbol, tf, start, count, high) > 0)
   {
      int maxIdx = ArrayMaximum(high);
      return high[maxIdx];
   }
   return 0.0;
}

double GetLowestLow(string symbol, ENUM_TIMEFRAMES tf, int count, int start)
{
   double low[];
   ArraySetAsSeries(low, true);
   if(CopyLow(symbol, tf, start, count, low) > 0)
   {
      int minIdx = ArrayMinimum(low);
      return low[minIdx];
   }
   return 0.0;
}

bool IsSessionValid()
{
   if(!InpUseSession) return true;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   
   int currentMins = dt.hour * 60 + dt.min;
   int startMins = InpSessionStartH * 60 + InpSessionStartM;
   int endMins = InpSessionEndH * 60 + InpSessionEndM;
   
   // Session within the same day
   if(startMins < endMins)
   {
      return (currentMins >= startMins && currentMins < endMins);
   }
   // Session spans across midnight
   else 
   {
      return (currentMins >= startMins || currentMins < endMins);
   }
}
//===================================================================
// Load calendar (24-hour horizon)
//===================================================================
void LoadTodayCalendarEvents()
  {
   datetime now = TimeCurrent();
   datetime fromTime = now;
   datetime toTime = now + 24 * 3600;    // Load next 24 hours


   ArrayFree(TodayEvents);
   int count = CalendarValueHistory(TodayEvents, fromTime, toTime);
   PrintFormat("Loaded %d calendar records for the next 24 hours.", count);


   if(count <= 0)
     {
      // Still update timestamp to prevent constant reloading attempts
      lastCalendarLoad = now;
      return;
     }

// Debug: print first few events for verification
   for(int i = 0; i < MathMin(count, 5); i++)
     {
      MqlCalendarEvent ev;
      if(CalendarEventById(TodayEvents[i].event_id, ev))
        {
         PrintFormat("Event %d: %s | Time: %s | Importance: %d",
                     i, ev.name, TimeToString(TodayEvents[i].time), ev.importance);
        }
     }

   lastCalendarLoad = now;
  }

//===================================================================
// Helper: Return CSV list of relevant currencies for symbol
//===================================================================
string GetRelevantCurrencies(string symbol)
  {
// 1. Check Manual Override
   if(StringLen(SymbolCurrencyOverride) > 0)
     {
      return SymbolCurrencyOverride;
     }

   string upper = symbol;
   StringToUpper(upper);


// 2. Standard Forex Pair Logic (e.g. EURUSD -> EUR,USD)
   if(StringLen(symbol) == 6)
     {
      string baseCurr = StringSubstr(upper, 0, 3);
      string quoteCurr = StringSubstr(upper, 3, 3);
      return baseCurr + "," + quoteCurr;
     }

// 3. Heuristics for Indices/Commodities
   if(StringFind(upper, "GER") != -1 || StringFind(upper, "DE40") != -1 || StringFind(upper, "DAX") != -1)
      return "EUR";
   if(StringFind(upper, "UK") != -1 || StringFind(upper, "FTSE") != -1)
      return "GBP";
   if(StringFind(upper, "US30") != -1 || StringFind(upper, "DJ") != -1)
      return "USD";
   if(StringFind(upper, "SPX") != -1 || StringFind(upper, "US500") != -1)
      return "USD";
   if(StringFind(upper, "NAS") != -1 || StringFind(upper, "US100") != -1)
      return "USD";
   if(StringFind(upper, "XAU") != -1 || StringFind(upper, "GOLD") != -1)
      return "USD";
   if(StringFind(upper, "XAG") != -1 || StringFind(upper, "SILVER") != -1)
      return "USD";
   if(StringFind(upper, "OIL") != -1 || StringFind(upper, "WTI") != -1 || StringFind(upper, "BRENT") != -1)
      return "USD";
   if(StringFind(upper, "JPN") != -1 || StringFind(upper, "NIK") != -1)
      return "JPY";
   if(StringFind(upper, "AUD") != -1)
      return "AUD";
   if(StringFind(upper, "CAD") != -1)
      return "CAD";
   if(StringFind(upper, "NZD") != -1)
      return "NZD";
   if(StringFind(upper, "CHF") != -1)
      return "CHF";
   if(StringFind(upper, "EUR") != -1)
      return "EUR";
   if(StringFind(upper, "GBP") != -1)
      return "GBP";
   if(StringFind(upper, "JPY") != -1)
      return "JPY";

// Fallback: if we can't guess, return nothing (safe mode)
   return "";
  }
//===================================================================
// Utility: Get currency from calendar event (via Country ID)
//===================================================================
string GetCurrencyFromEventDirect(const MqlCalendarEvent &ev)
  {
   MqlCalendarCountry country;
   if(CalendarCountryById(ev.country_id, country))
     {
      return country.currency; // Returns "USD", "EUR", etc.
     }
   return "";
  }
//===================================================================
// Core Detection Logic
// Returns true if 'now' is inside a news window for the specific symbol
//===================================================================
bool isUpcomingNews(const string symbol)
  {
   datetime now = TimeCurrent();

// A. Cache Management
   if(lastCalendarLoad == 0 || (now - lastCalendarLoad) > (datetime)CacheReloadHours * 3600)
     {
      LoadTodayCalendarEvents();
     }

   if(ArraySize(TodayEvents) == 0)
      return false;


// B. Testing Simulation
   if(EnableNewsTesting)
     {
      if(TestNewsNow)
         return true;
      datetime t = StringToTime(TestNewsTime);
      if(t > 0)
        {
         datetime start = t - TestNewsDuration * 60;
         datetime end   = t + TestNewsDuration * 60;
         if(now >= start && now <= end)
            return true;
        }
     }

// C. Optimization: Prepare Currency List OUTSIDE the loop
   string relevant = GetRelevantCurrencies(symbol);
   if(StringLen(relevant) == 0)
      return false;

   string currencyArray[];
   int currencyCount = StringSplit(relevant, ',', currencyArray);
   for(int k = 0; k < currencyCount; k++)
     {
      StringTrimLeft(currencyArray[k]);
      StringTrimRight(currencyArray[k]);
      StringToUpper(currencyArray[k]);
     }

// D. Event Scan
   for(int i = 0; i < ArraySize(TodayEvents); i++)
     {
      MqlCalendarEvent ev;
      // Retrieve event details from ID
      if(!CalendarEventById(TodayEvents[i].event_id, ev))
         continue;

      // 1. Importance Filter
      bool okImportance = false;
      switch(NewsImportanceMode)
        {
         case NEWS_HIGH_ONLY:
            okImportance = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
            break;
         case NEWS_MODERATE_ONLY:
            okImportance = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
            break;
         case NEWS_HIGH_AND_MODERATE:
            okImportance = (ev.importance == CALENDAR_IMPORTANCE_HIGH || ev.importance == CALENDAR_IMPORTANCE_MODERATE);
            break;
        }
      if(!okImportance)
         continue;

      // 2. Currency Relevance Filter
      string eventCurrency = GetCurrencyFromEventDirect(ev);
      if(StringLen(eventCurrency) == 0)
         continue;

      bool affect = false;
      for(int j = 0; j < currencyCount; j++)
        {
         if(eventCurrency == currencyArray[j])
           {
            affect = true;
            break;
           }
        }
      if(!affect)
         continue;

      // 3. Time Window Check
      datetime eventTime = TodayEvents[i].time;
      datetime windowStart = eventTime - (NewsMinutesBefore * 60);
      datetime windowEnd   = eventTime + (NewsMinutesAfter * 60);

      if(now >= windowStart && now <= windowEnd)
        {
         // Optional: Print once per detection to avoid log spam
         static string lastDetectedKey = "";
         string key = ev.name + "|" + TimeToString(eventTime);
         if(key != lastDetectedKey)
           {
            PrintFormat("NEWS: %s | Time: %s | Currency: %s", ev.name, TimeToString(eventTime), eventCurrency);
            lastDetectedKey = key;
           }
         return true;
        }
     }

   return false;
  }
bool IsNewsTime(string symbol)
  {
   return isUpcomingNews(symbol);
  }
//===================================================================
// Check if new trades are allowed (Main Filter Gate)
//===================================================================
bool CanOpenNewTrade(string symbol)
  {
   if(!EnableNewsFilter)
      return true;
   if(!RestrictNewTradesDuringNews)
      return true;

   if(IsNewsTime(symbol))
     {
      return false; // Block trade
     }

   return true;
  }
//===================================================================
// CloseAllTradesForSymbol
// Implements safe reverse iteration and CTrade closing
//===================================================================
void CloseAllTradesForSymbol(string symbol)
  {
// Iterate backward to safely close multiple positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      // Filter by symbol
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      // Close Logic
      bool closed = trade.PositionClose(ticket);

      if(closed)
        {
         PrintFormat("Closed position #%d on %s due to news.", ticket, symbol);
        }
      else
        {
         PrintFormat("Failed to close #%d. Error: %d", ticket, GetLastError());
        }
     }
  }
          
int GetConsecutiveLosses()
{
   if(InpMartingaleRatio <= 1.0) return 0;
   
   int losses = 0;
   HistorySelect(0, TimeCurrent());
   
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         ulong magic = (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC);
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
         
         if(symbol == _Symbol && magic == InpMagicNumber && (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT))
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) 
                          + HistoryDealGetDouble(ticket, DEAL_SWAP) 
                          + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            
            if(profit < 0.0)
            {
               losses++;
            }
            else
            {
               break; // Stop counting at the first win
            }
         }
      }
   }
   return losses;
}

double CalculateLotSize(double slDistancePrice)
{
   if(slDistancePrice <= 0) return 0.0;
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * InpRiskPercent / 100.0;
   
   int losses = GetConsecutiveLosses();
   if(losses > 0)
   {
      riskMoney *= MathPow(InpMartingaleRatio, losses);
   }
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0 || tickValue == 0) return 0.0;
   
   //double valuePerPrice = tickValue / tickSize;
   double valuePerPrice = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double lots = riskMoney / (slDistancePrice * valuePerPrice);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(stepLot > 0)
      lots = MathFloor(lots / stepLot) * stepLot;
      
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
}

double NormalizeVol(double v)
{
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st > 0) v = MathFloor(v / st) * st;
   return MathMax(mn, MathMin(mx, v));
}

void ManageOpenTrades()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   
   // Get current Donchian Mid line
   double dcHigh = GetHighestHigh(_Symbol, _Period, InpDonchianPeriod, 1);
   double dcLow = GetLowestLow(_Symbol, _Period, InpDonchianPeriod, 1);
   double dcMid = (dcHigh + dcLow) / 2.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
      {
         ulong ticket = posInfo.Ticket();
         double openPrice = posInfo.PriceOpen();
         double currentPrice = posInfo.PriceCurrent();
         double sl = posInfo.StopLoss();
         double volume = posInfo.Volume();
         ENUM_POSITION_TYPE type = posInfo.PositionType();
         
         // Fetch initial SL distance from custom deal comment if available, or calculate distance from current SL logic (assuming SL wasn't moved, or using global logic)
         // Since trailing stop is based on "initial SL pip", we should compute it from the first entry if possible.
         // A safe approximation for now: get the recorded initial SL distance 
         // But instead we will compute the floating distance from openPrice to SL *at the start*. 
         // If SL was moved, we need a better memory. We can use a global variable or static memory per ticket.
         
         double initialSLDist = 0;
         string gvKeySL = StringFormat("DC_SLDIST_%I64u", ticket);
         if(GlobalVariableCheck(gvKeySL))
         {
            initialSLDist = GlobalVariableGet(gvKeySL);
         }
         else
         {
            initialSLDist = MathAbs(openPrice - sl);
            GlobalVariableSet(gvKeySL, initialSLDist);
         }
         
         double triggerDist = initialSLDist * 2.0; // Reward reach to 2
         
         bool hitPartial = false;
         
         if(type == POSITION_TYPE_BUY)
         {
            // Close order when price crosses middle line of Donchian
            if(currentPrice < dcMid)
            {
               trade.PositionClose(ticket);
               GlobalVariableDel(gvKeySL);
               continue;
            }
            
            if(currentPrice >= openPrice + triggerDist)
               hitPartial = true;
               
            // Trailing stop logic exactly equal to initial SL pip distance
            double newTrailingSL = NormalizeDouble(currentPrice - initialSLDist, _Digits);
            if(newTrailingSL > sl)
            {
               trade.PositionModify(ticket, newTrailingSL, 0); // TP is removed
               sl = newTrailingSL; // update for next check
            }
         }
         else if(type == POSITION_TYPE_SELL)
         {
            // Close order when price crosses middle line of Donchian
            if(currentPrice > dcMid)
            {
               trade.PositionClose(ticket);
               GlobalVariableDel(gvKeySL);
               continue;
            }
            
            if(currentPrice <= openPrice - triggerDist)
               hitPartial = true;
               
            // Trailing stop logic exactly equal to initial SL pip distance
            double newTrailingSL = NormalizeDouble(currentPrice + initialSLDist, _Digits);
            if(newTrailingSL < sl || sl == 0.0)
            {
               trade.PositionModify(ticket, newTrailingSL, 0); // TP is removed
               sl = newTrailingSL; // update for next check
            }
         }
         
         // Handle partial close and BE move if reward reached 2
         string gvKeyPart = StringFormat("DC_PART_%I64u", ticket);
         if(hitPartial && !GlobalVariableCheck(gvKeyPart))
         {
            double closeVol = NormalizeVol(volume * 0.5); // close 50%
            if(closeVol > 0 && closeVol < volume)
            {
               if(trade.PositionClosePartial(ticket, closeVol))
               {
                  GlobalVariableSet(gvKeyPart, 1.0);
                  
                  // Move SL to entry layer + spread
                  double newSL = 0;
                  if(type == POSITION_TYPE_BUY)
                  {
                     newSL = NormalizeDouble(openPrice + spread, _Digits);
                     if(newSL > sl) trade.PositionModify(ticket, newSL, 0);
                  }
                  else
                  {
                     newSL = NormalizeDouble(openPrice - spread, _Digits);
                     if(newSL < sl || sl == 0.0) trade.PositionModify(ticket, newSL, 0);
                  }
               }
            }
            else
            {
               // If volume is too small to partial close, just mark it as done and move SL
               GlobalVariableSet(gvKeyPart, 1.0);
               double newSL = 0;
               if(type == POSITION_TYPE_BUY)
               {
                  newSL = NormalizeDouble(openPrice + spread, _Digits);
                  if(newSL > sl) trade.PositionModify(ticket, newSL, 0);
               }
               else
               {
                  newSL = NormalizeDouble(openPrice - spread, _Digits);
                  if(newSL < sl || sl == 0.0) trade.PositionModify(ticket, newSL, 0);
               }
            }
         }
      }
   }
}

void OnTick()
{
   datetime timeArray[];
   ArraySetAsSeries(timeArray, true);
   if(CopyTime(_Symbol, _Period, 0, 1, timeArray) <= 0) return;
   
   // Work on bar open
   if(timeArray[0] == lastBarTime) 
   {
      ManageOpenTrades();
      return;
   }
   
   // We wait for at least Period + FlatPeriods bars
   int neededBars = InpDonchianPeriod + InpFlatPeriods + 2;
   if(iBars(_Symbol, _Period) < neededBars) return;
   
   // Static latch to ensure we don't try to close trades multiple times per window
   static bool tradesClosedForThisNewsWindow = false;

   // 2. Main News Logic
   if(EnableNewsFilter)
     {
      bool isNews = IsNewsTime(_Symbol);

      // Feature: Close open trades before news if enabled
      if(CloseOpenTradesBeforeHighImpactNews && isNews)
        {
         if(!tradesClosedForThisNewsWindow)
           {
            Print("News window started -> Closing open trades.");
            CloseAllTradesForSymbol(_Symbol);
            tradesClosedForThisNewsWindow = true; // Latch
           }
        }
      else
         if(!isNews)
           {
            // Reset latch when we are out of the news window
            tradesClosedForThisNewsWindow = false;
           }
     }
  
   
   // Check news time
   if(!CanOpenNewTrade(_Symbol))
   {
   // News window active — do not open new trades
      ManageOpenTrades();
      return;
   }

   
   
   // Check if we already have an open position
   bool hasPos = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
      {
         hasPos = true;
         break;
      }
   }
   
   if(hasPos) 
   {
      ManageOpenTrades();
      return; // Only one trade at a time
   }
   
   // Ensure current time is within session
   if(!IsSessionValid()) 
   {
      ManageOpenTrades();
      return;
   }
   
   double upperBands[];
   double lowerBands[];
   ArrayResize(upperBands, InpFlatPeriods + 2);
   ArrayResize(lowerBands, InpFlatPeriods + 2);
   
   for(int k = 1; k <= InpFlatPeriods + 1; k++)
   {
      upperBands[k] = GetHighestHigh(_Symbol, _Period, InpDonchianPeriod, k);
      lowerBands[k] = GetLowestLow(_Symbol, _Period, InpDonchianPeriod, k);
      if(upperBands[k] == 0.0 || lowerBands[k] == 0.0) return; // Wait for valid data
   }
   
   bool isFlatUpper = true;
   bool isFlatLower = true;
   double flatUpLevel = upperBands[2];
   double flatDnLevel = lowerBands[2];
   
   for(int k = 3; k <= InpFlatPeriods + 1; k++)
   {
      // If the upper band isn't identical for the required period, it's not flat
      if(upperBands[k] != flatUpLevel) isFlatUpper = false;
      // If the lower band isn't identical, it's not flat
      if(lowerBands[k] != flatDnLevel) isFlatLower = false;
   }
   
   double close1 = iClose(_Symbol, _Period, 1);
   
   // Bull breakout: band was flat, and the completed bar just broke out of it above
   bool isBullBreakout = (isFlatUpper && close1 > flatUpLevel);
   
   // Bear breakout: band was flat, and the completed bar just broke out of it below
   bool isBearBreakout = (isFlatLower && close1 < flatDnLevel);
   
   double rr = MathMax(1.0, InpRewardRisk);
   int slCandlesVal = MathMax(1, InpSLCandles);
   
   if(isBullBreakout)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = GetLowestLow(_Symbol, _Period, slCandlesVal, 1);
      
      // Fallback if low is somehow above ask (should be rare)
      if(sl >= ask || sl <= 0.0) 
         sl = ask - 100 * _Point;
         
      double slDist = ask - sl;
      double lots = CalculateLotSize(slDist);
      
      sl = NormalizeDouble(sl, _Digits);
      
      if(lots > 0 && trade.Buy(lots, _Symbol, ask, sl, 0, "DC Breakout Buy")) // TP removed
      {
         lastBarTime = timeArray[0];
         GlobalVariableSet(StringFormat("DC_SLDIST_%I64u", trade.ResultDeal()), slDist);
      }
   }
   else if(isBearBreakout)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = GetHighestHigh(_Symbol, _Period, slCandlesVal, 1);
      
      // Fallback if high is somehow below bid
      if(sl <= bid || sl <= 0.0) 
         sl = bid + 100 * _Point;
         
      double slDist = sl - bid;
      double lots = CalculateLotSize(slDist);
      
      sl = NormalizeDouble(sl, _Digits);
      
      if(lots > 0 && trade.Sell(lots, _Symbol, bid, sl, 0, "DC Breakout Sell")) // TP removed
      {
         lastBarTime = timeArray[0];
         GlobalVariableSet(StringFormat("DC_SLDIST_%I64u", trade.ResultDeal()), slDist);
      }
   }
   else
   {
      // Mark bar as processed even if no signal
      lastBarTime = timeArray[0];
   }
   
   ManageOpenTrades();
}
