"""Generate a self-contained Xcode project using only Python's standard library."""
from __future__ import annotations
import hashlib
import json
import plistlib
import struct
import zlib
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def emit(value, indent=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent + 1) + quote(str(key)) + " = " + emit(item, indent + 1) + ";\n" for key, item in value.items()) + "\t" * indent + "}"
    if isinstance(value, list):
        return "(" + ", ".join(emit(x, indent) for x in value) + ("," if value else "") + ")"
    if isinstance(value, int):
        return str(value)
    return quote(str(value))


def icon_png(path):
    width = 1024
    data = bytearray()
    a, b = (335, 625), (688, 400)
    vx, vy = b[0] - a[0], b[1] - a[1]
    for y in range(width):
        data.append(0)
        for x in range(width):
            ring = abs(((x - 512) ** 2 + (y - 512) ** 2) ** 0.5 - 285) < 17
            t = max(0, min(1, ((x - a[0]) * vx + (y - a[1]) * vy) / (vx * vx + vy * vy)))
            slash = (x - a[0] - t * vx) ** 2 + (y - a[1] - t * vy) ** 2 < 21 ** 2
            data.extend((245, 252, 249) if ring or slash else (8, 124, 121))
    def chunk(kind, content):
        return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind + content) & 0xFFFFFFFF)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, width, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(data)) + chunk(b"IEND", b""))


def generate():
    objects = {}
    def add(key, isa, **fields):
        value = identifier(key)
        objects[value] = {"isa": isa, **fields}
        return value
    resources = ROOT / "SlowRun/Resources"
    resources.mkdir(parents=True, exist_ok=True)
    app_icon = resources / "Assets.xcassets/AppIcon.appiconset"
    accent = resources / "Assets.xcassets/AccentColor.colorset"
    app_icon.mkdir(parents=True, exist_ok=True); accent.mkdir(parents=True, exist_ok=True)
    (resources / "Assets.xcassets/Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}), encoding="utf-8")
    # Preserve the selected illustrated asset across project regeneration.
    icon_name = next((name for name in ("KleeIconChibi.png", "KleeIcon.png") if (app_icon / name).is_file()), "AppIcon.png")
    (app_icon / "Contents.json").write_text(json.dumps({"images": [{"filename": icon_name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")
    if icon_name == "AppIcon.png" and not (app_icon / icon_name).exists():
        icon_png(app_icon / icon_name)
    (accent / "Contents.json").write_text(json.dumps({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"alpha": "1.000", "red": "0.659", "green": "0.937", "blue": "0.667"}}}], "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")
    common = {"CFBundleDevelopmentRegion": "zh_CN", "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)", "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)"}
    app_info = {**common, "CFBundleDisplayName": "慢慢跑", "CFBundlePackageType": "APPL", "LSRequiresIPhoneOS": True,
                "NSLocationWhenInUseUsageDescription": "仅在你开始训练后，记录跑步路线、距离和配速。锁屏后继续记录本次训练。",
                "NSMotionUsageDescription": "跑步时读取步数和步频，帮助你回看训练节奏。",
                "NSLocalNetworkUsageDescription": "仅当你配置了局域网个人语音服务时，连接该服务生成播报或复盘。",
                "NSSupportsLiveActivities": True, "UIBackgroundModes": ["location", "audio"],
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}, "UILaunchScreen": {},
                "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {}},
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "CFBundleURLTypes": [{"CFBundleURLName": "SlowRun", "CFBundleURLSchemes": ["slowrun"]}]}
    widget_info = {**common, "CFBundleDisplayName": "慢慢跑实时活动", "CFBundlePackageType": "XPC!", "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}
    (resources / "App-Info.plist").write_bytes(plistlib.dumps(app_info, sort_keys=False))
    (resources / "Widget-Info.plist").write_bytes(plistlib.dumps(widget_info, sort_keys=False))
    privacy = {"NSPrivacyTracking": False, "NSPrivacyAccessedAPITypes": [{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}]}
    (resources / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(privacy, sort_keys=False))

    app_sources = sorted((ROOT / "SlowRun/App").glob("*.swift")) + sorted((ROOT / "SlowRun/Views").glob("*.swift"))
    shared = ROOT / "SlowRun/Shared/RunActivityAttributes.swift"
    widget = ROOT / "SlowRun/LiveActivity/SlowRunLiveActivity.swift"
    source_refs = {}
    for file in app_sources + [shared, widget]:
        relative = file.relative_to(ROOT).as_posix()
        source_refs[relative] = add("file:" + relative, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
    asset_ref = add("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path="SlowRun/Resources/Assets.xcassets", sourceTree="SOURCE_ROOT")
    privacy_ref = add("privacy", "PBXFileReference", lastKnownFileType="text.xml", path="SlowRun/Resources/PrivacyInfo.xcprivacy", sourceTree="SOURCE_ROOT")
    voice_ref = add("voice-pack", "PBXFileReference", lastKnownFileType="folder", path="SlowRun/Resources/VoicePack", sourceTree="SOURCE_ROOT")
    info_refs = [add(name, "PBXFileReference", lastKnownFileType="text.plist.xml", path="SlowRun/Resources/" + name, sourceTree="SOURCE_ROOT") for name in ("App-Info.plist", "Widget-Info.plist")]
    app_product = add("app-product", "PBXFileReference", explicitFileType="wrapper.application", path="SlowRun.app", sourceTree="BUILT_PRODUCTS_DIR", includeInIndex=0)
    widget_product = add("widget-product", "PBXFileReference", explicitFileType="wrapper.app-extension", path="SlowRunLiveActivity.appex", sourceTree="BUILT_PRODUCTS_DIR", includeInIndex=0)
    package = add("core-package", "XCLocalSwiftPackageReference", relativePath="RunCore")
    core_dependency = add("core-product", "XCSwiftPackageProductDependency", package=package, productName="RunCore")
    core_build = add("core-framework", "PBXBuildFile", productRef=core_dependency)

    def sources_phase(name, paths):
        files = [add(name + ":build:" + p, "PBXBuildFile", fileRef=source_refs[p]) for p in paths]
        return add(name + ":sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)
    app_phase = sources_phase("app", [x.relative_to(ROOT).as_posix() for x in app_sources + [shared]])
    widget_phase = sources_phase("widget", [widget.relative_to(ROOT).as_posix(), shared.relative_to(ROOT).as_posix()])
    app_resources = add("app-resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[add("assets-build", "PBXBuildFile", fileRef=asset_ref), add("privacy-app-build", "PBXBuildFile", fileRef=privacy_ref), add("voice-pack-build", "PBXBuildFile", fileRef=voice_ref)], runOnlyForDeploymentPostprocessing=0)
    widget_resources = add("widget-resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[add("privacy-widget-build", "PBXBuildFile", fileRef=privacy_ref)], runOnlyForDeploymentPostprocessing=0)
    app_frameworks = add("app-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[core_build], runOnlyForDeploymentPostprocessing=0)
    widget_frameworks = add("widget-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    embed = add("embed-widget", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=[add("widget-embed-build", "PBXBuildFile", fileRef=widget_product, settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0)

    def configs(name, common_settings):
        identifiers = []
        for configuration in ("Debug", "Release"):
            settings = dict(common_settings)
            if configuration == "Debug":
                settings.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"]})
            else:
                settings.update({"SWIFT_OPTIMIZATION_LEVEL": "-O", "SWIFT_COMPILATION_MODE": "wholemodule"})
            identifiers.append(add(name + ":" + configuration, "XCBuildConfiguration", buildSettings=settings, name=configuration))
        return add(name + ":config-list", "XCConfigurationList", buildConfigurations=identifiers, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    base = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym"}
    project_configs = configs("project", base)
    target_base = {"CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "", "CURRENT_PROJECT_VERSION": "15", "MARKETING_VERSION": "0.3.0", "TARGETED_DEVICE_FAMILY": "1", "SUPPORTS_MACCATALYST": "NO", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "GENERATE_INFOPLIST_FILE": "NO", "SWIFT_EMIT_LOC_STRINGS": "YES"}
    app_configs = configs("app", {**target_base, "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.example.slowrun", "INFOPLIST_FILE": "SlowRun/Resources/App-Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"]})
    widget_configs = configs("widget", {**target_base, "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.example.slowrun.LiveActivity", "INFOPLIST_FILE": "SlowRun/Resources/Widget-Info.plist", "APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]})
    widget_target = add("widget-target", "PBXNativeTarget", buildConfigurationList=widget_configs, buildPhases=[widget_phase, widget_frameworks, widget_resources], buildRules=[], dependencies=[], name="SlowRunLiveActivity", productName="SlowRunLiveActivity", productReference=widget_product, productType="com.apple.product-type.app-extension")
    proxy = add("widget-proxy", "PBXContainerItemProxy", containerPortal=identifier("project"), proxyType=1, remoteGlobalIDString=widget_target, remoteInfo="SlowRunLiveActivity")
    dependency = add("widget-target-dependency", "PBXTargetDependency", target=widget_target, targetProxy=proxy)
    app_target = add("app-target", "PBXNativeTarget", buildConfigurationList=app_configs, buildPhases=[app_phase, app_frameworks, app_resources, embed], buildRules=[], dependencies=[dependency], name="SlowRun", packageProductDependencies=[core_dependency], productName="SlowRun", productReference=app_product, productType="com.apple.product-type.application")
    products = add("products-group", "PBXGroup", children=[app_product, widget_product], name="Products", sourceTree="<group>")
    source_group = add("sources-group", "PBXGroup", children=list(source_refs.values()), name="Swift Sources", sourceTree="<group>")
    resources_group = add("resources-group", "PBXGroup", children=[asset_ref, privacy_ref, voice_ref] + info_refs, name="Resources", sourceTree="<group>")
    main_group = add("main-group", "PBXGroup", children=[source_group, resources_group, products], sourceTree="<group>")
    project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastSwiftUpdateCheck": "1600", "LastUpgradeCheck": "1600", "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "16.0", "SystemCapabilities": {"com.apple.BackgroundModes": {"enabled": 1}}}, widget_target: {"CreatedOnToolsVersion": "16.0"}}}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="zh_CN", hasScannedForEncodings=0, knownRegions=["zh_CN", "en", "Base"], mainGroup=main_group, packageReferences=[package], productRefGroup=products, projectDirPath="", projectRoot="", targets=[app_target, widget_target])
    content = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
    project_dir = ROOT / "SlowRun.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    (project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + emit(content) + "\n", encoding="utf-8")
    workspace = project_dir / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"/></Workspace>', encoding="utf-8")
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
    attrs = dict(BuildableIdentifier="primary", BlueprintIdentifier=app_target, BuildableName="SlowRun.app", BlueprintName="SlowRun", ReferencedContainer="container:SlowRun.xcodeproj")
    ET.SubElement(entry, "BuildableReference", attrs)
    test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    ET.SubElement(test, "Testables")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
    runnable = ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0")
    ET.SubElement(runnable, "BuildableReference", attrs)
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    ET.SubElement(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "BuildableReference", attrs)
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    scheme_dir = project_dir / "xcshareddata/xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    ET.indent(scheme, space="  ")
    ET.ElementTree(scheme).write(scheme_dir / "SlowRun.xcscheme", encoding="utf-8", xml_declaration=True)
    print(f"Generated {project_dir.name}: {len(app_sources) + 1} app Swift files, 2 widget Swift files, local RunCore package.")


if __name__ == "__main__":
    generate()
