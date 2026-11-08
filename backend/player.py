"""Isolated Windows PCM playback so a device failure cannot terminate the editor."""
import json
import sys
import wave
import winsound

try:
    path=sys.argv[1]
    with wave.open(path,'rb') as source:
        duration=source.getnframes()/source.getframerate()
    print(json.dumps(dict(event='playing',duration=duration)),flush=True)
    winsound.PlaySound(path,winsound.SND_FILENAME|winsound.SND_NODEFAULT)
    print(json.dumps(dict(event='complete')),flush=True)
except Exception as exc:
    print(json.dumps(dict(event='error',message=str(exc))),flush=True)
    sys.exit(1)
