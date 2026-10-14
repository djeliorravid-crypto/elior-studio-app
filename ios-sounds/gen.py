# Synthesize short notification sounds (pure python, 44.1kHz 16-bit mono WAV)
import math, struct, wave, random
SR = 44100
def env(t, a, d):  # attack / exponential decay
    return (t / a if t < a else math.exp(-(t - a) / d))
def bell(f, t, d=0.55):  # soft bell: fundamental + inharmonic partials
    return (math.sin(2*math.pi*f*t) * 1.0 + math.sin(2*math.pi*f*2.76*t) * 0.32 * math.exp(-t*6)
            + math.sin(2*math.pi*f*5.4*t) * 0.12 * math.exp(-t*11)) * env(t, 0.004, d)
def marimba(f, t, d=0.28):
    return (math.sin(2*math.pi*f*t) + 0.45*math.sin(2*math.pi*f*4*t)*math.exp(-t*18)) * env(t, 0.002, d)
def pad(f, t, d=0.9):
    return (math.sin(2*math.pi*f*t) + 0.5*math.sin(2*math.pi*f*2.001*t) + 0.25*math.sin(2*math.pi*f*3.003*t)) * env(t, 0.06, d)
def render(name, notes, total, gain=0.5):
    n = int(SR * total); buf = [0.0] * n
    for (start, fn, f, d, a) in notes:
        s0 = int(start * SR)
        for i in range(s0, n):
            t = (i - s0) / SR
            v = fn(f, t, d)
            if abs(v) < 1e-5 and t > d * 4: break
            buf[i] += v * a
    peak = max(abs(x) for x in buf) or 1
    # gentle room: tiny early reflections
    out = buf[:]
    for dl, g in ((0.031, .18), (0.053, .12), (0.089, .08)):
        k = int(dl * SR)
        for i in range(k, n): out[i] += buf[i - k] * g
    peak = max(abs(x) for x in out) or 1
    fade = int(0.06 * SR)
    with wave.open(name, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        fr = bytearray()
        for i, x in enumerate(out):
            if i > n - fade: x *= (n - i) / fade
            fr += struct.pack('<h', int(max(-1, min(1, x / peak * gain)) * 32767))
        w.writeframes(bytes(fr))
N = lambda m: 440 * 2 ** ((m - 69) / 12)
# 1 "חתימה" — two soft bell notes rising a fifth then a gentle third (like the signature stroke + dot)
render('1-signature.wav', [(0, bell, N(76), .45, 1), (0.14, bell, N(83), .55, .85), (0.30, bell, N(88), .7, .55)], 1.4)
# 2 "מאסטרו" — warm marimba three-note motif (ma-es-tro)
render('2-maestro.wav', [(0, marimba, N(72), .25, 1), (0.12, marimba, N(79), .25, .9), (0.24, marimba, N(84), .4, 1)], 1.0)
# 3 "נשימה" — single soft pad chord swelling (calm, premium)
render('3-breath.wav', [(0, pad, N(64), .7, .8), (0, pad, N(71), .7, .6), (0.02, pad, N(76), .8, .5), (0.25, bell, N(88), .5, .35)], 1.6, gain=.45)
# 4 "טיפה" — one clean high chime with a tiny echo (short, discreet)
render('4-drop.wav', [(0, bell, N(91), .35, 1), (0.18, bell, N(91), .3, .35)], 0.9)
print('ok')
