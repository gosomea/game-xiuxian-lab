"""Reproduce the exploration's original synthetic impact cues (Python stdlib)."""
from pathlib import Path
import math, random, struct, wave
root = Path(__file__).resolve().parents[3]
out = root / 'src/game/shared/sword_cast/audio'
out.mkdir(parents=True, exist_ok=True)
rate = 44100
for name, length, heavy in [('giant_impact', .7, True), ('light_sword', .23, False)]:
    rng = random.Random(20261010 + heavy)
    samples = []
    for i in range(int(rate * length)):
        t = i / rate
        if heavy:
            attack = min(t / .004, 1)
            low = math.sin(2 * math.pi * (65*t - 20*t*t)) * math.exp(-t*8)
            ring = math.sin(2*math.pi*240*t) * math.exp(-t*12)
            noise = rng.uniform(-1, 1)*math.exp(-t*30)
            value = attack * (.6*low + .12*ring + .2*noise)
        else:
            attack = min(t/.002, 1)
            value = attack*(.3*math.sin(2*math.pi*(620*t-450*t*t))*math.exp(-t*20)+.13*rng.uniform(-1,1)*math.exp(-t*45))
        samples.append(struct.pack('<h', int(max(-1, min(1,value))*32767)))
    with wave.open(str(out / (name+'.wav')), 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate); f.writeframes(b''.join(samples))
