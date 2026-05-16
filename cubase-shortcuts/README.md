# Cubase Plugin Shortcuts

קיצורי מקלדת לפתיחה אוטומטית של פלאגינים ב-Cubase 15 על Mac באמצעות [Hammerspoon](https://www.hammerspoon.org/).

ברירת המחדל: **`Cmd + P`** בתוך Cubase → פותח את **Pro-Q 4** באינסרט הפנוי הבא של הטראק הנבחר.

---

## דרישות מקדימות

- Mac עם macOS 11 ומעלה
- Cubase 15 (עובד גם על גרסאות קודמות ועל Nuendo)
- [Hammerspoon](https://www.hammerspoon.org/) - הסקריפט יתקין אוטומטית אם יש לך [Homebrew](https://brew.sh)

---

## התקנה

מתוך תיקיית `cubase-shortcuts/`:

```bash
./install.sh
```

הסקריפט:
1. מתקין Hammerspoon אם צריך (דרך Homebrew)
2. מגבה הגדרות Hammerspoon קיימות (אם יש)
3. מעתיק את הקונפיג ל-`~/.hammerspoon/`
4. פותח את Hammerspoon ואת הגדרות ה-Accessibility

---

## כיול חד-פעמי

לפני שימוש ראשון, צריך לכייל פעם אחת איפה נמצא סלוט האינסרט באולפן שלך:

1. פתח את Cubase ובחר טראק
2. ודא שהאינספקטור פתוח ושהקטע **Inserts** מורחב
3. הקש `Cmd + Option + Shift + I`
4. תופיע הודעה: *"מצב כיול: לחץ עם העכבר על סלוט אינסרט פנוי"*
5. לחץ על סלוט אינסרט פנוי
6. תופיע הודעת אישור עם המיקום שנשמר

הכיול נשמר ב-`~/.hammerspoon/cubase_calibration.json` ולא צריך לחזור עליו אלא אם הזזת את חלון Cubase משמעותית או שינית רזולוציה.

---

## שימוש

1. בחר טראק ב-Cubase
2. הקש `Cmd + P`
3. Pro-Q 4 ייפתח אוטומטית באינסרט הפנוי הבא ✨

---

## הוספת פלאגינים נוספים

ערוך את `~/.hammerspoon/plugins.lua` והוסף שורות לפי הפורמט:

```lua
return {
    { mods = {"cmd"},        key = "p", name = "Pro-Q 4"  },
    { mods = {"cmd", "alt"}, key = "c", name = "Pro-C 2"  },
    { mods = {"cmd", "alt"}, key = "l", name = "Pro-L 2"  },
}
```

- `mods` - מקשים מודיפיירים: `"cmd"`, `"alt"`, `"shift"`, `"ctrl"`
- `key` - האות / מספר / מקש (`"p"`, `"1"`, `"f1"`)
- `name` - השם המדויק שמופיע בחיפוש הפלאגינים של Cubase

אחרי עריכה: בתפריט Hammerspoon → **Reload Config**.

---

## פתרון בעיות

**הפלאגין לא נטען / נטען לא נכון**
- ודא ששם הפלאגין ב-`plugins.lua` מדויק (כמו בחיפוש של Cubase)
- ודא שיש סלוט אינסרט פנוי בטראק
- כייל מחדש אם הזזת את חלון Cubase

**הקיצור לא עובד בכלל**
- בדוק ש-Hammerspoon רץ (אייקון פטיש בסרגל)
- בדוק שיש ל-Hammerspoon הרשאת Accessibility (System Settings → Privacy & Security → Accessibility)
- בתפריט Hammerspoon → Reload Config

**הקיצור עובד באפליקציה הלא נכונה**
- הסקריפט מזהה את Cubase לפי שם החלון ("Cubase" או "Nuendo"). אם השם שונה אצלך - ערוך את `CUBASE_PATTERNS` בראש `init.lua`.

**Cmd+P התנגש עם Project Setup ב-Cubase**
- ב-Cubase, Cmd+P היה בעבר Project Setup. אחרי ההתקנה הוא יפתח את Pro-Q 4 במקום. Project Setup עדיין נגיש מהתפריט `Project → Project Setup` (או הקצה לו קיצור אחר ב-Key Commands של Cubase).
- אם תרצה קיצור שלא מתנגש בכלום, החלף ב-`plugins.lua` ל-`{"cmd","alt"}` + `"p"` (= Cmd+Option+P).

---

## מבנה הקבצים

```
cubase-shortcuts/
├── README.md             ← הקובץ הזה
├── install.sh            ← סקריפט התקנה
└── hammerspoon/
    ├── init.lua          ← הלוגיקה הראשית
    └── plugins.lua       ← רשימת הקיצורים והפלאגינים
```
