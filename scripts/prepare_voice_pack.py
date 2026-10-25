"""Explicitly generate the finite offline voice pack via the personal service.

Never run in CI. --generate authorizes the short, fixed synthesis requests;
unchanged recordings are reused. Keys/tokens are not packaged or printed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import urllib.request
import os

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "SlowRun/Resources/VoicePack"
VOICE = "zh-CN-XiaoxiaoNeural"


def texts():
    source = (ROOT / "RunCore/Sources/RunCore/FixedVoiceCue.swift").read_text(encoding="utf-8")
    cues = dict(re.findall(r'case \.(\w+): return "([^"\n]+)"', source))
    tips = (ROOT / "RunCore/Sources/RunCore/CoachingTip.swift").read_text(encoding="utf-8")
    speech = tips.split("public var speech: String", 1)[1].split("public var sourceTitle", 1)[0]
    phrases = dict(re.findall(r'case \.(\w+): return "([^"\n]+)"', speech))
    cues["coaching"] = " ".join(phrases[key] for key in ("posture", "breathing", "effort"))
    assert set(cues) == {"warmup", "run", "walk", "cooldown", "tooFast", "slowing", "coaching", "finished", "freeRunStarted"}
    assert all(0 < len(text) <= 300 for text in cues.values())
    return cues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--service-url", default="http://127.0.0.1:8787")
    parser.add_argument("--env-file", type=Path, default=ROOT / "service/.env")
    args = parser.parse_args()
    manifest_path = PACK / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {"voice": VOICE, "clips": {}}
    assert manifest["voice"] == VOICE
    if args.generate:
        sys.path.insert(0, str(ROOT))
        from service.server import load_env
        load_env(args.env_file)
    for name, text in texts().items():
        path = PACK / (name + ".mp3")
        clip = manifest["clips"].get(name, {})
        current = path.read_bytes() if path.exists() else b""
        valid = current and clip.get("text") == text and clip.get("sha256") == hashlib.sha256(current).hexdigest()
        if not valid:
            if not args.generate:
                raise SystemExit("Voice pack missing/stale: " + name + ". Run explicitly with --generate.")
            payload = json.dumps({"text": text, "voice": VOICE}, ensure_ascii=False).encode("utf-8")
            request = urllib.request.Request(args.service_url.rstrip("/") + "/v1/voice", data=payload,
                headers={"Content-Type": "application/json", "Authorization": "Bearer " + os.environ["SERVICE_ACCESS_TOKEN"]})
            with urllib.request.urlopen(request, timeout=15) as response:
                assert response.headers.get_content_type().startswith("audio/")
                current = response.read(5_000_001)
            assert 0 < len(current) < 5_000_000
            assert current.startswith(b"ID3") or current[0] == 0xFF, "Expected MPEG audio"
            PACK.mkdir(parents=True, exist_ok=True)
            path.write_bytes(current)
            manifest["clips"][name] = {"text": text, "sha256": hashlib.sha256(current).hexdigest()}
            temporary = manifest_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            temporary.replace(manifest_path)
        print("Ready:", name, len(current), "bytes", flush=True)
    print("PASS: 9 offline Microsoft recordings match the current source; no credentials included.")


if __name__ == "__main__":
    main()
