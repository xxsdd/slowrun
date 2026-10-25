"""Verify IPA packaging and device architecture metadata, not a signature."""
import plistlib
import hashlib
import json
import struct
import sys
from pathlib import Path
from zipfile import ZipFile


def check(path):
    with ZipFile(path) as archive:
        assert archive.testzip() is None, "Corrupt IPA archive"
        names = set(archive.namelist())
        app = "Payload/SlowRun.app/"
        widget = app + "PlugIns/SlowRunLiveActivity.appex/"
        for name in (app + "SlowRun", app + "Info.plist", widget + "SlowRunLiveActivity", widget + "Info.plist"):
            assert name in names, "Missing IPA file: " + name
        for name in (app + "SlowRun", widget + "SlowRunLiveActivity"):
            magic, cpu = struct.unpack("<II", archive.read(name)[:8])
            assert magic == 0xFEEDFACF and cpu == 0x0100000C, "Expected an arm64 device executable"
        assert not any(name.endswith((".debug.dylib", "/__preview.dylib")) for name in names), "Development preview libraries must be disabled for the sideload package"
        info = plistlib.loads(archive.read(app + "Info.plist"))
        extension = plistlib.loads(archive.read(widget + "Info.plist"))
        assert "iPhoneOS" in info.get("CFBundleSupportedPlatforms", []), "Simulator app cannot be installed on iPhone"
        assert extension["CFBundleIdentifier"].startswith(info["CFBundleIdentifier"] + ".")
        assert info.get("NSSupportsLiveActivities") is True
        assert extension["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
        assert Path(info["CFBundleExecutable"]).name == "SlowRun"
        assert Path(extension["CFBundleExecutable"]).name == "SlowRunLiveActivity"
        manifest = json.loads(archive.read(app + "VoicePack/manifest.json"))
        assert manifest["voice"] == "zh-CN-XiaoxiaoNeural"
        assert set(manifest["clips"]) == {"warmup", "run", "walk", "cooldown", "tooFast", "slowing", "coaching", "finished", "freeRunStarted"}
        for key, clip in manifest["clips"].items():
            audio = archive.read(app + "VoicePack/" + key + ".mp3")
            assert hashlib.sha256(audio).hexdigest() == clip["sha256"], "Missing/corrupt offline recording: " + key
        numbers = json.loads(archive.read(app + "VoicePack/numbers/manifest.json"))
        from prepare_number_voice_pack import texts
        assert numbers["voice"] == "zh-CN-XiaoxiaoNeural"
        assert set(numbers["clips"]) == set(texts())
        for key, text in texts().items():
            clip = numbers["clips"][key]
            audio = archive.read(app + "VoicePack/numbers/" + key + ".wav")
            assert clip["text"] == text and hashlib.sha256(audio).hexdigest() == clip["sha256"]
            assert audio[:4] == b"RIFF" and struct.unpack_from("<I", audio, 24)[0] == 24000
        print(f"PASS: {Path(path).name}; physical iPhone platform, app and Lock Screen extension present.")
        print("PASS: 9 offline Microsoft audio files are embedded and their hashes match.")
        print(f"PASS: {len(numbers['clips'])} Microsoft number/phrase recordings are embedded and match.")
        print("Unsigned package: local Apple-account signing and device installation are still required.")


if __name__ == "__main__":
    check(sys.argv[1])
