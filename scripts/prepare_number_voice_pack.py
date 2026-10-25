"""Prepare a finite Microsoft number pack; never called by CI or the phone.

Explicit --generate uses the configured personal service. Completed files and
the service cache are reused. No credentials or raw upstream errors are printed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request
import wave

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "SlowRun/Resources/VoicePack/numbers"
VOICE = "zh-CN-XiaoxiaoNeural"


def chinese(number):
    digits = "零一二三四五六七八九"
    if number < 10:
        return digits[number]
    return (digits[number // 10] if number >= 20 else "") + "十" + (digits[number % 10] if number % 10 else "")


def texts():
    result = {
        "pace": "当前配速每公里", "target": "目标每公里",
        "good": "刚刚好。", "fast": "有点快了。",
        "slow": "有点慢了。",
        "remaining": "本段跑步还剩", "complete": "已完成",
        "lap": "这一公里用时", "total": "累计主要训练用时", "zero": "零秒。",
    }
    for prefix, unit, maximum in (("minute", "分", 59), ("second", "秒", 59), ("hour", "小时", 12), ("km", "公里", 50)):
        for n in range(1, maximum + 1):
            result[f"{prefix}_{n}"] = chinese(n) + unit
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--service-url", default="http://127.0.0.1:8787")
    parser.add_argument("--work-dir", type=Path, default=ROOT / "outputs/number-voice-work")
    args = parser.parse_args()
    path = PACK / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"voice": VOICE, "sampleRate": 24000, "clips": {}}
    if args.generate:
        sys.path.insert(0, str(ROOT))
        from service.server import load_env
        load_env(ROOT / "service/.env")
        args.work_dir.mkdir(parents=True, exist_ok=True)
        PACK.mkdir(parents=True, exist_ok=True)
    for index, (key, text) in enumerate(texts().items(), 1):
        audio_path = PACK / (key + ".wav")
        clip = manifest["clips"].get(key, {})
        audio = audio_path.read_bytes() if audio_path.exists() else b""
        if not (audio and clip.get("text") == text and clip.get("sha256") == hashlib.sha256(audio).hexdigest()):
            if not args.generate:
                raise SystemExit("Missing/stale number recording: " + key)
            request = urllib.request.Request(args.service_url.rstrip("/") + "/v1/voice",
                data=json.dumps({"text": text, "voice": VOICE}, ensure_ascii=False).encode(),
                headers={"Content-Type": "application/json", "Authorization": "Bearer " + os.environ["SERVICE_ACCESS_TOKEN"]})
            for attempt in range(4):
                try:
                    with urllib.request.urlopen(request, timeout=20) as response:
                        mp3 = response.read(5_000_001)
                    break
                except urllib.error.HTTPError as error:
                    if error.code != 429 or attempt == 3:
                        raise SystemExit(f"Recording {key} stopped (HTTP {error.code}); completed files preserved.") from None
                    print("Provider rate limit; waiting before this unfinished clip.", flush=True)
                    time.sleep(60)
            assert 0 < len(mp3) < 5_000_000
            raw = args.work_dir / (key + ".mp3")
            raw.write_bytes(mp3)
            temporary = args.work_dir / (key + ".wav")
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(raw), "-af",
                "silenceremove=start_periods=1:start_duration=0.02:start_threshold=-48dB:start_silence=0.025,areverse,silenceremove=start_periods=1:start_duration=0.02:start_threshold=-48dB:start_silence=0.035,areverse",
                "-ac", "1", "-ar", "24000", "-c:a", "pcm_s16le", str(temporary)], check=True)
            # Canonical 44-byte PCM header, no ffmpeg metadata chunks.
            with wave.open(str(temporary), "rb") as src:
                assert (src.getnchannels(), src.getsampwidth(), src.getframerate()) == (1, 2, 24000)
                frames = src.readframes(src.getnframes())
            assert len(frames) > 2400, "Unexpectedly short recording"
            with wave.open(str(audio_path), "wb") as dst:
                dst.setparams((1, 2, 24000, 0, "NONE", "not compressed"))
                dst.writeframes(frames)
            audio = audio_path.read_bytes()
            manifest["clips"][key] = {"text": text, "sha256": hashlib.sha256(audio).hexdigest()}
            temp_manifest = path.with_suffix(".tmp")
            temp_manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            temp_manifest.replace(path)
        with wave.open(str(audio_path), "rb") as src:
            assert (src.getnchannels(), src.getsampwidth(), src.getframerate()) == (1, 2, 24000)
            assert src.getnframes() > 1200
        print(f"Ready {index}/{len(texts())}: {key}", flush=True)
    assert set(manifest["clips"]) == set(texts())
    print("PASS: complete offline Microsoft number pack; hashes and PCM format verified.", flush=True)


if __name__ == "__main__":
    main()
