#!/usr/bin/env python3
"""Refresh the ?h=<hash> on the pages' asset links so phones always load the
matching version (the service worker caches by full URL). Run after editing
js/app.js, css/base.css or css/spent.css. Also rebuilds js/wedding.js (the
wedding page for Dri) from app.js first, so it never drifts."""
import hashlib, re, os, sys, subprocess
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
subprocess.run([sys.executable, os.path.join(ROOT, 'tools/build-wedding.py')], check=True, stdout=subprocess.DEVNULL)
changed = 0
for page in ('index.html', 'wedding.html'):
    p = os.path.join(ROOT, page)
    if not os.path.exists(p): continue
    s = open(p, encoding='utf-8').read()
    for f in ('js/app.js', 'js/wedding.js', 'css/base.css', 'css/spent.css'):
        h = hashlib.sha1(open(os.path.join(ROOT, f), 'rb').read()).hexdigest()[:10]
        s2 = re.sub(re.escape(f) + r'\?h=[0-9a-f]+', f + '?h=' + h, s)
        if s2 != s: changed += 1
        s = s2
    open(p, 'w', encoding='utf-8').write(s)
print('assets ok' + (' (updated %d)' % changed if changed else ''))
