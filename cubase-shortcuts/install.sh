#!/usr/bin/env bash
# התקנה אוטומטית של Cubase Shortcuts ל-Hammerspoon

set -e

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS_DIR="$HOME/.hammerspoon"

echo "===== Cubase Shortcuts - התקנה ====="

# 1. וידוא ש-Hammerspoon מותקן
if [ ! -d "/Applications/Hammerspoon.app" ]; then
    echo ""
    echo "Hammerspoon לא מותקן."
    if command -v brew >/dev/null 2>&1; then
        echo "מתקין דרך Homebrew..."
        brew install --cask hammerspoon
    else
        echo "Homebrew לא מותקן."
        echo "התקן ידנית מ: https://www.hammerspoon.org/"
        echo "או התקן Homebrew מ: https://brew.sh ואז הרץ שוב את הסקריפט הזה."
        exit 1
    fi
fi

# 2. גיבוי הגדרות קיימות (אם יש)
if [ -d "$HS_DIR" ] && [ "$(ls -A "$HS_DIR" 2>/dev/null)" ]; then
    BACKUP="$HS_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    echo ""
    echo "מגבה הגדרות Hammerspoon קיימות ל:"
    echo "  $BACKUP"
    cp -r "$HS_DIR" "$BACKUP"
fi

# 3. העתקת קבצי הקונפיג
mkdir -p "$HS_DIR"
cp "$SOURCE_DIR/hammerspoon/init.lua"    "$HS_DIR/init.lua"
cp "$SOURCE_DIR/hammerspoon/plugins.lua" "$HS_DIR/plugins.lua"
echo ""
echo "✓ קבצי הקונפיג הועתקו ל-$HS_DIR"

# 4. פתיחת Hammerspoon
open -a Hammerspoon

# 5. פתיחת הגדרות Accessibility
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

cat <<'EOF'

===========================================
✓ ההתקנה הושלמה!
===========================================

צעדים אחרונים:

1. אשר ל-Hammerspoon הרשאת "Accessibility"
   (החלון אמור להיפתח לך אוטומטית)

2. בתפריט Hammerspoon (אייקון של פטיש למעלה בסרגל המק):
   → Reload Config

3. פתח את Cubase 15 ובחר טראק כלשהו

4. בדוק קודם אם זיהוי אוטומטי עובד אצלך:
   - הקש  Cmd + Option + Shift + D  (אבחון)
   - אם רשום "✓ זיהוי אוטומטי עובד!" - דלג לשלב 6, לא צריך לכייל!

5. אם הזיהוי האוטומטי לא עבד - כיול חד-פעמי:
   - הקש  Cmd + Option + Shift + I
   - תופיע הודעה: "מצב כיול: לחץ עם העכבר על סלוט אינסרט פנוי"
   - לחץ עם העכבר על סלוט אינסרט פנוי באינספקטור
   - תופיע הודעת אישור עם המיקום שנשמר

6. (אופציונלי) בדיקת כיול לפני שימוש אמיתי:
   - הקש  Cmd + Option + Shift + T  (טסט)
   - הסקריפט יקליק על המיקום שזוהה, בלי להקליד שום פלאגין
   - אם נפתח חלון בחירת הפלאגין במקום הנכון - הכל מוכן

7. מעכשיו: Cmd + P בתוך Cubase
   יפתח את Pro-Q 4 באינסרט הפנוי הבא של הטראק הנבחר ✨

קיצורי עזר:
  Cmd + Option + Shift + D  →  אבחון (מה עובד ומה לא)
  Cmd + Option + Shift + I  →  כיול ידני
  Cmd + Option + Shift + T  →  בדיקת מיקום בלי הקלדה

הערות:
- Cmd+P באפליקציות אחרות (Word, דפדפן וכו') ממשיך לעבוד כרגיל.
- אם הלייאאוט שלך משתנה - הקש שוב Cmd+Option+Shift+I לכיול מחדש.
- להוספת פלאגינים נוספים: ערוך את $HOME/.hammerspoon/plugins.lua

EOF
