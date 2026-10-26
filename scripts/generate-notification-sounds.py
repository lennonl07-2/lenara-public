#!/usr/bin/env python3
"""Generate original, normalized PCM notification tones for Lenara."""
import math
import os
import struct
import wave

ROOT = os.path.join(os.path.dirname(__file__), "..", "Lenara", "Resources", "NotificationSounds")
RATE = 44100


def tone(path, notes, duration, peak=0.94):
    samples = int(RATE * duration)
    frames = bytearray()
    for index in range(samples):
        t = index / RATE
        value = 0.0
        for start, end, frequency, amplitude in notes:
            if start <= t < end:
                local = t - start
                length = end - start
                attack = min(1.0, local / 0.018)
                release = min(1.0, (length - local) / 0.09)
                envelope = max(0.0, min(attack, release))
                value += amplitude * envelope * (
                    math.sin(2 * math.pi * frequency * local)
                    + 0.22 * math.sin(2 * math.pi * frequency * 2.01 * local)
                    + 0.08 * math.sin(2 * math.pi * frequency * 3.98 * local)
                )
        value = max(-1.0, min(1.0, value / 1.25 * peak))
        frames.extend(struct.pack("<h", round(value * 32767)))
    with wave.open(os.path.join(ROOT, path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(frames)


os.makedirs(ROOT, exist_ok=True)
tone("Brisa.wav", [(0, .3, 784, .55), (.16, .65, 1175, .6)], .72)
tone("Gota.wav", [(0, .24, 1319, .6), (.18, .48, 988, .58), (.42, .78, 784, .62)], .86)
tone("Destello.wav", [(0, .28, 1047, .54), (.16, .5, 1568, .48), (.34, .88, 2093, .58)], .98)
tone("Latido.wav", [(0, .22, 660, .65), (.31, .55, 660, .72), (.7, .96, 880, .64)], 1.08)
tone("Aurora.wav", [(i * .32, i * .32 + .38, f, .52) for i, f in enumerate([523, 659, 784, 988, 1175, 988, 1175, 1568])], 3.2)
tone("Llamado.wav", [(i * .48, i * .48 + .36, f, .7) for i, f in enumerate([784, 988, 1175, 988, 784, 988, 1175, 1568, 1175, 988, 1175, 1568])], 6.0)
