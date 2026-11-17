//+------------------------------------------------------------------+
//| YY_Panel.mqh — แผงข้อความภาษาไทยบนกราฟ (OBJ_LABEL ทีละบรรทัด)       |
//+------------------------------------------------------------------+
#ifndef YY_PANEL_MQH
#define YY_PANEL_MQH

class CYYPanel
{
private:
   string m_prefix;
   int    m_x, m_y, m_lineH, m_fontSize, m_lines;
   string m_font;

public:
   void Init(const string prefix, const int x = 12, const int y = 24, const int fontSize = 9)
   {
      m_prefix = prefix; m_x = x; m_y = y; m_fontSize = fontSize;
      m_lineH = (int)MathRound(fontSize * 1.9);
      m_font = "Tahoma";   // รองรับภาษาไทย
      m_lines = 0;
   }

   void SetLine(const int i, const string text, const color clr = clrWhiteSmoke)
   {
      string name = m_prefix + IntegerToString(i);
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_y + i * m_lineH);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, m_fontSize);
         ObjectSetString (0, name, OBJPROP_FONT, m_font);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetString (0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      if(i + 1 > m_lines) m_lines = i + 1;
   }

   void Destroy()
   {
      ObjectsDeleteAll(0, m_prefix);
      m_lines = 0;
   }
};

#endif
