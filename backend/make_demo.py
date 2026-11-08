"""Create the portable procedural demo; no recordings or private paths required."""
import json

from engine import ROOT


def demo_project():
    objects = []
    for index, (kind, name, x, y, z) in enumerate([
        ('wind', '风声 · 由远及近', 0, 6, .3),
        ('rain', '雨幕 · 左后方', -3, -2, 2),
        ('rain', '雨幕 · 右后方', 3, -2, 2),
    ]):
        obj = dict(id=f'demo-{index}', name=name, kind='ambience', generator=kind,
                   path='', duration=30, seed=71+index*7, colorIndex=index,
                   x=x, y=y, z=z, gain=-12, reverb=.25, echo=0,
                   distortion=0, spread=.65, decay=2.6, delayMs=280,
                   feedback=.42, lowpass=15000, highpass=80,
                   interpolation='smooth', waveform=[], keyframes=[])
        if index == 0:
            obj['keyframes'] = [dict(time=t, x=0, y=distance, z=.3,
                                    gain=gain, reverb=wet, spread=.35)
                                for t, distance, gain, wet in
                                [(0, 6, -12, .5), (12, 3, -9, .35), (24, 1.2, -6, .2)]]
        objects.append(obj)
    return dict(schemaVersion=2, name='ORBIT · 程序化雨夜示例', duration=30,
                masterGain=-3, tail=3, hrtf='', protectPeaks=True,
                listener=dict(x=0, y=0, z=0, yaw=0, pitch=0), objects=objects)


def make_demo():
    folder = ROOT / 'projects'
    folder.mkdir(exist_ok=True)
    destination = folder / 'procedural.orbit.json'
    destination.write_text(json.dumps(demo_project(), ensure_ascii=False, indent=2), encoding='utf-8')
    print('Created procedural demo: 3 objects / 30 seconds; no external audio.')


if __name__ == '__main__':
    make_demo()
