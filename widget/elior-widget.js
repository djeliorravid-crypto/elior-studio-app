// וידג'ט "משימות היום" — אליאור רביד (Scriptable)
// מד התקדמות למעלה + רשימת המשימות מתחתיו. נתונים חיים מ-Firebase.
const DB_BASE = "https://elior-studio-default-rtdb.firebaseio.com";
// לחיצה על הוידג'ט פותחת את האפליקציה (בדפדפן ברירת המחדל)
const TAP_URL = "https://djeliorravid-crypto.github.io/elior-studio-app/";

const C = {
  text:   new Color("#F3E9DF"),
  muted:  new Color("#B9A48F"),
  dim:    new Color("#7C6B5A"),
  accent: new Color("#E8A24A"),
  good:   new Color("#7BD88F"),
  bad:    new Color("#FF6B6B"),
  track:  new Color("#4A382A"),
};

function cleanUrl(u) {
  const ok = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:/._-~?=&%#";
  let o = "";
  for (let i = 0; i < u.length; i++) { if (ok.indexOf(u[i]) >= 0) o += u[i]; }
  return o;
}
function todayStr() {
  const x = new Date();
  return x.getFullYear() + "-" + String(x.getMonth() + 1).padStart(2, "0") + "-" + String(x.getDate()).padStart(2, "0");
}
function asArr(v) {
  if (Array.isArray(v)) return v.filter(Boolean);
  if (v && typeof v === "object") return Object.values(v).filter(Boolean);
  return [];
}

async function fetchDaily() {
  const url = cleanUrl(DB_BASE + "/studio_data/daily_tasks.json");
  try {
    const req = new Request(url);
    req.timeoutInterval = 25;
    const txt = await req.loadString();
    const code = req.response ? req.response.statusCode : 200;
    if (code >= 400) return { err: "HTTP " + code };
    if (!txt || txt === "null") return { list: [] };
    const j = JSON.parse(txt);
    if (j && j.error) return { err: String(j.error) };
    return { list: asArr(j) };
  } catch (e) {
    return { err: String((e && e.message) || e) };
  }
}

function compute(list) {
  const today = todayStr();
  const items = list.filter(t => t && t.date === today);
  items.sort((a, b) => {
    if (a.done !== b.done) return a.done ? 1 : -1;
    return new Date(a.createdAt || 0) - new Date(b.createdAt || 0);
  });
  const total = items.length;
  const done = items.filter(t => t.done).length;
  const pct = total ? Math.round((done / total) * 100) : 0;
  return { items, total, done, pct };
}

// מד התקדמות אופקי — מתמלא מימין (RTL)
function addBar(container, pct, width, height) {
  const track = container.addStack();
  track.size = new Size(width, height);
  track.backgroundColor = C.track;
  track.cornerRadius = height / 2;
  const fillW = (width * pct) / 100;
  if (fillW > 0) {
    track.addSpacer();
    const fill = track.addStack();
    fill.size = new Size(Math.max(fillW, height), height);
    fill.backgroundColor = pct >= 100 ? C.good : C.accent;
    fill.cornerRadius = height / 2;
  }
}
function rightText(stack, txt, font, color) {
  const t = stack.addText(txt);
  t.font = font;
  t.textColor = color;
  t.rightAlignText();
  return t;
}

function buildWidget(state, family) {
  const w = new ListWidget();
  const bg = new LinearGradient();
  bg.colors = [new Color("#2A1F17"), new Color("#16100B")];
  bg.locations = [0, 1];
  bg.startPoint = new Point(0, 0);
  bg.endPoint = new Point(1, 1);
  w.backgroundGradient = bg;
  w.setPadding(14, 15, 14, 15);
  w.url = cleanUrl(TAP_URL);

  if (state.err) {
    rightText(w, "שגיאת חיבור", Font.boldSystemFont(15), C.bad).centerAlignText();
    w.addSpacer(4);
    const e = rightText(w, state.err, Font.systemFont(11), C.muted);
    e.centerAlignText();
    e.lineLimit = 3;
    return w;
  }

  const m = state.m;
  const small = family === "small";
  const barW = small ? 120 : (family === "large" ? 320 : 300);

  // כותרת
  const head = w.addStack();
  head.addSpacer();
  rightText(head, "משימות היום", Font.boldSystemFont(small ? 13 : 15), C.accent);
  w.addSpacer(small ? 6 : 8);

  // מד התקדמות + אחוז
  const meter = w.addStack();
  meter.centerAlignContent();
  const pctTxt = meter.addText(m.pct + "%");
  pctTxt.font = Font.boldSystemFont(small ? 18 : 22);
  pctTxt.textColor = m.pct >= 100 ? C.good : C.accent;
  meter.addSpacer(8);
  meter.addSpacer();
  addBar(meter, m.pct, barW, small ? 7 : 9);
  w.addSpacer(4);
  rightText(w, m.total ? `${m.done} מתוך ${m.total} בוצעו` : "אין משימות להיום", Font.semiboldSystemFont(small ? 11 : 12), C.muted);

  if (m.total === 0) {
    w.addSpacer(8);
    rightText(w, "הוסף משימה ראשונה ☀️", Font.systemFont(small ? 12 : 13), C.dim);
    w.addSpacer();
    return w;
  }

  w.addSpacer(small ? 6 : 10);

  // רשימת המשימות
  const max = small ? 3 : (family === "large" ? 11 : 5);
  m.items.slice(0, max).forEach(t => {
    const r = w.addStack();
    r.spacing = 6;
    r.centerAlignContent();
    r.addSpacer();
    const txt = r.addText(t.text);
    txt.font = Font.systemFont(small ? 12 : 13);
    txt.textColor = t.done ? C.dim : C.text;
    txt.rightAlignText();
    txt.lineLimit = 1;
    const mark = r.addText(t.done ? "✓" : "○");
    mark.font = Font.boldSystemFont(small ? 12 : 14);
    mark.textColor = t.done ? C.good : C.accent;
    if (!small) w.addSpacer(4);
  });
  if (m.items.length > max) {
    rightText(w, `ועוד ${m.items.length - max}…`, Font.systemFont(small ? 11 : 12), C.muted);
  }

  w.addSpacer();
  const time = new Date().toLocaleTimeString("he-IL", { hour: "2-digit", minute: "2-digit" });
  const tEl = rightText(w, "עודכן " + time, Font.systemFont(9), C.dim);
  tEl.leftAlignText();
  return w;
}

const family = config.widgetFamily || "medium";
const res = await fetchDaily();
const state = res.err ? { err: res.err } : { m: compute(res.list) };
const widget = buildWidget(state, family);

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  if (family === "small") await widget.presentSmall();
  else if (family === "large") await widget.presentLarge();
  else await widget.presentMedium();
}
widget.refreshAfterDate = new Date(Date.now() + 60 * 1000);
Script.complete();
