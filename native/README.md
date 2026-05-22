# כושר ותזונה — Native iOS App

האפליקציה הזו עוטפת את אתר "כושר ותזונה" כאפליקציית iOS אמיתית.

## מה צריך פעם אחת

1. **Xcode** מותקן ב-Mac (מ-App Store, ~10GB)
2. **חשבון Apple ID חינמי** (לא חייב להיות Apple Developer)

## להריץ על האייפון

```bash
cd native
npm run ios
```

זה יסנכרן את קבצי האתר העדכניים ויפתח את Xcode.

ב-Xcode:
1. **Signing & Capabilities** → בחר "Add Account..." → התחבר עם ה-Apple ID שלך
2. ב-**Team** בחר את ה-Apple ID שלך (Personal Team)
3. ב-**Bundle Identifier** ודא שמופיע `com.eliorravid.fitness` (או שנה אם יש קונפליקט)
4. חבר את האייפון בכבל למק
5. בחר את האייפון מהרשימה למעלה (לא Simulator)
6. לחץ **▶ Run** (חץ הפעלה)

בפעם הראשונה — באייפון: **Settings → General → VPN & Device Management** → סמוך על המפתח שלך.

## לעדכן את האפליקציה אחרי שינויים באתר

```bash
cd native
npm run sync
```

ואז ב-Xcode → ▶ Run שוב.

## הערות

- אפליקציה עם Apple ID חינמי פגה כל 7 ימים — תצטרך לחבר את האייפון ולהריץ Run שוב
- אם תרצה App Store / שתישאר 365 יום — תצטרך Apple Developer Account ($99/שנה)
- ההתראות **native** עובדות גם כשהאפליקציה סגורה לחלוטין וגם בנעילה
