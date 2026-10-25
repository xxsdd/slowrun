"""Check Xcode project integrity. This is NOT a Swift compiler or iPhone test."""
import json
import plistlib
import re
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def parse_pbx(text):
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text)
    index = 0
    def value():
        nonlocal index
        token = tokens[index]; index += 1
        if token == "{":
            result = {}
            while tokens[index] != "}":
                key = value()
                assert tokens[index] == "="; index += 1
                result[key] = value()
                assert tokens[index] == ";"; index += 1
            index += 1
            return result
        if token == "(":
            result = []
            while tokens[index] != ")":
                result.append(value())
                if tokens[index] == ",": index += 1
            index += 1
            return result
        return json.loads(token) if token.startswith('"') else token
    result = value()
    assert index == len(tokens), "Unparsed project tokens"
    return result


def main():
    project = parse_pbx((ROOT / "SlowRun.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
    objects = project["objects"]
    assert project["rootObject"] in objects
    def references(value):
        if isinstance(value, dict):
            for child in value.values(): yield from references(child)
        elif isinstance(value, list):
            for child in value: yield from references(child)
        elif isinstance(value, str) and re.fullmatch(r"[A-F0-9]{24}", value): yield value
    assert all(ref in objects for ref in references(project)), "Unresolved project object reference"
    for item in objects.values():
        if item["isa"] == "PBXFileReference" and item["sourceTree"] == "SOURCE_ROOT":
            assert (ROOT / item["path"]).exists(), "Missing file: " + item["path"]
    targets = [x for x in objects.values() if x["isa"] == "PBXNativeTarget"]
    assert {x["name"] for x in targets} == {"SlowRun", "SlowRunLiveActivity"}
    app = next(x for x in targets if x["name"] == "SlowRun")
    widget = next(x for x in targets if x["name"] == "SlowRunLiveActivity")
    assert any(objects[x]["isa"] == "PBXCopyFilesBuildPhase" for x in app["buildPhases"]), "Widget is not embedded"
    assert app["dependencies"], "Widget target dependency missing"
    for target in (app, widget):
        phases = [objects[x] for x in target["buildPhases"]]
        sources = next(x for x in phases if x["isa"] == "PBXSourcesBuildPhase")
        files = [objects[objects[x]["fileRef"]]["path"] for x in sources["files"]]
        assert "SlowRun/Shared/RunActivityAttributes.swift" in files
    for name in ("App-Info.plist", "Widget-Info.plist", "PrivacyInfo.xcprivacy"):
        plistlib.loads((ROOT / "SlowRun/Resources" / name).read_bytes())
    info = plistlib.loads((ROOT / "SlowRun/Resources/App-Info.plist").read_bytes())
    assert info["NSSupportsLiveActivities"] is True
    assert set(info["UIBackgroundModes"]) == {"location", "audio"}
    assert not info["NSAppTransportSecurity"].get("NSAllowsArbitraryLoads", False)
    ET.parse(ROOT / "SlowRun.xcodeproj/xcshareddata/xcschemes/SlowRun.xcscheme")
    for path in ROOT.glob("SlowRun/Resources/Assets.xcassets/**/Contents.json"):
        json.loads(path.read_text())
    assert (ROOT / "RunCore/Package.swift").is_file()
    print(f"PASS: {len(objects)} Xcode objects resolve; source files, targets, widget embedding, plists, assets and scheme checked.")
    print("NOT RUN: Swift compilation, XCTest, Xcode build, signing and iPhone execution.")


if __name__ == "__main__":
    main()
