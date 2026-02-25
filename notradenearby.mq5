//+------------------------------------------------------------------+
//|                                                notradenearby.mq5 |
//|                                                             Nick |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Nick"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Input                                                            |
//+------------------------------------------------------------------+
input bool inBuy = true;
input double lot = 0.01;
input double distancePip = 10;
input double InpStopLoss = 10;
input double InpTakeProfit = 10;
input int takeprofit = 2000;

//--- Globals
CTrade        trade;
CPositionInfo position;
CAccountInfo  account;

double pipSize;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create timer
   EventSetTimer(60);
   pipSize = (Digits() == 5 || Digits() == 3) ? 10.0 * _Point : _Point;
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl,tp;
   if (InpStopLoss == 0)
   {
      sl = 0;
   }
   else
   {
      sl = ask - InpTakeProfit*pipSize;
   }
   
   if (InpTakeProfit == 0)
   {
      tp = 0;
   }
   else
   {
     rbrbbbbtp = ask + InpTakeProfit*pipSize;
   }   
   
   if(!IsTradeNearby(distancePip))
   {
      trade.Buy(lot,_Symbol,ask,sl,tp,"");
   }
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   
  }
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
//---
   double ret=0.0;
//---

//---
   return(ret);
  }
//+------------------------------------------------------------------+
//| TesterInit function                                              |
//+------------------------------------------------------------------+
void OnTesterInit()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| TesterPass function                                              |
//+------------------------------------------------------------------+
void OnTesterPass()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| TesterDeinit function                                            |
//+------------------------------------------------------------------+
void OnTesterDeinit()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int32_t id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| BookEvent function                                               |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
  {
//---
   
  }
//+------------------------------------------------------------------+

bool IsTradeNearby(double RangePip)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   //+---Check open position
   for(int i = 0; i < PositionsTotal(); i++)
   {
    if(PositionGetTicket(i))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);

            if(MathAbs(price - bid) <= RangePip * pipSize)
               return true;
         }
      }
   }
   
   // --- Check Pending Orders (Limit Orders Only)
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderGetTicket(i))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

            if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
            {
               double price = OrderGetDouble(ORDER_PRICE_OPEN);

               if(MathAbs(price - bid) <= RangePip * pipSize)
                  return true;
            }
         }
      }
   }

   return false;
}