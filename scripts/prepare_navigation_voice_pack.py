"""Validate or explicitly synthesize ten finite offline Microsoft navigation cues.

Only --generate contacts the user's existing Azure Speech resource. No credentials
or precise locations are printed, committed, or included in the app.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'SlowRun/Resources/VoicePack/navigation'
VOICE = 'zh-CN-XiaoxiaoNeural'


def texts():
    source = (ROOT / 'RunCore/Sources/RunCore/Navigation.swift').read_text(encoding='utf-8')
    section = source.split('public enum NavigationVoice:', 1)[1].split('public struct NavigationCue:', 1)[0]
    result = dict(re.findall(r'case \.(\w+): return "([^"\n]+)"', section))
    assert len(result) == 10
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generate', action='store_true')
    args = parser.parse_args()
    path = PACK / 'manifest.json'
    manifest = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {'voice': VOICE, 'clips': {}}
    if args.generate:
        sys.path.insert(0, str(ROOT))
        from service.server import load_env, Service, Config, PublicError
        load_env(ROOT / 'service/.env')
        service = Service(Config.from_env())
        PACK.mkdir(parents=True, exist_ok=True)
    for key, text in texts().items():
        file = PACK / (key + '.mp3')
        data = file.read_bytes() if file.exists() else b''
        entry = manifest['clips'].get(key, {})
        if not data or entry.get('text') != text or entry.get('sha256') != hashlib.sha256(data).hexdigest():
            if not args.generate:
                raise SystemExit('Missing or stale navigation clip: ' + key)
            try:
                data, mime = service.voice({'text': text, 'voice': VOICE})
            except PublicError as error:
                raise SystemExit(f'Navigation audio stopped: {key}, HTTP {error.status}; completed clips retained.') from None
            assert mime == 'audio/mpeg' and 100 < len(data) < 1_000_000
            file.write_bytes(data)
            manifest['clips'][key] = {'text': text, 'sha256': hashlib.sha256(data).hexdigest()}
            temp = path.with_suffix('.tmp')
            temp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            temp.replace(path)
        assert data.startswith(b'ID3') or data[0] == 0xFF
        print('Ready:', key, len(data), 'bytes', flush=True)
    assert set(manifest['clips']) == set(texts())
    print('PASS: 10 offline Microsoft navigation recordings verified.')


if __name__ == '__main__':
    main()
