// Icon generator — pure Node (no deps). Draws a dumbbell on a teal→indigo
// gradient and writes icon-192.png + icon-512.png. Part of the reusable base.
const fs = require('fs');
const zlib = require('zlib');

// ── CRC32 (for PNG chunks) ──
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const body = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function lerp(a, b, t) { return Math.round(a + (b - a) * t); }
function hex(h) { return [parseInt(h.slice(1,3),16), parseInt(h.slice(3,5),16), parseInt(h.slice(5,7),16)]; }

// Rounded-rect coverage with 2x supersampling for smooth edges
function inRR(x, y, x0, y0, x1, y1, r) {
  if (x < x0 || x > x1 || y < y0 || y > y1) return false;
  const cx = Math.min(Math.max(x, x0 + r), x1 - r);
  const cy = Math.min(Math.max(y, y0 + r), y1 - r);
  const dx = x - cx, dy = y - cy;
  return dx * dx + dy * dy <= r * r;
}

function makeIcon(s, rgb) {
  const top = hex('#14b8a6'), bot = hex('#6366f1');
  const cy = s * 0.5;
  // dumbbell geometry (relative to size)
  const parts = [
    // bar
    [0.355, 0.45, 0.645, 0.55, 0.03],
    // left plates
    [0.27, 0.30, 0.355, 0.70, 0.035],
    [0.205, 0.36, 0.27, 0.64, 0.03],
    [0.16, 0.42, 0.205, 0.58, 0.025],
    // right plates
    [0.645, 0.30, 0.73, 0.70, 0.035],
    [0.73, 0.36, 0.795, 0.64, 0.03],
    [0.795, 0.42, 0.84, 0.58, 0.025],
  ].map(p => [p[0]*s, p[1]*s, p[2]*s, p[3]*s, p[4]*s]);

  const ch = rgb ? 3 : 4;
  const raw = Buffer.alloc(s * (s * ch + 1));
  let o = 0;
  for (let y = 0; y < s; y++) {
    raw[o++] = 0; // filter byte
    for (let x = 0; x < s; x++) {
      // background diagonal gradient
      const t = (x + y) / (2 * s);
      let r = lerp(top[0], bot[0], t);
      let g = lerp(top[1], bot[1], t);
      let b = lerp(top[2], bot[2], t);
      // dumbbell coverage (2x2 supersample)
      let cov = 0;
      for (let sy = 0; sy < 2; sy++) for (let sx = 0; sx < 2; sx++) {
        const px = x + (sx + 0.5) / 2, py = y + (sy + 0.5) / 2;
        if (parts.some(p => inRR(px, py, p[0], p[1], p[2], p[3], p[4]))) cov++;
      }
      if (cov > 0) {
        const a = cov / 4;
        r = lerp(r, 255, a); g = lerp(g, 255, a); b = lerp(b, 255, a);
      }
      raw[o++] = r; raw[o++] = g; raw[o++] = b;
      if (!rgb) raw[o++] = 255;
    }
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(s, 0); ihdr.writeUInt32BE(s, 4);
  ihdr[8] = 8; ihdr[9] = rgb ? 2 : 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const idat = zlib.deflateSync(raw, { level: 9 });
  const sig = Buffer.from([0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A]);
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}

fs.writeFileSync('icon-192.png', makeIcon(192));
fs.writeFileSync('icon-512.png', makeIcon(512));
console.log('✓ wrote icon-192.png + icon-512.png');

// iOS app icon (1024, RGB — no alpha allowed in App Store icons)
const iosPath = 'native/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png';
if (fs.existsSync('native/ios/App/App/Assets.xcassets/AppIcon.appiconset')) {
  fs.writeFileSync(iosPath, makeIcon(1024, true));
  console.log('✓ wrote iOS app icon (1024)');
}
