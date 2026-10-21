"""Original short interface tones. No external sound recordings."""
import math, random, struct, wave
from pathlib import Path

RATE = 48000
folder = Path(__file__).resolve().parent.parent / 'app' / 'assets' / 'sounds'
folder.mkdir(parents=True, exist_ok=True)
random.seed(7)


def note(start, length, f0, f1=None, decay=30, attack=.002, partials=((1, 1),)):
    """A sine voice that may glide from f0 to f1, with a soft attack and an exponential tail."""
    f1 = f1 or f0
    def voice(t):
        t -= start
        if t < 0 or t > length:
            return 0
        k = t / length
        # Phase of a linear glide: integral of f0 + (f1 - f0) * t / length.
        phase = 2 * math.pi * (f0 * t + (f1 - f0) * t * k / 2)
        env = min(1, t / attack) * math.exp(-t * decay) * min(1, (length - t) / .006)
        return env * sum(a * math.sin(phase * m) for m, a in partials)
    return voice


def click(length=.003, gain=.5):
    """A tiny filtered noise transient, so taps read as physical."""
    last = 0
    samples = []
    for i in range(round(RATE * length)):
        last = last * .55 + random.uniform(-1, 1) * .45
        samples.append(last * gain * (1 - i / (RATE * length)))
    return lambda t: samples[int(t * RATE)] if t * RATE < len(samples) else 0


bell = ((1, 1), (2, .18), (2.76, .06))
sounds = {
    'tap': (.032, .10, [note(0, .032, 1650, decay=140, partials=((1, 1), (1.5, .25))), click()]),
    'nav': (.050, .08, [note(0, .050, 1046, decay=70, partials=((1, 1), (1.5, .3))), click(gain=.3)]),
    'add': (.140, .11, [note(0, .07, 659, decay=40, partials=bell), note(.045, .095, 988, decay=34, partials=bell)]),
    'complete': (.180, .12, [note(0, .08, 784, decay=30, partials=bell), note(.05, .13, 1175, decay=24, partials=bell)]),
    'undo': (.120, .09, [note(0, .06, 880, decay=40, partials=bell), note(.04, .08, 659, decay=36, partials=bell)]),
    'delete': (.150, .12, [note(0, .15, 420, 220, decay=24, partials=((1, 1), (2, .2))), click(.006, .35)]),
    'open': (.110, .06, [note(0, .11, 620, 1120, decay=22, attack=.012, partials=((1, 1), (2, .12)))]),
    'close': (.100, .06, [note(0, .10, 1000, 600, decay=26, attack=.008, partials=((1, 1), (2, .12)))]),
    'toggle_on': (.055, .09, [note(0, .055, 1320, decay=80, partials=((1, 1), (2, .15))), click()]),
    'toggle_off': (.055, .08, [note(0, .055, 990, decay=80, partials=((1, 1), (2, .15))), click()]),
    'error': (.210, .09, [note(0, .1, 330, decay=18, partials=((1, 1), (3, .18))), note(.09, .12, 277, decay=18, partials=((1, 1), (3, .18)))]),
}

for name, (duration, gain, voices) in sounds.items():
    frames = []
    for i in range(round(RATE * duration)):
        t = i / RATE
        value = gain * sum(v(t) for v in voices)
        frames.append(struct.pack('<h', round(max(-1, min(1, value)) * 32767)))
    # Windows Media Foundation can drop clips this short; a silent tail keeps
    # every tone at 150 ms so it starts and reports completion reliably.
    frames += [struct.pack('<h', 0)] * max(0, round(RATE * .15) - len(frames))
    with wave.open(str(folder / (name + '.wav')), 'wb') as wav:
        wav.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        wav.writeframes(b''.join(frames))
    print(name, f'{duration * 1000:.0f} ms')
