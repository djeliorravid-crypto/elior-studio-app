#!/usr/bin/env python3
"""Refresh the ?h=<hash> on index.html's asset links so phones always load the
matching version (the service worker caches by full URL). Run after editing
js/app.js, css/base.css or css/spent.css."""
import hashlib, re, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
p = os.path.join(ROOT, 'index.html')
s = open(p, encoding='utf-8').read()
changed = 0
for f in ('js/app.js', 'css/base.css', 'css/spent.css'):
    h = hashlib.sha1(open(os.path.join(ROOT, f), 'rb').read()).hexdigest()[:10]
    s2 = re.sub(re.escape(f) + r'\?h=[0-9a-f]+', f + '?h=' + h, s)
    if s2 != s: changed += 1
    s = s2
open(p, 'w', encoding='utf-8').write(s)
print('assets ok' + (' (updated %d)' % changed if changed else ''))
