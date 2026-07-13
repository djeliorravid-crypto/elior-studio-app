// ═════════════════════════════════════════════════════════════════
//  Ravid Studio — WhatsApp webhook receiver + sender
//  Runs as a Cloudflare Worker. Meta (via DualHook coexistence)
//  delivers message webhooks here; we answer the hub.challenge
//  verification handshake and write a compact record of every
//  incoming customer message + every reply Elior sends from the
//  WhatsApp Business app into the app's Firebase RTDB, where the
//  "ממתינים לתשובה" screen reads it.
//
//  /send — replies FROM the app, via Meta's Graph API. Requires two
//  SECRETS configured in the Cloudflare dashboard (Settings →
//  Variables and Secrets — NEVER hardcoded here, this file is public):
//    WHATSAPP_TOKEN — the Meta access token
//    SEND_SECRET    — a password of your choosing; the app asks for
//                     it once and sends it with every /send call
//
//  HOURLY SERVER PUSH (v8) — the worker itself reminds Elior's iPhone
//  "X אנשים מחכים לתשובה" through Apple Push, so reminders arrive even
//  when the app has been closed for days. Needs:
//    • a Cron Trigger:  Settings → Triggers → Cron Triggers → 0 * * * *
//    • three more secrets: APNS_KEY (the full contents of the .p8 key
//      file from Apple Developer → Keys), APNS_KEY_ID, APNS_TEAM_ID
//  Without them the cron runs and quietly does nothing (result logged
//  to /whatsapp/pushlog for debugging).
//
//  Deploy: Cloudflare dashboard → Workers → Create → paste → Deploy.
//  The public URL of this worker is the "Webhook URL" DualHook asks
//  for, and VERIFY_TOKEN below is the "Verify token".
// ═════════════════════════════════════════════════════════════════

const VERIFY_TOKEN = 'ravid-studio-whatsapp-2026';
const FIREBASE = 'https://elior-studio-default-rtdb.firebaseio.com/whatsapp';
const PHONE_ID = '1246363738550836';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type'
};
// Whitespace-proof secret: pasted values often carry a stray trailing
// space or newline — never let that break auth or signatures.
function sendSecret(env) {
  return String((env && env.SEND_SECRET) || '').trim();
}
function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status: status || 200,
    headers: { 'Content-Type': 'application/json', ...CORS }
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    // Meta's one-time webhook verification handshake
    if (request.method === 'GET') {
      if (url.searchParams.get('hub.mode') === 'subscribe' &&
          url.searchParams.get('hub.verify_token') === VERIFY_TOKEN) {
        return new Response(url.searchParams.get('hub.challenge') || '', { status: 200 });
      }
      return new Response('ravid-studio-whatsapp-webhook', { status: 200 });
    }

    if (request.method !== 'POST') return new Response('ok', { status: 200 });

    // ── shared bits for the app-facing endpoints ──
    const graphMsg = (body) => fetch('https://graph.facebook.com/v21.0/' + PHONE_ID + '/messages', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + env.WHATSAPP_TOKEN, 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    const markRead = async (id) => {
      if (!id) return;
      try {
        await graphMsg({ messaging_product: 'whatsapp', status: 'read', message_id: id });
      } catch (_) {}
    };

    // ── /send — text reply from the app ──
    if (url.pathname === '/send') {
      let b = null;
      try { b = await request.json(); } catch (_) { return json({ error: 'bad json' }, 400); }
      // trim both sides — a stray space/newline picked up while
      // pasting the secret must never break sending
      if (!env || !sendSecret(env) || !b || String(b.secret || '').trim() !== sendSecret(env)) {
        return json({ error: 'forbidden' }, 403);
      }
      if (!env.WHATSAPP_TOKEN) return json({ error: 'WHATSAPP_TOKEN not configured' }, 500);
      const to = String(b.to || '').replace(/\D/g, '');
      const text = String(b.text || '').slice(0, 4000);
      if (!to || !text) return json({ error: 'missing to/text' }, 400);
      await markRead(b.readId);   // customer's message → read (no more unanswered look)
      const r = await graphMsg({ messaging_product: 'whatsapp', to, type: 'text', text: { body: text } });
      const j = await r.json().catch(() => ({}));
      if (r.ok) {
        // API sends don't echo back on the webhook — record ourselves
        // so the app's waiting row clears instantly.
        await fetch(FIREBASE + '/msgs.json', {
          method: 'POST',
          body: JSON.stringify({ dir: 'out', phone: to, text, ts: Date.now(), via: 'app' })
        });
        await fetch(FIREBASE + '/waiting/' + to + '.json', { method: 'DELETE' });
        return json({ ok: true });
      }
      return json({ error: (j.error && j.error.message) || ('graph ' + r.status), code: j.error && j.error.code });
    }

    // ── /twilio — Twilio WhatsApp sandbox webhook. A REAL WhatsApp
    // chat that answers him TODAY, no Meta onboarding: the reply rides
    // back on the TwiML response, so no Twilio credentials are needed.
    if (url.pathname === '/twilio') {
      const twiml = (s) => new Response(s, { headers: { 'Content-Type': 'text/xml' } });
      const xml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      let form = null;
      try { form = await request.formData(); } catch (_) { return twiml('<Response/>'); }
      const from = String(form.get('From') || '').replace(/\D/g, '');
      const text = String(form.get('Body') || '').trim();
      // Only Elior's number gets the assistant — anyone else who joins
      // the sandbox is ignored silently.
      if (!text || !from || from !== ownerDigits(env)) return twiml('<Response/>');
      const replies = [];
      await handleOwnerCmd(text, env, from, true, async (m) => { replies.push(String(m)); });
      return twiml(replies.length
        ? '<Response><Message>' + xml(replies.join('\n\n')) + '</Message></Response>'
        : '<Response/>');
    }

    // ── /tg — Telegram assistant webhook. A bot that ACTUALLY answers
    // him in a real chat TODAY, while Meta's onboarding block sits on
    // the WhatsApp assistant number. Free-form commands, freeMode=true.
    if (url.pathname === '/tg') {
      if (!env.TELEGRAM_TOKEN) return json({ ok: true });
      // Telegram echoes back the secret registered via setWebhook
      if (request.headers.get('x-telegram-bot-api-secret-token') !== sendSecret(env)) {
        return json({ error: 'forbidden' }, 403);
      }
      let b = null;
      try { b = await request.json(); } catch (_) { return json({ ok: true }); }
      const msg = b && (b.message || b.edited_message);
      const text = msg && msg.text;
      const chat = msg && msg.chat && msg.chat.id;
      if (!text || !chat) return json({ ok: true });
      // First person to write claims the bot as owner; anyone else is ignored.
      let ownerChat = await fetch(FIREBASE + '/tgchat.json').then(r => r.json()).catch(() => null);
      if (!ownerChat) {
        ownerChat = chat;
        await fetch(FIREBASE + '/tgchat.json', { method: 'PUT', body: JSON.stringify(chat) });
      }
      if (String(chat) !== String(ownerChat)) return json({ ok: true });
      const tgReply = async (m) => {
        try {
          await fetch('https://api.telegram.org/bot' + env.TELEGRAM_TOKEN + '/sendMessage', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ chat_id: chat, text: String(m).slice(0, 4000) })
          });
        } catch (_) {}
      };
      await handleOwnerCmd(text, env, ownerDigits(env), true, tgReply);
      return json({ ok: true });
    }

    // ── /tg-setup — register this worker as the bot's webhook (run
    // once after TELEGRAM_TOKEN lands in secrets, via the probe CI) ──
    if (url.pathname === '/tg-setup') {
      let b = null;
      try { b = await request.json(); } catch (_) { return json({ error: 'bad json' }, 400); }
      if (!env || !sendSecret(env) || !b || String(b.secret || '').trim() !== sendSecret(env)) {
        return json({ error: 'forbidden' }, 403);
      }
      if (!env.TELEGRAM_TOKEN) return json({ error: 'TELEGRAM_TOKEN not set' }, 500);
      const r = await fetch('https://api.telegram.org/bot' + env.TELEGRAM_TOKEN + '/setWebhook', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          url: 'https://ravid-whatsapp.djeliorravid.workers.dev/tg',
          secret_token: sendSecret(env),
          allowed_updates: ['message']
        })
      });
      return json(await r.json().catch(() => ({})));
    }

    // ── /testcmd — run one assistant command end-to-end (real brain,
    // real data) and return the reply, for CI-driven verification ──
    if (url.pathname === '/testcmd') {
      let b = null;
      try { b = await request.json(); } catch (_) { return json({ error: 'bad json' }, 400); }
      if (!env || !sendSecret(env) || !b || String(b.secret || '').trim() !== sendSecret(env)) {
        return json({ error: 'forbidden' }, 403);
      }
      const replies = [];
      await handleOwnerCmd(String(b.text || ''), env, ownerDigits(env), true, async (m) => { replies.push(String(m)); });
      return json({ ok: true, replies });
    }

    // ── /testpush — fire one APNs alert and return Apple's verdict,
    // so push problems are diagnosed with a curl instead of guesswork ──
    if (url.pathname === '/testpush') {
      let b = null;
      try { b = await request.json(); } catch (_) { return json({ error: 'bad json' }, 400); }
      if (!env || !sendSecret(env) || !b || String(b.secret || '').trim() !== sendSecret(env)) {
        return json({ error: 'forbidden' }, 403);
      }
      const r = await sendApns(env, '🤖 בדיקת התראות', String(b.text || 'אם אתה רואה את זה — ההתראות מהעוזר עובדות! ✅'));
      if (!r) return json({ ok: false, why: 'no APNS secrets or no device token in /whatsapp/push.json' });
      return json({ ok: r.ok, status: r.status, apple: await r.text() });
    }

    // ── /send-voice — recorded audio reply from the app ──
    if (url.pathname === '/send-voice') {
      let b = null;
      try { b = await request.json(); } catch (_) { return json({ error: 'bad json' }, 400); }
      if (!env || !sendSecret(env) || !b || String(b.secret || '').trim() !== sendSecret(env)) {
        return json({ error: 'forbidden' }, 403);
      }
      if (!env.WHATSAPP_TOKEN) return json({ error: 'WHATSAPP_TOKEN not configured' }, 500);
      const to = String(b.to || '').replace(/\D/g, '');
      const mime = String(b.mime || 'audio/mp4');
      if (!to || !b.audio) return json({ error: 'missing to/audio' }, 400);
      let bytes;
      try {
        const bin = atob(b.audio);
        bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      } catch (_) { return json({ error: 'bad audio encoding' }, 400); }
      // 1) upload the media to Meta
      const fd = new FormData();
      fd.append('messaging_product', 'whatsapp');
      fd.append('type', mime);
      fd.append('file', new Blob([bytes], { type: mime }), 'voice.m4a');
      const up = await fetch('https://graph.facebook.com/v21.0/' + PHONE_ID + '/media', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + env.WHATSAPP_TOKEN },
        body: fd
      });
      const uj = await up.json().catch(() => ({}));
      if (!up.ok || !uj.id) {
        return json({ error: (uj.error && uj.error.message) || ('upload ' + up.status) });
      }
      await markRead(b.readId);
      // 2) send as a REAL voice note (PTT with waveform) — voice:true
      //    is what makes WhatsApp render it like a normal recording,
      //    not an audio-file attachment. Only valid for OGG/Opus.
      const isOpus = mime.indexOf('ogg') !== -1;
      const audioObj = isOpus ? { id: uj.id, voice: true } : { id: uj.id };
      const r = await graphMsg({ messaging_product: 'whatsapp', to, type: 'audio', audio: audioObj });
      const j = await r.json().catch(() => ({}));
      if (r.ok) {
        await fetch(FIREBASE + '/msgs.json', {
          method: 'POST',
          body: JSON.stringify({ dir: 'out', phone: to, text: '[הקלטה קולית]', type: 'audio', ts: Date.now(), via: 'app' })
        });
        await fetch(FIREBASE + '/waiting/' + to + '.json', { method: 'DELETE' });
        return json({ ok: true });
      }
      return json({ error: (j.error && j.error.message) || ('graph ' + r.status), code: j.error && j.error.code });
    }

    let body = null;
    try { body = await request.json(); } catch (_) { return new Response('ok', { status: 200 }); }

    // Ack Meta IMMEDIATELY and process in the background — slow work
    // (like transcription) must never trigger webhook retries.
    if (ctx && ctx.waitUntil) {
      ctx.waitUntil(processWebhook(body, env));
      return new Response('ok', { status: 200 });
    }
    await processWebhook(body, env);
    return new Response('ok', { status: 200 });
  },

  // Cron Trigger (* * * * * — every minute): flush due scheduled
  // messages every run; the hourly "X מחכים" push fires only at the
  // top of the hour. A coarser 0 * * * * cron still works — both
  // jobs then run hourly.
  async scheduled(event, env, ctx) {
    const jobs = [flushOutbox(env)];
    if (new Date().getMinutes() === 0) jobs.push(hourlyPush(env));
    ctx.waitUntil(Promise.allSettled(jobs));
  }
};

// ── Scheduled messages: the app queues {to, text, at, sig} under
//    /whatsapp/outbox; each cron run sends whatever came due. The sig
//    (SHA-256 of SEND_SECRET|to|text|at) proves the item was queued by
//    the app — the DB alone can't mint a valid one. ──
async function sha256hex(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
}
async function flushOutbox(env) {
  try {
    const box = await fetch(FIREBASE + '/outbox.json').then(r => r.json()).catch(() => null);
    if (!box) return;
    const now = Date.now();
    for (const id of Object.keys(box)) {
      const it = box[id] || {};
      // housekeeping: anything final and older than 30 days goes away
      if (it.status !== 'pending' && now - (Number(it.at) || 0) > 30 * 24 * 3600 * 1000) {
        await fetch(FIREBASE + '/outbox/' + id + '.json', { method: 'DELETE' });
        continue;
      }
      if (it.status !== 'pending' || Number(it.at) > now) continue;
      const mark = (patch) => fetch(FIREBASE + '/outbox/' + id + '.json', {
        method: 'PATCH', body: JSON.stringify(patch)
      });
      const to = String(it.to || '').replace(/\D/g, '');
      const text = String(it.text || '').slice(0, 4000);
      if (!to || !text || !sendSecret(env) || !env.WHATSAPP_TOKEN) {
        // Name the exact missing piece — 'הגדרה חסרה' sent Elior
        // guessing. (Secrets must be added as type SECRET in the
        // dashboard; plain-text vars get wiped on every deploy.)
        const missing = !to ? 'מספר' : !text ? 'טקסט'
          : !sendSecret(env) ? 'SEND_SECRET חסר בענן'
          : 'WHATSAPP_TOKEN חסר בענן (Settings → Variables, סוג Secret)';
        await mark({ status: 'failed', err: missing, doneTs: now });
        continue;
      }
      const expect = await sha256hex(sendSecret(env) + '|' + to + '|' + text + '|' + it.at);
      if (it.sig !== expect) {
        await mark({ status: 'failed', err: 'חתימה לא תקינה', doneTs: now });
        continue;
      }
      const r = await fetch('https://graph.facebook.com/v21.0/' + PHONE_ID + '/messages', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + env.WHATSAPP_TOKEN, 'Content-Type': 'application/json' },
        body: JSON.stringify({ messaging_product: 'whatsapp', to, type: 'text', text: { body: text } })
      });
      const j = await r.json().catch(() => ({}));
      if (r.ok) {
        await mark({ status: 'sent', doneTs: now });
        await fetch(FIREBASE + '/msgs.json', {
          method: 'POST',
          body: JSON.stringify({ dir: 'out', phone: to, text, ts: now, via: 'sched' })
        });
        await fetch(FIREBASE + '/waiting/' + to + '.json', { method: 'DELETE' });
      } else {
        const err = (j.error && j.error.message) || ('graph ' + r.status);
        await mark({ status: 'failed', err, doneTs: now });
        // The likeliest cause is Meta's 24h customer-service window —
        // tell the phone right away so it isn't a silent black hole.
        await sendApns(env, '⏰ הודעה מתוזמנת לא נשלחה', 'ל-' + to + ': ' + err).catch(() => {});
      }
    }
  } catch (_) {}
}

// ── Hourly "X מחכים לתשובה" push over Apple Push (APNs) ──
async function hourlyPush(env) {
  const log = { ts: Date.now(), count: 0, sent: false, err: '' };
  try {
    // Quiet hours 22:00–08:00 Israel time — same rule as in the app.
    const h = Number(new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Jerusalem', hour: 'numeric', hour12: false
    }).format(new Date())) % 24;
    if (h < 8 || h >= 22) { log.err = 'quiet hours'; return; }

    const [waiting, cls, marks, push] = await Promise.all([
      fetch(FIREBASE + '/waiting.json').then(r => r.json()).catch(() => null),
      fetch(FIREBASE + '/cls.json').then(r => r.json()).catch(() => null),
      fetch(FIREBASE + '/clients.json').then(r => r.json()).catch(() => null),
      fetch(FIREBASE + '/push.json').then(r => r.json()).catch(() => null)
    ]);
    const MONTH = 30 * 24 * 3600 * 1000;
    const phones = Object.keys(waiting || {}).filter(p => {
      const ts = Number(waiting[p]) || 0;
      if (!ts || Date.now() - ts > MONTH) return false;        // stale
      if (marks && marks[p] === false) return false;           // "לא רלוונטי"
      if (cls && cls[p] === 'skip') return false;              // friends/family
      return true;                                             // client or lead
    });
    log.count = phones.length;
    if (!phones.length) return;
    if (!push || !push.token) { log.err = 'no device token yet'; return; }
    if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) { log.err = 'APNS secrets missing'; return; }

    const body = phones.length === 1
      ? 'לקוח אחד מחכה לתשובה בוואטסאפ'
      : phones.length + ' אנשים מחכים לתשובה בוואטסאפ';
    const r = await sendApns(env, '💬 מחכים לתשובה שלך', body);
    if (r && r.ok) log.sent = true;
    else log.err = 'apns ' + (r ? r.status + ' ' + (await r.text().catch(() => '')).slice(0, 200) : 'no token/secrets');
  } catch (e) {
    log.err = (e && e.message) || 'push error';
  } finally {
    // Always leave a trace — one record, overwritten each run, so a
    // silent failure is impossible to miss when debugging.
    try { await fetch(FIREBASE + '/pushlog.json', { method: 'PUT', body: JSON.stringify(log) }); } catch (_) {}
  }
}

// One APNs alert to Elior's registered iPhone. Returns the fetch
// Response, or null when the token / APNS secrets aren't set up yet.
async function sendApns(env, title, body) {
  if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return null;
  const push = await fetch(FIREBASE + '/push.json').then(r => r.json()).catch(() => null);
  if (!push || !push.token) return null;
  const jwt = await apnsJwt(env);
  // Try production first, then sandbox. His .p8 key came back
  // BadEnvironmentKeyInToken on production (key was created
  // sandbox-only), and dev builds register sandbox tokens anyway —
  // trying both means pushes work regardless of key scope or build
  // type, and the diag trace shows exactly which side Apple rejects.
  let last = { ok: false, status: 0, txt: '' };
  for (const host of ['api.push.apple.com', 'api.sandbox.push.apple.com']) {
    const r = await fetch('https://' + host + '/3/device/' + push.token, {
      method: 'POST',
      headers: {
        'authorization': 'bearer ' + jwt,
        'apns-topic': 'com.ravidstudio.app',
        'apns-push-type': 'alert',
        'apns-priority': '10'
      },
      body: JSON.stringify({
        aps: { alert: { title, body }, sound: 'default', 'thread-id': 'wa-waiting' }
      })
    });
    const txt = await r.text().catch(() => '');
    await diag(env, 'apns', { host, ok: r.ok, status: r.status, apple: txt.slice(0, 200) });
    last = { ok: r.ok, status: r.status, txt };
    if (r.ok) break;
  }
  return { ok: last.ok, status: last.status, text: () => Promise.resolve(last.txt) };
}

// ES256 JWT for APNs, signed with the .p8 auth key (WebCrypto).
async function apnsJwt(env) {
  const b64u = (buf) => btoa(String.fromCharCode.apply(null, new Uint8Array(buf)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const enc = (obj) => b64u(new TextEncoder().encode(JSON.stringify(obj)));
  const pem = String(env.APNS_KEY).replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der.buffer, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']
  );
  const head = enc({ alg: 'ES256', kid: env.APNS_KEY_ID });
  const claims = enc({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) });
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(head + '.' + claims)
  );
  return head + '.' + claims + '.' + b64u(sig);
}

// Transcribe an incoming WhatsApp voice note with Gemini (needs the
// GEMINI_KEY secret; silently skipped without it).
async function transcribe(mediaId, env) {
  if (!env || !env.GEMINI_KEY || !env.WHATSAPP_TOKEN) return '';
  try {
    const metaRes = await fetch('https://graph.facebook.com/v21.0/' + mediaId, {
      headers: { 'Authorization': 'Bearer ' + env.WHATSAPP_TOKEN }
    });
    const meta = await metaRes.json().catch(() => ({}));
    if (!meta || !meta.url) return '';
    const audRes = await fetch(meta.url, { headers: { 'Authorization': 'Bearer ' + env.WHATSAPP_TOKEN } });
    if (!audRes.ok) return '';
    const buf = new Uint8Array(await audRes.arrayBuffer());
    if (!buf.length || buf.length > 6 * 1024 * 1024) return '';
    let bin = '';
    const CH = 0x8000;
    for (let i = 0; i < buf.length; i += CH) bin += String.fromCharCode.apply(null, buf.subarray(i, i + CH));
    const b64 = btoa(bin);
    const g = await fetch('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=' + env.GEMINI_KEY, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [
          { inline_data: { mime_type: meta.mime_type || 'audio/ogg', data: b64 } },
          { text: 'תמלל את ההקלטה במדויק, בשפה שבה דיברו. החזר את התמלול בלבד — בלי הקדמות ובלי הערות.' }
        ] }],
        generationConfig: { temperature: 0, maxOutputTokens: 2048 }
      })
    });
    const gj = await g.json().catch(() => ({}));
    const parts = gj && gj.candidates && gj.candidates[0] && gj.candidates[0].content && gj.candidates[0].content.parts;
    const tr = parts ? parts.map(p => p.text || '').join('').trim() : '';
    return tr.slice(0, 1500);
  } catch (_) { return ''; }
}

// ══════════ OWNER REMOTE CONTROL — Elior texts his own business
// number from his personal phone (env.OWNER_PHONE secret) and the
// business answers: expenses/income queued into the app, live money
// and schedule queries answered instantly. ══════════
const ROOT_DB = FIREBASE.replace(/\/whatsapp$/, '');
// Accept the owner number in ANY format he pasted it — 052…, 972…,
// +972…, with dashes — and normalize to WhatsApp's international form.
function numDigits(v) {
  let d = String(v || '').replace(/\D/g, '');
  if (!d) return '';
  if (d.startsWith('972')) return d;
  if (d.startsWith('0')) return '972' + d.slice(1);
  return d;
}
function ownerDigits(env) { return numDigits(env && env.OWNER_PHONE); }
// The worker's clock is UTC; every "today/tomorrow/what day is it"
// must be computed in HIS timezone — a 23:30 UTC answer that says
// Monday when it's already Tuesday in Tel Aviv reads as "הוא טועה".
function ilNow() { return new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' })); }
const IL_DAYS = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
// A SECOND number Elior owns (cheap eSIM on the same iPhone, regular
// WhatsApp next to the Business app). Meta blocks number→itself, but
// business→personal is a normal customer chat — so with this set, the
// business number becomes an assistant that ACTUALLY ANSWERS him,
// no Meta onboarding and no assistant app needed.
function personalDigits(env) { return numDigits(env && env.OWNER_PERSONAL); }
async function handleOwnerCmd(raw, env, replyTo, freeMode, replyOverride) {
  // freeMode: a DEDICATED assistant chat — every message is for the
  // bot. false = the self-chat, which doubles as his notepad.
  // replyOverride: a channel that CAN answer directly (Telegram) —
  // replaces the WhatsApp/APNs/cmdreply fanout entirely.
  const t = String(raw || '').trim();
  const owner = String(replyTo || '').replace(/\D/g, '') || ownerDigits(env);
  // Meta hard-blocks number→itself (#100), so replies go out from the
  // ASSISTANT number (Meta's free test number, its own secrets) when
  // configured — a real WhatsApp chat named "העוזר". Falls back to the
  // business number for the day a second personal number exists.
  const viaAssistant = !!(env.ASSISTANT_PHONE_ID && env.ASSISTANT_TOKEN);
  const fromId = viaAssistant ? env.ASSISTANT_PHONE_ID : PHONE_ID;
  const fromTok = viaAssistant ? env.ASSISTANT_TOKEN : env.WHATSAPP_TOKEN;
  // Answers fan out through EVERY channel we have — whichever is
  // alive delivers:
  //   1. WhatsApp (assistant number once Meta unblocks; self-send is
  //      Meta-blocked so the main number only works to a 2nd phone)
  //   2. APNs push to his iPhone (lights up the moment the Apple
  //      checklist is done — no Meta involved)
  //   3. /whatsapp/cmdreply → the app toasts it on next open (always)
  const reply = replyOverride || (async (msg) => {
    const body = String(msg).slice(0, 3500);
    try {
      const r = await fetch('https://graph.facebook.com/v21.0/' + fromId + '/messages', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + fromTok, 'Content-Type': 'application/json' },
        body: JSON.stringify({ messaging_product: 'whatsapp', to: owner || ownerDigits(env), type: 'text', text: { body } })
      });
      const j = await r.json().catch(() => ({}));
      await diag(env, 'cmd-reply', { via: viaAssistant ? 'assistant' : 'main', ok: r.ok, status: r.status, err: j.error && j.error.message });
    } catch (e) {
      await diag(env, 'cmd-reply', { err: String(e && e.message) });
    }
    try { await sendApns(env, '🤖 העוזר של האולפן', body); } catch (_) {}
    try { await fetch(FIREBASE + '/cmdreply.json', { method: 'POST', body: JSON.stringify({ msg: body, ts: Date.now() }) }); } catch (_) {}
  });
  const getData = (p) => fetch(ROOT_DB + '/studio_data/' + p + '.json').then(r => r.json()).catch(() => null);
  const ils = (n) => (Math.round(Number(n) || 0)).toLocaleString('en-US') + ' ₪';
  try {
    let m;
    // ── ACTION COMMANDS — the assistant changes things in the app ──
    // טופל מוקי / סגור מוקי
    if ((m = t.match(/^(?:טופל|סגור)\s+(.+)$/))) {
      await fetch(FIREBASE + '/cmdqueue.json', { method: 'POST', body: JSON.stringify({ type: 'done', name: m[1].trim(), ts: Date.now() }) });
      await reply('✓ מסמן טופל את ' + m[1].trim());
      return;
    }
    // נודניק מוקי / נודניק מוקי הערב / נודניק מוקי מחר / נודניק מוקי שעה
    if ((m = t.match(/^נודניק\s+(.+?)(?:\s+(שעה|3 שעות|הערב|מחר))?$/))) {
      const when = m[2] || '3 שעות';
      await fetch(FIREBASE + '/cmdqueue.json', { method: 'POST', body: JSON.stringify({ type: 'snooze', name: m[1].trim(), when, ts: Date.now() }) });
      await reply('😴 ' + m[1].trim() + ' בנודניק (' + when + ') — יחזור עם התראה.');
      return;
    }
    // קבע מחר 16:00 פגישה עם מוקי / קבע 14.7 ב-10 מיקס לגל /
    // תוסיף ליומן היום בשעה 18:00 דרי רביד — deterministic, zero AI.
    // תוסיף/הוסף fire only with a calendar word or a time signal, so
    // notepad lines like "תוסיף חלב לרשימה" never become events.
    const evm = t.match(/^(?:קבע|תקבע|לקבוע|תוסיף|הוסף|להוסיף)(?:\s+לי)?(?:\s+(?:ליומן|ביומן|ללוז|בלוז))?(?:\s+לי)?\s+(.+)$/);
    if (evm && (/^(?:קבע|תקבע|לקבוע)/.test(t) || /ליומן|ביומן|ללוז|בלוז/.test(t) || /\d{1,2}:\d{2}|בשעה|לשעה/.test(t))) {
      const rest = evm[1];
      const now = ilNow();
      let d = new Date(now);
      if (/מחרתיים/.test(rest)) d.setDate(d.getDate() + 2);
      else if (/מחר/.test(rest)) d.setDate(d.getDate() + 1);
      const dm = rest.match(/(\d{1,2})[./](\d{1,2})/);
      if (dm) d = new Date(now.getFullYear(), +dm[2] - 1, +dm[1]);
      const tm = rest.match(/(\d{1,2}):(\d{2})/) || rest.match(/(?:בשעה|לשעה|ב-?)\s*(\d{1,2})(?![:.\d])/);
      // "6 וחצי" → :30, "ורבע" → :15; "8 בערב" → 20:00, "11 בלילה" → 23:00
      let hhNum = tm ? +tm[1] : 12;
      if (/בערב|אחר\s?הצהריים|אחה["״']?צ/.test(rest) && hhNum < 12) hhNum += 12;
      else if (/בלילה/.test(rest) && hhNum >= 7 && hhNum < 12) hhNum += 12;
      const hh = String(hhNum).padStart(2, '0');
      const mm2 = (tm && tm[2]) ? tm[2] : (/וחצי/.test(rest) ? '30' : (/ורבע/.test(rest) ? '15' : '00'));
      const title = rest
        .replace(/מחרתיים|מחר|היום|הערב/g, '')
        .replace(/ליומן|ביומן|ללוז|בלוז/g, '')
        .replace(/בבוקר|בערב|בצהריים|אחר\s?הצהריים|אחה["״']?צ|בלילה/g, '')
        .replace(/וחצי|ורבע/g, '')
        .replace(/(\d{1,2})[./](\d{1,2})/, '')
        .replace(/(\d{1,2}):(\d{2})/, '')
        .replace(/(?:בשעה|לשעה|ב-?)\s*\d{1,2}(?![:.\d])/, '')
        .replace(/בשעה|לשעה/g, '')
        // "ב22:00" leaves an orphan "ב" after the HH:MM strip — drop
        // a standalone ב token (never a word that starts with ב)
        .replace(/(^|\s)ב-?(?=\s|$)/g, ' ')
        .replace(/^\s*לי(?![א-ת])\s*/, '')
        .replace(/\s+/g, ' ').trim()
        // he often wraps the title in quotes — the quotes aren't the name
        .replace(/^["'״׳]+|["'״׳]+$/g, '').trim() || 'פגישה';
      const dateKey = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
      await addEventDirect(env, dateKey, hh + ':' + mm2, title);
      await reply('סגור אחי 📅 קבעתי: ' + title + ' — ' + String(d.getDate()) + '.' + (d.getMonth() + 1) + ' בשעה ' + hh + ':' + mm2 + '. כבר יושב לך בלוז.');
      return;
    }
    // משימה לסדר את האולפן / תזכורת להוציא חשבונית
    if ((m = t.match(/^(?:משימה|תזכורת)\s+(.+)$/))) {
      await fetch(FIREBASE + '/cmdqueue.json', { method: 'POST', body: JSON.stringify({ type: 'task', text: m[1].trim(), ts: Date.now() }) });
      await reply('✓ נוספה משימה: ' + m[1].trim());
      return;
    }
    // הוצאה 200 דלק
    if ((m = t.match(/^הוצאה\s+(\d+(?:\.\d+)?)\s*(.*)$/))) {
      await fetch(FIREBASE + '/cmdqueue.json', { method: 'POST', body: JSON.stringify({ type: 'expense', amount: +m[1], desc: (m[2] || '').trim(), ts: Date.now() }) });
      await reply('✓ נרשמה הוצאה: ' + ils(m[1]) + (m[2] ? ' — ' + m[2].trim() : ''));
      return;
    }
    // הכנסה 500 מוקי
    if ((m = t.match(/^הכנסה\s+(\d+(?:\.\d+)?)\s*(.*)$/))) {
      await fetch(FIREBASE + '/cmdqueue.json', { method: 'POST', body: JSON.stringify({ type: 'income', amount: +m[1], desc: (m[2] || '').trim(), ts: Date.now() }) });
      await reply('✓ נרשמה הכנסה פתוחה: ' + ils(m[1]) + (m[2] ? ' — ' + m[2].trim() : ''));
      return;
    }
    // כמה נכנס / כמה כסף נכנס לי החודש / מצב / מי לא שילם —
    // deterministic money answers, straight from the data, zero AI.
    // (NOTE: never use \b next to Hebrew — JS word boundaries only
    // know ASCII, so \b after א-ת never matches)
    if (/כמה\s+(?:כסף\s+)?(?:נכנס|עשיתי|הרווחתי)/.test(t)
        || /כמה\s+(?:אני\s+)?(?:כסף\s+)?(?:צריך|אמור|הולך)\s+(?:עוד\s+)?(?:לה?י?כנס|להכניס)/.test(t)
        || /כמה\s+(?:עוד\s+)?(?:יכנס|ייכנס|צריך\s+להכנס)/.test(t)
        || /^מצב(?![א-ת])/.test(t)
        || /מי\s+(?:עוד\s+)?לא\s+שילם/.test(t)) {
      const inc = (await getData('income')) || [];
      const now = ilNow();
      const mk = now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0');
      const arr = Array.isArray(inc) ? inc : Object.values(inc);
      const paid = arr.filter(i => i && (i.status || 'pending') === 'paid' && String(i.date || '').slice(0, 7) === mk).reduce((s, i) => s + (Number(i.amount) || 0), 0);
      // Open-for-collection = THIS month only. Plan installments dated
      // other months aren't money he's chasing right now.
      const openArr = arr.filter(i => i && (i.status || 'pending') !== 'paid' && String(i.date || '').slice(0, 7) === mk);
      const open = openArr.reduce((s, i) => s + (Number(i.amount) || 0), 0);
      const openLines = openArr
        .sort((a, b) => (Number(b.amount) || 0) - (Number(a.amount) || 0)).slice(0, 8)
        .map(i => '· ' + ((i.client || i.desc || 'ללא שם')) + ' — ' + ils(i.amount)).join('\n');
      await reply('💰 מצב העסק:\nנכנס החודש: ' + ils(paid)
        + '\nפתוח לגבייה החודש: ' + ils(open) + (openArr.length ? ' (' + openArr.length + ' תשלומים):\n' + openLines : ''));
      return;
    }
    // לוז / לוז מחר / מה הלוז שלי מחר / מה יש לי היום — deterministic
    // schedule answers straight from the data: always Israel-time,
    // always sorted, never invented. Free-form schedule questions used
    // to fall to the AI and came back messy/wrong.
    if (/^לוז(?![א-ת])/.test(t)
        || (/לוז|ביומן|יומן/.test(t) && /^(?:מה|תן|שלח|הצג|תראה|איזה|מתי)/.test(t))
        || /מה\s+יש\s+לי\s+(?:היום|מחר|מחרתיים|השבוע)/.test(t)
        || /^(?:של\s+)?(?:כל\s+)?השבוע\s*\??$/.test(t)) {
      const sched = (await getData('schedule')) || [];
      const arr = Array.isArray(sched) ? sched : Object.values(sched);
      // junk guard: events with neither time nor title render as "— "
      const real = arr.filter(s => s && s.date && ((s.title && String(s.title).trim()) || s.time));
      const dkey2 = (x) => x.getFullYear() + '-' + String(x.getMonth() + 1).padStart(2, '0') + '-' + String(x.getDate()).padStart(2, '0');
      const lines = (items) => items.sort((a, b) => String(a.time).localeCompare(String(b.time)))
        .map(s => '· ' + (s.time || '--:--') + ' — ' + (String(s.title || '').trim() || 'ללא שם')).join('\n');
      const d = ilNow();
      // "מה הלוז השבוע" / "של כל השבוע" → 7 days grouped by day
      if (/שבוע/.test(t)) {
        const days = [];
        for (let i = 0; i < 7; i++) {
          const dd = new Date(d); dd.setDate(dd.getDate() + i);
          const items = real.filter(s => s.date === dkey2(dd));
          if (items.length) days.push('יום ' + IL_DAYS[dd.getDay()] + ' ' + dd.getDate() + '.' + (dd.getMonth() + 1) + ':\n' + lines(items));
        }
        await reply(days.length
          ? '📅 הלוז של השבוע:\n\n' + days.join('\n\n')
          : '📅 השבוע פנוי לגמרי 🎉');
        return;
      }
      let label = 'היום';
      if (/מחרתיים/.test(t)) { d.setDate(d.getDate() + 2); label = 'מחרתיים'; }
      else if (/מחר/.test(t)) { d.setDate(d.getDate() + 1); label = 'מחר'; }
      const items = real.filter(s => s.date === dkey2(d));
      const head = '📅 הלוז של ' + label + ' (יום ' + IL_DAYS[d.getDay()] + ' ' + d.getDate() + '.' + (d.getMonth() + 1) + ')';
      await reply(items.length ? head + ':\n' + lines(items) : head + ': פנוי — אין אירועים בלוז 🎉');
      return;
    }
    // מי מחכה
    if (/מי מחכה|ממתינים/.test(t)) {
      const [waiting, cls, marks, names] = await Promise.all([
        fetch(FIREBASE + '/waiting.json').then(r => r.json()).catch(() => null),
        fetch(FIREBASE + '/cls.json').then(r => r.json()).catch(() => null),
        fetch(FIREBASE + '/clients.json').then(r => r.json()).catch(() => null),
        fetch(FIREBASE + '/names.json').then(r => r.json()).catch(() => null)
      ]);
      const phones = Object.keys(waiting || {}).filter(p => {
        if (marks && marks[p] === false) return false;
        if (cls && cls[p] === 'skip') return false;
        return true;
      });
      await reply(phones.length
        ? '💬 ' + phones.length + ' מחכים לתשובה:\n' + phones.slice(0, 10).map(p => '· ' + ((names && names[p]) || p)).join('\n')
        : '🎉 אף אחד לא מחכה לתשובה.');
      return;
    }
    // No exact pattern matched → the AI brain reads his intent in
    // free Hebrew. The self-chat doubles as his personal notepad, so
    // there the AI only engages when clearly addressed (a question
    // mark, or starting with עוזר/a question word); on the dedicated
    // assistant number EVERYTHING goes to the AI.
    // Anything with a time/date signal, a question mark, or a request
    // verb goes to the AI. The AI itself is told to stay SILENT on
    // pure personal notes (action:"note"), so over-triggering is safe.
    const timeSignal = /(\d{1,2}:\d{2})|בשעה|לשעה|שעה\s*\d|מחר|מחרתיים|הערב|היום/.test(t);
    const addressed = freeMode === true
      || /\?\s*$/.test(t)
      || timeSignal
      || /^(עוזר|מה|כמה|מתי|מי|איך|תרשום|תוסיף|תקבע|תזכיר|רשום|קבע|הוסף|שים|תשים|להוסיף|לקבוע|לרשום|תעשה|צור|תיצור|תבטל)(?![א-ת])/.test(t);
    if (addressed && (env.AI || env.GEMINI_KEY)) {
      const done = await aiCommand(t, env, reply);
      if (done) return;
      // AI failed on a message that was CLEARLY for the assistant —
      // say so out loud instead of leaving him talking to a wall.
      const strong = freeMode === true || /\?\s*$/.test(t)
        || /^(עוזר|תרשום|תוסיף|תקבע|תזכיר|רשום|קבע|הוסף|שים|תשים|להוסיף|לקבוע|לרשום|תעשה|צור|תיצור|תבטל)(?![א-ת])/.test(t);
      if (strong) { await reply('🤖 משהו נתקע לי רגע בעיבוד — שלח שוב או נסח קצת אחרת.'); return; }
    }
    if (!addressed) { await diag(env, 'skipped', { t: t.slice(0, 40) }); return; }
    if (/^(עזרה|עוזר|פקודות|מה קורה|מה המצב|היי)(?![א-ת])/.test(t)) {
      await reply('היי אליאור 👋 אני העוזר של האולפן. דבר אליי חופשי ("תרשום 200 על דלק", "מה המצב החודש?") או בקיצורים:\n'
        + '💰 הוצאה 200 דלק · הכנסה 500 מוקי · כמה נכנס\n'
        + '📅 לוז / לוז מחר · קבע מחר 16:00 פגישה עם מוקי\n'
        + '💬 מי מחכה · טופל מוקי · נודניק מוקי הערב\n'
        + '📝 משימה להוציא חשבונית לגל');
    }
  } catch (_) {
    try { await reply('⚠️ משהו השתבש בפקודה — נסה שוב.'); } catch (__) {}
  }
}

// ══════════ THE AI BRAIN — free-Hebrew understanding ══════════
// When no exact pattern matches, Gemini reads the message WITH the
// live business snapshot and returns strict JSON: an action to
// execute and/or a Hebrew reply. Costs ~nothing at his volume.
async function aiCommand(t, env, reply) {
  try {
    const now = ilNow();
    const dow = IL_DAYS[now.getDay()];
    const dkey = d => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
    // live snapshot
    // The assistant sees EVERY dataset the app holds — any question
    // the app can answer, he can answer.
    const gd = (k) => fetch(ROOT_DB + '/studio_data/' + k + '.json').then(r => r.json()).catch(() => null);
    const [incRaw, schRaw, expRaw, taskRaw, cliRaw, planRaw, waiting, names] = await Promise.all([
      gd('income'), gd('schedule'), gd('expenses'), gd('daily_tasks'), gd('clients'), gd('plans'),
      fetch(FIREBASE + '/waiting.json').then(r => r.json()).catch(() => null),
      fetch(FIREBASE + '/names.json').then(r => r.json()).catch(() => null)
    ]);
    const asArr = (v) => Array.isArray(v) ? v : Object.values(v || {});
    const inc = asArr(incRaw);
    const sch = asArr(schRaw);
    const exp = asArr(expRaw);
    const tasks = asArr(taskRaw);
    const clients = asArr(cliRaw);
    const plans = asArr(planRaw);
    const mk = dkey(now).slice(0, 7);
    const paid = inc.filter(i => i && (i.status || 'pending') === 'paid' && String(i.date || '').slice(0, 7) === mk).reduce((s, i) => s + (Number(i.amount) || 0), 0);
    // THIS month's open payments only — same rule as the deterministic
    // answer, per Elior: other months' installments don't count.
    const open = inc.filter(i => i && (i.status || 'pending') !== 'paid' && String(i.date || '').slice(0, 7) === mk);
    const openSum = open.reduce((s, i) => s + (Number(i.amount) || 0), 0);
    const tomorrow = new Date(now.getTime() + 864e5);
    const schReal = sch.filter(s => s && s.date && ((s.title && String(s.title).trim()) || s.time));
    const dayList = (key) => schReal.filter(s => s.date === key)
      .sort((a, b) => String(a.time).localeCompare(String(b.time)))
      .map(s => '· ' + s.time + ' — ' + s.title).join('\n') || 'ריק';
    const next7 = sch.filter(s => s && s.date > dkey(tomorrow) && s.date <= dkey(new Date(now.getTime() + 7 * 864e5)))
      .sort((a, b) => (a.date + a.time).localeCompare(b.date + b.time)).slice(0, 15)
      .map(s => s.date + ' ' + s.time + ' ' + s.title).join(' | ');
    const waitNames = Object.keys(waiting || {}).map(p => (names && names[p]) || p).slice(0, 8).join(', ');
    const hhmm = String(now.getHours()).padStart(2, '0') + ':' + String(now.getMinutes()).padStart(2, '0');
    // expenses this month
    const expMonth = exp.filter(e => e && String(e.date || '').slice(0, 7) === mk);
    const expSum = expMonth.reduce((s, e) => s + (Number(e.amount) || 0), 0);
    const expLast = expMonth.slice(-6).map(e => (e.desc || e.cat || '') + ' ' + Math.round(Number(e.amount) || 0) + '₪').join(', ');
    // open tasks
    const openTasks = tasks.filter(x => x && !x.done).slice(-10).map(x => x.text).filter(Boolean);
    // active payment plans: paid-of-total per client
    const planLines = plans.map(p => {
      if (!p) return null;
      const pays = Array.isArray(p.payments) ? p.payments : [];
      if (!pays.length) return null;
      const tot = pays.reduce((s, x) => s + (Number(x.amount) || 0), 0);
      const pd = pays.filter(x => x && x.paid).reduce((s, x) => s + (Number(x.amount) || 0), 0);
      if (pd >= tot) return null;   // finished plan — noise
      return (p.client || p.name || 'ללא שם') + ': שולם ' + Math.round(pd) + '₪ מתוך ' + Math.round(tot) + '₪';
    }).filter(Boolean).slice(0, 8).join(' | ');
    const cliNames = clients.map(c => c && c.name).filter(Boolean).slice(-15).join(', ');
    // humanized dates — the model regurgitates whatever format it's
    // fed, and 2026-07-16 in a WhatsApp reply reads like a robot
    const humanDate = (iso) => {
      const p = String(iso).split('-');
      const dd = new Date(+p[0], +p[1] - 1, +p[2]);
      return 'יום ' + IL_DAYS[dd.getDay()] + ' ' + dd.getDate() + '.' + (dd.getMonth() + 1);
    };
    const next14 = schReal.filter(s => s.date > dkey(tomorrow) && s.date <= dkey(new Date(now.getTime() + 14 * 864e5)))
      .sort((a, b) => (a.date + a.time).localeCompare(b.date + b.time)).slice(0, 20)
      .map(s => humanDate(s.date) + ' ' + s.time + ' ' + s.title).join(' | ');
    const sys = 'אתה העוזר האישי של אליאור רביד, מפיק מוזיקלי (אולפן רביד). אתה מחובר לאפליקציית ניהול האולפן שלו ורואה את כל הנתונים שלה.\n'
      + 'עכשיו בישראל: יום ' + dow + ' ' + dkey(now) + ', השעה ' + hhmm + '. מחר = יום ' + IL_DAYS[tomorrow.getDay()] + ' ' + dkey(tomorrow) + '.\n'
      + 'נתוני אמת מהאפליקציה (אל תמציא שום דבר מעבר להם):\n'
      + '— כספים: נכנס החודש ' + Math.round(paid) + '₪. פתוחים לגבייה החודש: ' + open.length + ' תשלומים בסך ' + Math.round(openSum) + '₪'
      + (open.length ? ' (' + open.slice(0, 6).map(i => (i.client || i.desc || '') + ' ' + Math.round(Number(i.amount) || 0) + '₪').join(', ') + ')' : '') + '\n'
      + '— הוצאות החודש: ' + Math.round(expSum) + '₪ ב-' + expMonth.length + ' הוצאות' + (expLast ? ' (אחרונות: ' + expLast + ')' : '') + '\n'
      + '— תוכניות תשלום פעילות: ' + (planLines || 'אין') + '\n'
      + '— הלוז של היום (' + dkey(now) + '):\n' + dayList(dkey(now)) + '\n'
      + '— הלוז של מחר (' + dkey(tomorrow) + '):\n' + dayList(dkey(tomorrow)) + '\n'
      + '— שבועיים קדימה: ' + (next14 || 'ריק') + '\n'
      + '— משימות פתוחות: ' + (openTasks.length ? openTasks.join(' | ') : 'אין') + '\n'
      + '— לקוחות (' + clients.length + '): ' + (cliNames || '—') + '\n'
      + '— מחכים לתשובה בוואטסאפ: ' + (waitNames || 'אף אחד') + '\n'
      + 'קרא את ההודעה של אליאור והחזר JSON בלבד (בלי טקסט מסביב, בלי ```):\n'
      + '{"action":"expense|income|event|task|done|snooze|answer","amount":מספר,"desc":"","date":"YYYY-MM-DD","time":"HH:MM","title":"","name":"","when":"שעה|הערב|מחר","reply":"תשובה בעברית"}\n'
      + 'השתמש ב-action מתאים רק אם הוא ביקש פעולה; לשאלות מידע החזר action="answer" עם reply מהנתונים בלבד. '
      + 'כללי reply: קצר וחברי, בשורות מסודרות; כל אירוע בשורה נפרדת בפורמט "· HH:MM — שם" ממוין לפי שעה; תאריכים תמיד "יום שלישי 14.7" ולעולם לא YYYY-MM-DD; סכומים במספרים מדויקים מהנתונים; אם אין נתון — כתוב שאין, אל תנחש ואל תמציא. '
      + 'שים לב להבדל: "כמה נכנס" = מה ששולם; "כמה עוד אמור להיכנס / כמה צריך להכניס" = הפתוחים לגבייה. '
      + 'אם זה סתם פתק אישי שלא מבקש ממך כלום (רשימת קניות, מחשבה) — החזר action="note" בלי reply. שדות לא רלוונטיים השמט.';
    // Two independent brains, either one is enough:
    //   1. Workers AI — lives INSIDE Cloudflare, free allocation, no
    //      API key to expire (his Gemini key came back "limit: 0").
    //   2. Gemini — tried when a key exists; each model has its own
    //      free-tier quota pool, so 429 on one may spare the next.
    let raw = '';
    if (env.AI) {
      try {
        const a = await env.AI.run('@cf/meta/llama-3.3-70b-instruct-fp8-fast', {
          messages: [
            { role: 'system', content: sys },
            { role: 'user', content: 'ההודעה: "' + t + '"' }
          ],
          max_tokens: 600,
          temperature: 0.15
        });
        // Workers AI sometimes hands back the model's JSON already
        // parsed (an object) instead of text — stringify it back so
        // the shared JSON-extract below handles both shapes.
        let out0 = a && (a.response !== undefined ? a.response : a.result);
        raw = (out0 && typeof out0 === 'object') ? JSON.stringify(out0) : String(out0 || '').trim();
        await diag(env, 'ai-cf', { len: raw.length, shape: typeof out0 });
      } catch (e) {
        await diag(env, 'ai-fail', { model: 'workers-ai', err: String(e && e.message).slice(0, 200) });
      }
    }
    if (!raw && env.GEMINI_KEY) {
      const models = ['gemini-2.0-flash', 'gemini-2.5-flash-lite', 'gemini-1.5-flash'];
      for (const model of models) {
        const g = await fetch('https://generativelanguage.googleapis.com/v1beta/models/' + model + ':generateContent?key=' + env.GEMINI_KEY, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{ parts: [{ text: sys + '\n\nההודעה: "' + t + '"' }] }],
            generationConfig: { temperature: 0.2, maxOutputTokens: 500 }
          })
        });
        const gj = await g.json().catch(() => ({}));
        if (g.ok) {
          const parts = gj && gj.candidates && gj.candidates[0] && gj.candidates[0].content && gj.candidates[0].content.parts;
          raw = parts ? parts.map(p => p.text || '').join('').trim() : '';
          break;
        }
        // Never fail SILENTLY again — trace it and tell him.
        await diag(env, 'ai-fail', { model, status: g.status, err: gj && gj.error && gj.error.message });
        if (![429, 404, 503].includes(g.status)) break;   // key/req broken — retrying models won't help
      }
    }
    if (!raw) return false;
    raw = raw.replace(/^```json?\s*/i, '').replace(/```\s*$/, '').trim();
    let out = null;
    try { out = JSON.parse(raw); } catch (_) {
      const mjs = raw.match(/\{[\s\S]*\}/);
      if (mjs) { try { out = JSON.parse(mjs[0]); } catch (__) {} }
    }
    if (!out) { await diag(env, 'ai-fail', { parse: raw.slice(0, 200) }); return false; }
    await diag(env, 'ai-ok', { action: out.action, date: out.date, time: out.time });
    if (out.action === 'note') return true;   // his notepad — stay silent
    // execute the action through the same queue the exact commands use
    const post = (obj) => fetch(FIREBASE + '/cmdqueue.json', { method: 'POST', body: JSON.stringify(Object.assign({ ts: Date.now() }, obj)) });
    if (out.action === 'expense' && out.amount) await post({ type: 'expense', amount: +out.amount, desc: out.desc || '' });
    else if (out.action === 'income' && out.amount) await post({ type: 'income', amount: +out.amount, desc: out.desc || out.name || '' });
    else if (out.action === 'event' && out.date) await addEventDirect(env, out.date, out.time || '12:00', out.title || 'פגישה');
    else if (out.action === 'task' && (out.desc || out.title)) await post({ type: 'task', text: out.desc || out.title });
    else if (out.action === 'done' && out.name) await post({ type: 'done', name: out.name });
    else if (out.action === 'snooze' && out.name) await post({ type: 'snooze', name: out.name, when: out.when || '3 שעות' });
    await reply(out.reply || '✓ בוצע');
    return true;
  } catch (_) { return false; }
}

// Add a schedule event DIRECTLY into the app's cloud data — so 'קבע'
// exists the moment the command lands, even with the app closed. The
// cmdqueue entry (same id → app upserts, no duplicate) only handles
// what the cloud can't: mirroring to the iOS/Google calendar.
async function addEventDirect(env, dateKey, time, title) {
  const id = 'ev' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  try {
    const arr = await fetch(ROOT_DB + '/studio_data/schedule.json').then(r => r.json()).catch(() => null);
    const list = Array.isArray(arr) ? arr.slice() : (arr ? Object.values(arr) : []);
    list.push({ id, date: dateKey, time, title, notes: 'נקבע מרחוק דרך וואטסאפ', createdAt: new Date().toISOString() });
    await fetch(ROOT_DB + '/studio_data/schedule.json', { method: 'PUT', body: JSON.stringify(list) });
    await fetch(ROOT_DB + '/studio_meta/schedule.json', { method: 'PUT', body: JSON.stringify(Date.now()) });
  } catch (_) {}
  try {
    await fetch(FIREBASE + '/cmdqueue.json', { method: 'POST', body: JSON.stringify({ type: 'event', id, date: dateKey, time, title, ts: Date.now() }) });
  } catch (_) {}
  return id;
}

// Compact diagnostic trace — answers "what shape does a self-chat
// message actually arrive in?" without dumping full payloads.
async function diag(env, tag, data) {
  try {
    await fetch(FIREBASE + '/diag.json', {
      method: 'POST',
      body: JSON.stringify({ ts: Date.now(), tag, data: JSON.stringify(data).slice(0, 900) })
    });
  } catch (_) {}
}
async function processWebhook(body, env) {
    let stored = 0;
    const names = {};   // phone → name, PATCHed once at the end
    const nowWaiting = {};   // phone → ts — set when a customer writes
    const answered = {};     // phone → true — cleared when Elior replies
    // DIAG: one-line shape summary per webhook
    try {
      for (const e0 of (body && body.entry) || []) for (const ch of e0.changes || []) {
        const v0 = ch.value || {};
        await diag(env, 'shape', {
          field: ch.field,
          meta: v0.metadata && v0.metadata.display_phone_number,
          msgs: (v0.messages || []).map(m => ({ from: m.from, type: m.type, txt: (m.text && m.text.body || '').slice(0, 30) })),
          echoes: (v0.message_echoes || v0.smb_message_echoes || []).map(m => ({ to: m.to || m.recipient_id, from: m.from, type: m.type, txt: (m.text && m.text.body || '').slice(0, 30) })),
          statuses: (v0.statuses || []).length,
          otherKeys: Object.keys(v0).filter(k => !['metadata','contacts','messages','message_echoes','smb_message_echoes','statuses','messaging_product'].includes(k))
        });
      }
    } catch (_) {}
    try {
      for (const entry of (body && body.entry) || []) {
        for (const change of entry.changes || []) {
          const v = change.value || {};
          // ── ASSISTANT NUMBER: its own app posts to this same worker.
          // Anything Elior writes to the assistant chat is a command;
          // anyone else gets a polite brush-off. Never mixes with the
          // business inbox. ──
          const metaId = String((v.metadata && v.metadata.phone_number_id) || '');
          if (env.ASSISTANT_PHONE_ID && metaId === String(env.ASSISTANT_PHONE_ID)) {
            for (const m of v.messages || []) {
              const fromPh = String(m.from || '').replace(/\D/g, '');
              stored++;
              if (fromPh === ownerDigits(env)) {
                await handleOwnerCmd((m.text && m.text.body) || '', env, fromPh, true);
              }
            }
            stored++;   // statuses etc. on the assistant line are noise
            continue;
          }
          // Contact-directory sync (coexistence app-state/history):
          // these carry HIS address-book names — keep them all.
          if (Array.isArray(v.contacts)) {
            for (const c of v.contacts) {
              const ph = String(c.phone_number || c.wa_id || '').replace(/\D/g, '');
              const nm = c.full_name || (c.profile && c.profile.name) || c.first_name || '';
              if (ph && nm) { names[ph] = nm; stored++; }
            }
          }
          // Incoming customer messages
          for (const m of v.messages || []) {
            // Emoji reactions aren't a message that needs answering —
            // recording them would mark the chat as waiting falsely.
            if (m.type === 'reaction') { stored++; continue; }
            const ph = String(m.from || '').replace(/\D/g, '');
            // Edited messages arrive as a NEW webhook that references the
            // original — treat the edited body as the message text.
            let text = (m.text && m.text.body)
              || (m.edited && m.edited.text && m.edited.text.body)
              || (m.text_edited && m.text_edited.body)
              || '';
            if (!text) {
              const t = m.type;
              if (t === 'text')           text = '✏️ ' + ((m.text && m.text.body) || '(עריכה)');
              else if (t === 'sticker')   text = '🧩 סטיקר';
              else if (t === 'image')     text = '📷 תמונה' + (m.image && m.image.caption ? ' — ' + m.image.caption : '');
              else if (t === 'video')     text = '🎬 סרטון' + (m.video && m.video.caption ? ' — ' + m.video.caption : '');
              else if (t === 'audio') {
                // Voice note → automatic transcription (Gemini)
                const tr = (m.audio && m.audio.id) ? await transcribe(m.audio.id, env) : '';
                text = tr ? ('🎤 תמלול: ' + tr) : '🎤 הודעה קולית';
              }
              else if (t === 'document')  text = '📄 קובץ' + (m.document && m.document.filename ? ' — ' + m.document.filename : '');
              else if (t === 'location')  text = '📍 מיקום';
              else if (t === 'contacts')  text = '👤 איש קשר';
              // Button / interactive replies carry their label elsewhere.
              else if (t === 'button')    text = (m.button && m.button.text) || '🔘 כפתור';
              else if (t === 'interactive') text = (m.interactive && ((m.interactive.button_reply && m.interactive.button_reply.title) || (m.interactive.list_reply && m.interactive.list_reply.title))) || '🔘 בחירה';
              else {
                // Truly unknown — label with the type so it's not a
                // mystery, and capture the raw shape once for diagnosis.
                text = '📩 הודעה (' + (t || 'לא ידוע') + ')';
                try {
                  await fetch(FIREBASE + '/debug.json', {
                    method: 'POST',
                    body: JSON.stringify({ raw: JSON.stringify(m).slice(0, 2000), ts: Date.now() })
                  });
                } catch (_) {}
              }
            }
            // Owner remote control: a message from HIS personal number
            // is a command, not a customer conversation.
            // OWNER_PERSONAL (second eSIM) is a DEDICATED assistant chat
            // → freeMode, and the reply goes back to that number — a
            // real WhatsApp answer, since it isn't a self-send.
            const personalPh = personalDigits(env);
            if (personalPh && ph === personalPh) {
              stored++;
              await handleOwnerCmd((m.text && m.text.body) || text, env, ph, true);
              continue;
            }
            const ownerPh = ownerDigits(env);
            if (ownerPh && ph === ownerPh) {
              stored++;
              await handleOwnerCmd((m.text && m.text.body) || text, env);
              continue;
            }
            const rec = {
              dir: 'in',
              phone: ph,
              id: m.id || '',   // wamid — needed to mark-as-read on reply
              name: (v.contacts && v.contacts[0] && v.contacts[0].profile && v.contacts[0].profile.name) || '',
              type: m.type || '',
              text,
              ts: (Number(m.timestamp || 0) * 1000) || Date.now()
            };
            if (rec.name && ph) names[ph] = names[ph] || rec.name;
            await fetch(FIREBASE + '/msgs.json', { method: 'POST', body: JSON.stringify(rec) });
            if (ph) { nowWaiting[ph] = rec.ts; delete answered[ph]; }
            stored++;
          }
          // Echoes of messages sent from the WhatsApp Business app
          // (field name differs across doc versions — accept both)
          for (const m of v.message_echoes || v.smb_message_echoes || []) {
            const toPh = String(m.to || m.recipient_id || '').replace(/\D/g, '');
            // ONE-PHONE remote control: he has no second number, so
            // commands are typed in WhatsApp's message-yourself chat.
            // A self-chat message arrives as an ECHO whose `to` equals
            // his own number (the business display number / OWNER_PHONE).
            const selfNum = String((v.metadata && v.metadata.display_phone_number) || '').replace(/\D/g, '');
            const ownEcho = ownerDigits(env);
            if (toPh && ((ownEcho && toPh === ownEcho) || (selfNum && toPh === selfNum))) {
              stored++;
              await handleOwnerCmd((m.text && m.text.body) || '', env, toPh);
              continue;
            }
            // The assistant chat with his personal eSIM number is not a
            // customer conversation — keep it out of the inbox.
            if (toPh && toPh === personalDigits(env)) { stored++; continue; }
            const rec = {
              dir: 'out',
              phone: toPh,
              type: m.type || '',
              text: (m.text && m.text.body) || '',
              ts: (Number(m.timestamp || 0) * 1000) || Date.now()
            };
            await fetch(FIREBASE + '/msgs.json', { method: 'POST', body: JSON.stringify(rec) });
            if (rec.phone) { answered[rec.phone] = true; delete nowWaiting[rec.phone]; }
            stored++;
          }
          // Delivery/read receipts — mostly noise, but FAILURES are
          // gold: Meta accepts a message with 200 and can reject it
          // asynchronously (e.g. unsupported audio codec). Surface it.
          if (Array.isArray(v.statuses) && v.statuses.length) {
            stored++;
            for (const st of v.statuses) {
              if (st.status === 'failed') {
                const e0 = (st.errors && st.errors[0]) || {};
                await fetch(FIREBASE + '/fails.json', {
                  method: 'POST',
                  body: JSON.stringify({
                    to: String(st.recipient_id || '').replace(/\D/g, ''),
                    err: e0.message || e0.title || 'נכשל',
                    code: e0.code || 0,
                    ts: Date.now()
                  })
                });
              }
            }
          }
        }
      }
      if (Object.keys(names).length) {
        await fetch(FIREBASE + '/names.json', { method: 'PATCH', body: JSON.stringify(names) });
      }
      // The waiting map is what the hourly cron push counts — customer
      // message sets the phone, any reply from Elior (app OR phone,
      // via the echo) clears it.
      if (Object.keys(nowWaiting).length) {
        await fetch(FIREBASE + '/waiting.json', { method: 'PATCH', body: JSON.stringify(nowWaiting) });
      }
      for (const ph of Object.keys(answered)) {
        await fetch(FIREBASE + '/waiting/' + ph + '.json', { method: 'DELETE' });
      }
      // Nothing parsed? Keep a trimmed raw copy so the payload shape
      // can be inspected and the parser adapted.
      if (!stored) {
        const raw = JSON.stringify(body).slice(0, 4000);
        await fetch(FIREBASE + '/debug.json', {
          method: 'POST',
          body: JSON.stringify({ raw, ts: Date.now() })
        });
      }
    } catch (_) {}
}
