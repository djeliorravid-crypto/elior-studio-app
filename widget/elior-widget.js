// ===== וידג'ט "אליאור רביד" ל-Scriptable =====
// מציג: משימות היום · יתרת הבנק החודש · יעד החודש
// הנתונים נמשכים חיים מ-Firebase (אותו מקור כמו האפליקציה).
//
// התקנה (פעם אחת):
//   1. התקן את האפליקציה החינמית "Scriptable" מה-App Store
//   2. פתח Scriptable → "+" → הדבק את כל הקובץ הזה → שמור בשם "אליאור"
//   3. לחיצה ארוכה על מסך הבית → "+" → Scriptable → בחר גודל בינוני → הוסף
//   4. לחיצה ארוכה על הוידג'ט → Edit Widget → Script: "אליאור"
//
// אין צורך לעדכן את הקוד שוב — הנתונים מתרעננים לבד.

// --- הגדרות ---
const DB_BASE = "https://elior-studio-default-rtdb.firebaseio.com";
const APP_URL = "https://djeliorravid-crypto.github.io/elior-studio-app/"; // נפתח בלחיצה על הוידג'ט

// --- צבעים (תואם עיצוב האפליקציה) ---
const C = {
  text:   new Color("#F3E9DF"),
  muted:  new Color("#B9A48F"),
  accent: new Color("#E8A24A"),
  good:   new Color("#7BD88F"),
  bad:    new Color("#FF6B6B"),
  track:  new Color("#4A382A"),
};

// --- עזרי נתונים ---
function todayStr() {
  const x = new Date();
  return x.getFullYear() + "-" + String(x.getMonth() + 1).padStart(2, "0") + "-" + String(x.getDate()).padStart(2, "0");
}
function curMonthKey() {
  const x = new Date();
  return x.getFullYear() + "-" + String(x.getMonth() + 1).padStart(2, "0");
}
function asArr(v) {
  if (Array.isArray(v)) return v.filter(Boolean);
  if (v && typeof v === "object") return Object.values(v).filter(Boolean);
  return [];
}
function inCurMonth(s) {
  const d = new Date(s), n = new Date();
  return d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth();
}
function money(n) {
  n = Math.round(Number(n) || 0);
  return "₪" + n.toLocaleString("en-US");
}

// --- שליפת נתונים (רק מה שצריך, במקביל) ---
async function getKey(key) {
  const req = new Request(DB_BASE + "/studio_data/" + key + ".json");
  req.timeoutInterval = 25;
  const txt = await req.loadString();
  const code = req.response ? req.response.statusCode : 200;
  if (code >= 400) throw new Error("HTTP " + code + (txt ? " · " + txt.slice(0, 60) : ""));
  if (!txt || txt === "null") return null;
  let j;
  try { j = JSON.parse(txt); } catch (e) { throw new Error("תשובה לא-JSON: " + txt.slice(0, 60)); }
  if (j && j.error) throw new Error("Firebase: " + j.error);
  return j;
}
async function fetchData() {
  const keys = ["daily_tasks", "income", "expenses", "recurring_expenses", "monthlyGoal"];
  try {
    const vals = await Promise.all(keys.map(getKey));
    const out = {};
    keys.forEach((k, i) => { out[k] = vals[i]; });
    return out;
  } catch (e) {
    return { __err: String((e && e.message) || e) };
  }
}

// --- חישובים (זהים ללוגיקה באפליקציה) ---
function compute(data) {
  const today = todayStr();
  const mKey  = curMonthKey();

  const daily  = asArr(data.daily_tasks).filter(t => t.date === today);
  const total  = daily.length;
  const done   = daily.filter(t => t.done).length;
  const open   = daily.filter(t => !t.done)
                      .sort((a, b) => new Date(a.createdAt || 0) - new Date(b.createdAt || 0))
                      .map(t => t.text);

  const income = asArr(data.income).filter(i => inCurMonth(i.date));
  const exps   = asArr(data.expenses).filter(e => inCurMonth(e.date));
  const recur  = asArr(data.recurring_expenses).filter(r => {
    if (r.startMonth && r.startMonth > mKey) return false;
    if (r.endMonth && r.endMonth < mKey) return false;
    return true;
  });

  const paidInc    = income.filter(i => (i.status || "pending") === "paid")
                           .reduce((s, i) => s + Number(i.amount || 0), 0);
  const pendingInc = income.filter(i => (i.status || "pending") !== "paid")
                           .reduce((s, i) => s + Number(i.amount || 0), 0);
  const paidExp    = exps.filter(e => e.paid).reduce((s, e) => s + Number(e.amount || 0), 0)
                   + recur.filter(r => r.paidMonths && r.paidMonths[mKey])
                          .reduce((s, r) => s + Number(r.amount || 0), 0);

  const balance = paidInc - paidExp;
  const goal    = (data.monthlyGoal && Number(data.monthlyGoal.v)) || 0;
  const goalPct = goal > 0 ? Math.min(100, Math.round((paidInc / goal) * 100)) : 0;

  return { total, done, open, paidInc, pendingInc, balance, goal, goalPct };
}

// --- רכיבי תצוגה ---
function addBar(stack, pct, width, height) {
  const track = stack.addStack();
  track.size = new Size(width, height);
  track.backgroundColor = C.track;
  track.cornerRadius = height / 2;
  const fillW = Math.max(0, Math.min(width, (width * pct) / 100));
  if (fillW > 0) {
    const fill = track.addStack();
    fill.size = new Size(fillW, height);
    fill.backgroundColor = C.accent;
    fill.cornerRadius = height / 2;
  }
}
function row(stack, txt, font, color, align = "right") {
  const t = stack.addText(txt);
  t.font = font;
  t.textColor = color;
  if (align === "right") t.rightAlignText();
  else if (align === "center") t.centerAlignText();
  return t;
}

// --- בניית הוידג'ט ---
function buildWidget(m, family) {
  const w = new ListWidget();
  const bg = new LinearGradient();
  bg.colors = [new Color("#2A1F17"), new Color("#16100B")];
  bg.locations = [0, 1];
  bg.startPoint = new Point(0, 0);
  bg.endPoint = new Point(1, 1);
  w.backgroundGradient = bg;
  w.setPadding(14, 15, 14, 15);
  w.url = APP_URL;

  if (m && m.__err) {
    row(w, "שגיאת חיבור", Font.boldSystemFont(15), C.bad, "center");
    w.addSpacer(6);
    const e = row(w, m.__err, Font.systemFont(11), C.muted, "center");
    e.lineLimit = 4;
    return w;
  }

  const small = family === "small";

  if (small) {
    // קומפקטי: משימות + יתרה
    row(w, "משימות היום", Font.semiboldSystemFont(12), C.muted);
    row(w, m.total ? `${m.done}/${m.total} בוצעו` : "אין משימות", Font.boldSystemFont(24), C.accent);
    w.addSpacer(6);
    row(w, "יתרת הבנק החודש", Font.semiboldSystemFont(12), C.muted);
    row(w, money(m.balance), Font.boldSystemFont(22), m.balance >= 0 ? C.good : C.bad);
    w.addSpacer();
    return w;
  }

  // כותרת
  const head = w.addStack();
  head.addSpacer();
  row(head, "אליאור רביד", Font.boldSystemFont(15), C.accent);
  w.addSpacer(8);

  // יתרת הבנק
  row(w, "יתרת הבנק החודש", Font.semiboldSystemFont(12), C.muted);
  row(w, money(m.balance), Font.boldSystemFont(26), m.balance >= 0 ? C.good : C.bad);
  row(w, `התקבל ${money(m.paidInc)}  ·  ממתין ${money(m.pendingInc)}`, Font.systemFont(11), C.muted);

  // יעד החודש
  if (m.goal > 0) {
    w.addSpacer(8);
    const gl = w.addStack();
    gl.addSpacer();
    row(gl, `יעד החודש · ${m.goalPct}%`, Font.semiboldSystemFont(11), C.muted);
    w.addSpacer(4);
    const barRow = w.addStack();
    barRow.addSpacer();
    addBar(barRow, m.goalPct, family === "large" ? 300 : 280, 7);
  }

  w.addSpacer(10);

  // משימות היום
  const tHead = w.addStack();
  tHead.addSpacer();
  const label = m.total ? `משימות היום · ${m.done}/${m.total}` : "משימות היום";
  row(tHead, label, Font.semiboldSystemFont(13), C.text);
  w.addSpacer(4);

  if (m.total === 0) {
    row(w, "אין משימות להיום ☀️", Font.systemFont(13), C.muted);
  } else if (m.open.length === 0) {
    row(w, "סיימת הכל — כל הכבוד! 🎉", Font.semiboldSystemFont(14), C.good);
  } else {
    const max = family === "large" ? 7 : 3;
    m.open.slice(0, max).forEach(txt => {
      const r = w.addStack();
      r.addSpacer();
      const t = r.addText("• " + txt);
      t.font = Font.systemFont(13);
      t.textColor = C.text;
      t.lineLimit = 1;
      t.rightAlignText();
    });
    if (m.open.length > max) {
      row(w, `ועוד ${m.open.length - max}…`, Font.systemFont(12), C.muted);
    }
  }

  w.addSpacer();
  const time = new Date().toLocaleTimeString("he-IL", { hour: "2-digit", minute: "2-digit" });
  row(w, "עודכן " + time, Font.systemFont(10), C.muted, "left");
  return w;
}

// --- ריצה ---
const family = config.widgetFamily || "medium";
const data   = await fetchData();
const m      = data && data.__err ? data : compute(data);
const widget = buildWidget(m, family);

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  if (family === "small") await widget.presentSmall();
  else if (family === "large") await widget.presentLarge();
  else await widget.presentMedium();
}
widget.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000);
Script.complete();
