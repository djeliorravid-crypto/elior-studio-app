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
      if (!env || !env.SEND_SECRET || !b || b.secret !== env.SEND_SECRET) {
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
        return json({ ok: true });
      }
      return json({ error: (j.error && j.error.message) || ('graph ' + r.status), code: j.error && j.error.code });
    }

    // ── /send-voice — recorded audio reply from the app ──
    if (url.pathname === '/send-voice') {
      let b = null;
      try { b = await request.json(); } catch (_) { return json({ error: 'bad json' }, 400); }
      if (!env || !env.SEND_SECRET || !b || b.secret !== env.SEND_SECRET) {
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
  }
};

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

async function processWebhook(body, env) {
    let stored = 0;
    const names = {};   // phone → name, PATCHed once at the end
    try {
      for (const entry of (body && body.entry) || []) {
        for (const change of entry.changes || []) {
          const v = change.value || {};
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
            let text = (m.text && m.text.body) || '';
            if (!text) {
              const t = m.type;
              if (t === 'sticker')        text = '🧩 סטיקר';
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
              else text = '[הודעה]';
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
            stored++;
          }
          // Echoes of messages sent from the WhatsApp Business app
          // (field name differs across doc versions — accept both)
          for (const m of v.message_echoes || v.smb_message_echoes || []) {
            const rec = {
              dir: 'out',
              phone: String(m.to || m.recipient_id || '').replace(/\D/g, ''),
              type: m.type || '',
              text: (m.text && m.text.body) || '',
              ts: (Number(m.timestamp || 0) * 1000) || Date.now()
            };
            await fetch(FIREBASE + '/msgs.json', { method: 'POST', body: JSON.stringify(rec) });
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
