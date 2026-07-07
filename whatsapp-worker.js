// ═════════════════════════════════════════════════════════════════
//  Ravid Studio — WhatsApp webhook receiver
//  Runs as a Cloudflare Worker. Meta (via DualHook coexistence)
//  delivers message webhooks here; we answer the hub.challenge
//  verification handshake and write a compact record of every
//  incoming customer message + every reply Elior sends from the
//  WhatsApp Business app into the app's Firebase RTDB, where the
//  "ממתינים לתשובה" screen reads it.
//
//  Deploy: Cloudflare dashboard → Workers → Create → paste → Deploy.
//  The public URL of this worker is the "Webhook URL" DualHook asks
//  for, and VERIFY_TOKEN below is the "Verify token".
// ═════════════════════════════════════════════════════════════════

const VERIFY_TOKEN = 'ravid-studio-whatsapp-2026';
const FIREBASE = 'https://elior-studio-default-rtdb.firebaseio.com/whatsapp';

export default {
  async fetch(request) {
    const url = new URL(request.url);

    // Meta's one-time webhook verification handshake
    if (request.method === 'GET') {
      if (url.searchParams.get('hub.mode') === 'subscribe' &&
          url.searchParams.get('hub.verify_token') === VERIFY_TOKEN) {
        return new Response(url.searchParams.get('hub.challenge') || '', { status: 200 });
      }
      return new Response('ravid-studio-whatsapp-webhook', { status: 200 });
    }

    if (request.method !== 'POST') return new Response('ok', { status: 200 });

    let body = null;
    try { body = await request.json(); } catch (_) { return new Response('ok', { status: 200 }); }

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
            const ph = String(m.from || '').replace(/\D/g, '');
            const rec = {
              dir: 'in',
              phone: ph,
              name: (v.contacts && v.contacts[0] && v.contacts[0].profile && v.contacts[0].profile.name) || '',
              type: m.type || '',
              text: (m.text && m.text.body) || m.caption || ('[' + (m.type || 'הודעה') + ']'),
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
          // Delivery/read receipts — known noise, count as handled.
          if (Array.isArray(v.statuses) && v.statuses.length) stored++;
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

    return new Response('ok', { status: 200 });
  }
};
