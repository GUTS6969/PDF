"""Narration for $0 on this computer: local Kokoro-82M Q8, with a CC0 Piper fallback. No account, no API.

  scripts/py scripts/voice.py <project>          script.json -> data/narration.wav + data/lines.json (exact line times)
  scripts/py scripts/voice.py --list             voices that narrate well
  scripts/py scripts/voice.py --download         verify installed local voice files

script.json: { "voice": "am_michael", "speed": 1.05, "lead": 0.45, "outro": 0.9, "gap": 0.32,
               "lines": [ { "text": "What if you swallow gum?", "caps": "...", "gap": 0.3 }, ... ] }
One line = one CUT, not one sentence: a sentence can run across several lines ("It slides down your throat and lands
in your stomach," / "where acid gets to work on it."). Lines are grouped into whole sentences and each sentence is
spoken in ONE pass, so the intonation flows naturally; then every cut inside a sentence is found in the audio (snapped
to the nearest pause, else placed by length). "gap" (on a sentence's last line) = the pause after that sentence.
Write numbers the way they're SAID. Then run words.py for the word timings.
"""
import argparse, json, os, re, sys, urllib.request
from pathlib import Path
import numpy as np
from scipy import signal
from scipy.io import wavfile

HOME = Path(os.environ.get('FACELESS_HOME', Path.home() / '.faceless-shorts'))
KDIR = HOME / 'kokoro'
# Compact Kokoro-82M Q8 model and its locally packed English voice styles.
# It is fully local, loaded through the existing kokoro-onnx CPU runtime.
KQ8_DIR = HOME / 'models' / 'kokoro-82m-q8'
KQ8_MODEL = KQ8_DIR / 'onnx' / 'model_quantized.onnx'
KQ8_VOICES = KQ8_DIR / 'voices.npz'
PIPER_MODEL = HOME / 'models' / 'piper' / 'en_US-joe-medium.onnx'
FILES = {
    'kokoro-v1.0.onnx': 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx',
    'voices-v1.0.bin': 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin',
}
GOOD = {
    'am_michael': 'US male, steady explainer (default)', 'am_puck': 'US male, lively, playful', 'am_fenrir': 'US male, deeper',
    'am_onyx': 'US male, low', 'af_heart': 'US female, warm (best overall)', 'af_bella': 'US female, bright',
    'af_nicole': 'US female, soft and close', 'bm_george': 'UK male, documentary', 'bm_fable': 'UK male, storyteller',
    'bf_emma': 'UK female, calm',
}
SR = 24000


def kokoro_q8_ready():
    return KQ8_MODEL.exists() and KQ8_MODEL.stat().st_size > 90_000_000 and KQ8_VOICES.exists()


def kokoro_ready():
    return all((KDIR / name).exists() and (KDIR / name).stat().st_size > 1_000_000 for name in FILES)


def piper_ready():
    return PIPER_MODEL.exists() and PIPER_MODEL.with_suffix('.onnx.json').exists()


def ensure_models():
    """Prefer local Kokoro-82M Q8, then original Kokoro, with Piper as fallback."""
    if kokoro_q8_ready(): return 'kokoro-q8'
    if kokoro_ready(): return 'kokoro'
    if piper_ready(): return 'piper'
    KDIR.mkdir(parents=True, exist_ok=True)
    for name, url in FILES.items():
        p = KDIR / name
        if p.exists() and p.stat().st_size > 1_000_000: continue
        print(f'downloading {name} (once)...', flush=True)
        tmp = p.with_suffix('.part'); urllib.request.urlretrieve(url, tmp); tmp.rename(p)
    return 'kokoro'


def trim(x, thr=0.008):
    """cut leading/trailing silence so line start/end times are exact"""
    idx = np.where(np.abs(x) > thr)[0]
    if not len(idx): return x
    a = max(0, idx[0] - int(0.01 * SR)); b = min(len(x), idx[-1] + int(0.03 * SR)); return x[a:b]


def silences(x, thr=0.012, min_len=0.06):
    """pauses inside speech: [(start_s, end_s)] where the 10 ms RMS stays under thr for >= min_len"""
    hop = int(0.01 * SR); n = len(x) // hop
    rms = np.sqrt(np.mean(x[:n * hop].reshape(n, hop) ** 2, axis=1)); quiet = rms < thr * np.abs(x).max()
    out, st = [], None
    for f, q in enumerate(quiet):
        if q and st is None: st = f
        if (not q or f == n - 1) and st is not None:
            if (f - st) * 0.01 >= min_len: out.append((st * 0.01, f * 0.01))
            st = None
    return out


def make_kokoro_q8_say(voice_name, speed):
    """Run the local Q8 Kokoro ONNX export with its packaged 28 English voices."""
    from kokoro_onnx import Kokoro
    k = Kokoro(str(KQ8_MODEL), str(KQ8_VOICES))

    # The compact Transformers.js ONNX export expects style as [1, 256].
    # kokoro-onnx's older v1 export uses [256], so adapt only this model's
    # inference input while preserving its tokenizer and natural pause logic.
    def q8_infer(tokens, style, rate):
        inputs = {
            k._tokens_input: np.array([[0, *tokens, 0]], dtype=k._input_dtypes[k._tokens_input]),
            'style': np.asarray(style, dtype=k._input_dtypes['style']).reshape(1, -1),
            'speed': np.array([k._speed_value(rate)], dtype=k._input_dtypes['speed']),
        }
        return np.asarray(k.sess.run(None, inputs)[0]).ravel(), None

    k._infer = q8_infer
    lang = 'en-gb' if voice_name.startswith('b') else 'en-us'
    return lambda text: trim(np.asarray(k.create(text, voice=voice_name, speed=speed, lang=lang)[0], dtype=np.float64))


def make_piper_say(speed):
    """Return a Kokoro-compatible 24 kHz synthesis function using the CC0 Piper voice."""
    from piper import PiperVoice
    from piper.config import SynthesisConfig
    voice = PiperVoice.load(PIPER_MODEL)
    config = SynthesisConfig(length_scale=1 / max(speed, 0.1))

    def say(text):
        chunks = [chunk.audio_float_array for chunk in voice.synthesize(text, config)]
        x = np.concatenate(chunks) if chunks else np.zeros(1, dtype=np.float32)
        if voice.config.sample_rate != SR:
            x = signal.resample_poly(x, SR, voice.config.sample_rate)
        return trim(np.asarray(x, dtype=np.float64))

    return say


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('project', nargs='?'); ap.add_argument('--list', action='store_true'); ap.add_argument('--download', action='store_true')
    ap.add_argument('--voice'); ap.add_argument('--speed', type=float)
    a = ap.parse_args()
    if a.list:
        for k, v in GOOD.items(): print(f'{k:12s} {v}')
        return
    engine = ensure_models()
    if a.download:
        print(f'{engine} voice model ready')
        return
    if not a.project: ap.error('project folder missing')
    P = Path(a.project); S = json.loads((P / 'script.json').read_text())
    voice = a.voice or S.get('voice', 'am_michael'); speed = a.speed or S.get('speed', 1.0)
    if engine == 'kokoro-q8':
        print(f'Using local Kokoro-82M Q8 voice: {voice}.', flush=True)
        say = make_kokoro_q8_say(voice, speed)
        voice_used = voice
    elif engine == 'kokoro':
        from kokoro_onnx import Kokoro
        k = Kokoro(str(KDIR / 'kokoro-v1.0.onnx'), str(KDIR / 'voices-v1.0.bin'))
        lang = 'en-gb' if voice.startswith('b') else 'en-us'
        say = lambda text: trim(np.asarray(k.create(text, voice=voice, speed=speed, lang=lang)[0], dtype=np.float64))
        voice_used = voice
    else:
        print(f'Kokoro model unavailable; using the free local Piper Joe voice instead of {voice}.', flush=True)
        say = make_piper_say(speed)
        voice_used = 'piper-joe'
    # group the lines into whole sentences (a line ending in . ? ! closes one; "break": true forces a close)
    groups, cur = [], []
    for i, ln in enumerate(S['lines']):
        cur.append(i)
        if re.search(r'[.?!]["\')]*$', ln['text'].strip()) or ln.get('break') or i == len(S['lines']) - 1: groups.append(cur); cur = []
    out = [np.zeros(int(S.get('lead', 0.4) * SR))]; t = len(out[0]) / SR; lines = [None] * len(S['lines'])
    for g in groups:
        x = say(' '.join(S['lines'][i]['text'] for i in g))
        cuts = [0.0]
        if len(g) > 1:                                    # find each cut inside the sentence
            lens = np.array([len(say(S['lines'][i]['text'])) for i in g], dtype=float)
            pauses = silences(x)
            for c in np.cumsum(lens)[:-1] / lens.sum() * len(x) / SR:
                near = [p for p in pauses if abs((p[0] + p[1]) / 2 - c) < 0.4]
                if near: p = min(near, key=lambda p: abs((p[0] + p[1]) / 2 - c)); cuts.append((p[0], p[1]))
                else: cuts.append((c, c))
        n = len(x) / SR
        for j, i in enumerate(g):
            a = 0.0 if j == 0 else cuts[j][1]; b = n if j == len(g) - 1 else cuts[j + 1][0]
            lines[i] = {'i': i, 'text': S['lines'][i]['text'], 'start': round(t + a, 3), 'end': round(t + b, 3)}
            print(f'{i:2d} {lines[i]["start"]:6.2f}-{lines[i]["end"]:6.2f}  {S["lines"][i]["text"]}', flush=True)
        gap = np.zeros(int(float(S['lines'][g[-1]].get('gap', S.get('gap', 0.3))) * SR))
        out += [x, gap]; t += (len(x) + len(gap)) / SR
    outro = np.zeros(int(float(S.get('outro', 0.9)) * SR)); out.append(outro)
    y = np.concatenate(out); y = y / (np.abs(y).max() + 1e-9) * 0.9
    (P / 'data').mkdir(exist_ok=True)
    wavfile.write(P / 'data/narration.wav', SR, (y * 32767).astype(np.int16))
    dur = len(y) / SR
    (P / 'data/lines.json').write_text(json.dumps({'duration': round(dur, 3), 'voice': voice_used, 'speed': speed, 'lines': lines}, indent=1))
    print(f'data/narration.wav ({dur:.2f} s, {voice_used} x{speed}) + data/lines.json. Next: words.py')


if __name__ == '__main__':
    main()
