// Maestro smoke test — run before every deploy:  NODE_PATH=$(npm root -g) node tests/smoke.js
// Serves the repo itself, drives the app in Chromium and checks the money/receipt/calendar paths.
// Morning (receipts) and calendar are mocked; nothing real is touched.
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const TYPES = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };
const srv = http.createServer((q, r) => { let f = path.join(ROOT, decodeURIComponent(q.url.split('?')[0])); if (f.endsWith('/')) f += 'index.html';
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); r.end(); return; } r.writeHead(200, { 'content-type': TYPES[path.extname(f)] || 'application/octet-stream' }); r.end(b); }); });
const results = []; const ok = (name, cond, extra) => { results.push([cond ? 'PASS' : 'FAIL', name, extra || '']); };
// split files: every ?h= in index.html must match the file (else phones get a stale mix)
{ const crypto = require('crypto'); const html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
  for (const f of ['js/app.js', 'css/base.css', 'css/spent.css']) { const m = html.match(new RegExp(f.replace('.', '\\.') + '\\?h=([0-9a-f]+)'));
    const h = crypto.createHash('sha1').update(fs.readFileSync(path.join(ROOT, f))).digest('hex').slice(0, 10);
    ok('asset ' + f + ' hash is current', m && m[1] === h, m ? m[1] + ' vs ' + h : 'not linked'); } }
(async () => {
  await new Promise(r => srv.listen(0, r)); const port = srv.address().port;
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.route(/firebase|gstatic|googleapis|workers\.dev/, r => r.abort());
  await p.route(/greeninvoice/, r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ token: 't', expires: 9e9, id: 'DOC1', number: 101, url: { he: 'https://x' } }) }));
  await p.addInitScript(() => {
    if (sessionStorage.getItem('seeded')) return; sessionStorage.setItem('seeded', '1');
    localStorage.clear();
    localStorage.setItem('ui_skin', 'spent'); localStorage.setItem('fc_seeded_2709', '1'); localStorage.setItem('ios_cal_granted', '1');
    localStorage.setItem('morning_api_id', 'x'); localStorage.setItem('morning_api_secret', 'y');
    const t = new Date(), iso = d => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
    const day = n => { const d = new Date(t); d.setDate(d.getDate() + n); return iso(d); };
    localStorage.setItem('s_income', JSON.stringify([{ id: 'i1', client: 'מיה', clientName: 'מיה', category: 'הפקה', amount: 3000, date: day(-1), status: 'paid' }, { id: 'i2', client: 'רן', clientName: 'רן', amount: 1000, date: day(-20), status: 'pending' }]));
    localStorage.setItem('s_expenses', JSON.stringify([{ id: 'e1', description: 'שופרסל', amount: 86, date: day(0), category: '', paid: true }, { id: 'e2', description: 'נגן', amount: 600, date: day(0), category: 'נגנים', paid: true }]));
    localStorage.setItem('s_fixed_costs', JSON.stringify([{ id: 'f1', name: 'ארנונה', amount: 651, group: 'living', day: 15 }, { id: 'f2', name: 'מי עדן', amount: 180, amount2: 44, altAnchor: iso(t).slice(0, 7), group: 'living' }]));
    localStorage.setItem('s_clients', JSON.stringify([{ id: 'c1', name: 'מיה', phone: '0501234567', status: 'active' }]));
    localStorage.setItem('s_productions', JSON.stringify([{ id: 'p1', title: 'אלבום', name: 'אלבום', client: 'רן', status: 'active', lane: 'urgent' }]));
    window.Capacitor = { isNativePlatform: () => false, Plugins: { IosCalendar: { listEvents: async () => ({ events: [{ id: 'k1', date: day(2), time: '10:00', endTime: '12:00', title: 'פגישה', calendar: 'W' }] }), addListener: () => {} } } };
  });
  await p.goto('http://localhost:' + port + '/index.html'); await p.waitForTimeout(2500);
  ok('loads without errors', errs.length === 0, errs.join(' | '));
  await p.evaluate(() => { document.getElementById('login-pass').value = PASS; doLogin(); }); await p.waitForTimeout(800);
  ok('home renders', await p.evaluate(() => !!document.querySelector('#sp-lobby .fz-me')));
  const before = await p.evaluate(() => JSON.stringify(['income', 'expenses', 'fixed_costs', 'clients', 'productions'].map(k => load(k))));
  for (const pg of ['productions', 'income', 'expenses', 'fixed', 'schedule', 'profiles', 'whatsapp', 'installments', 'proposals', 'contracts', 'students', 'workshops', 'daily', 'dashboard']) {
    const n = errs.length; await p.evaluate(pg => { chooseMode('business'); showPage(pg); }, pg); await p.waitForTimeout(350);
    ok('page ' + pg + ' opens', errs.length === n, errs.slice(n).join(' | '));
  }
  ok('browsing changes no data', before === await p.evaluate(() => JSON.stringify(['income', 'expenses', 'fixed_costs', 'clients', 'productions'].map(k => load(k)))));
  // receipt path
  await p.evaluate(() => showPage('income')); await p.waitForTimeout(400);
  await p.evaluate(() => { const r = [...document.querySelectorAll('#inc-spent .fz-row')].find(x => x.textContent.includes('מיה')); r.click(); }); await p.waitForTimeout(400);
  const acts = await p.evaluate(() => [...document.querySelectorAll('#spent-sheet.open .ss-btn')].map(x => x.textContent));
  ok('paid income offers a receipt', acts.some(a => a.includes('צור קבלה')), acts.join(','));
  await p.locator('#spent-sheet .ss-btn', { hasText: 'צור קבלה' }).click(); await p.waitForTimeout(700);
  await p.locator('#morning-receipt-overlay button', { hasText: 'צור קבלה' }).click(); await p.waitForTimeout(2000);
  ok('receipt is created and saved', await p.evaluate(() => load('income').find(i => i.id === 'i1').morningDocId === 'DOC1'));
  // expenses
  await p.evaluate(() => { document.querySelectorAll('.open').forEach(x => x.classList.remove('open')); showPage('expenses'); }); await p.waitForTimeout(400);
  ok('expense categories show', await p.evaluate(() => document.querySelectorAll('#exp-spent .ex-cat').length >= 2));
  // fixed costs
  await p.evaluate(() => showPage('fixed')); await p.waitForTimeout(400);
  await p.click('.fcs-cat .ex-cat >> nth=0'); await p.waitForTimeout(300);
  await p.click('.fcs-items .fcs-tick >> nth=0'); await p.waitForTimeout(300);
  ok('fixed cost can be ticked', await p.evaluate(() => load('fixed_costs').some(x => x.paidMonths && Object.keys(x.paidMonths).length)));
  ok('alternating amount this month', await p.evaluate(() => _fcAmtIn(load('fixed_costs').find(x => x.id === 'f2'), new Date()) === 180));
  // calendar + free times + offer
  await p.evaluate(() => showPage('schedule')); await p.waitForTimeout(500);
  ok('calendar strip', await p.evaluate(() => document.querySelectorAll('.fz-days button').length > 100));
  const slots = await p.evaluate(() => { window._freeOpt = { from: 600, range: 'month', min: 3, count: 2 }; return _freeSlots(window._freeOpt).length; });
  ok('free times found', slots > 3, String(slots));
  await p.evaluate(() => offerImport('יום ב׳ 12.10 · 10:00–14:00')); await p.waitForTimeout(400);
  ok('offer import asks the date', await p.evaluate(() => (document.querySelector('#spent-sheet.open .ss-t') || {}).textContent === 'איזה תאריך נבחר?'));
  ok('no errors overall', errs.length === 0, errs.join(' | '));
  await b.close(); srv.close();
  const fails = results.filter(r => r[0] === 'FAIL');
  results.forEach(r => console.log(r[0], '·', r[1], r[2] ? '— ' + r[2] : ''));
  console.log(fails.length ? '\n✗ ' + fails.length + ' FAILED' : '\n✓ ALL ' + results.length + ' PASSED');
  process.exit(fails.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
