#!/usr/bin/env python3
"""Собирает MetroTimer.xcodeproj/project.pbxproj.

Списки файлов — константы ниже: добавил файл в проект → допиши сюда
и перезапусти. XcodeGen и Homebrew не нужны.
"""
import os

# Корень проекта — родитель папки Scripts: генератор переживает переезд.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SHARED = [
    "Shared/MetroActivityAttributes.swift",
    "Shared/Models.swift",
    "Shared/MetroRepository.swift",
    "Shared/TripPlanner.swift",
    "Shared/CalibrationStore.swift",
    "Shared/NotificationScheduler.swift",
    "Shared/ActivityController.swift",
    "Shared/TripEngine.swift",
    "Shared/AdjustTripIntent.swift",
    "Shared/Strings.swift",
    "Shared/Localization.swift",
    "Shared/TripLogStore.swift",
    "Shared/ColorHex.swift",
]
APP_SRC = [
    "App/MetroTimerApp.swift",
    "App/Views/ContentView.swift",
    "App/Views/TripView.swift",
    "App/Views/CalibrationView.swift",
    "App/Views/TripLogView.swift",
    "App/Views/AboutView.swift",
    "App/Services/MotionRecorder.swift",
    "App/Services/LocationRecorder.swift",
    "App/Services/CalibrationViewModel.swift",
    "App/Services/LocationCorrector.swift",
    "App/Services/NotificationPresenter.swift",
    "App/Services/AlertService.swift",
]
WIDGET_SRC = ["Widget/MetroActivityWidget.swift"]
APP_RES = ["App/Resources/kyiv_metro.json", "App/Resources/uk.lproj",
           "App/Resources/en.lproj", "App/Assets.xcassets", "App/PrivacyInfo.xcprivacy"]
# kyiv_metro.json нужен и виджету: MetroRepository компилируется в оба таргета
# (цепочка AdjustTripIntent → TripEngine), а его init падает fatalError без
# файла в бандле. 48 КБ — дешевле, чем крэш расширения в чужих руках.
WIDGET_RES = ["Widget/PrivacyInfo.xcprivacy", "App/Resources/kyiv_metro.json"]
TEST_SRC = ["Tests/PlannerTests.swift", "Tests/DataTests.swift", "Tests/ScheduleTests.swift",
            "Tests/LocalizationTests.swift"]
OTHER = ["App/Info.plist", "App/MetroTimer.entitlements", "Widget/Info.plist"]

for p in SHARED + APP_SRC + WIDGET_SRC + TEST_SRC + APP_RES + WIDGET_RES + OTHER:
    assert os.path.exists(os.path.join(ROOT, p)), f"missing {p}"

_counter = 0
def nid():
    global _counter
    _counter += 1
    return "AA%022X" % _counter

def ftype(path):
    if path.endswith(".lproj"): return "folder"
    if path.endswith(".swift"): return "sourcecode.swift"
    if path.endswith(".xcassets"): return "folder.assetcatalog"
    if path.endswith(".json"): return "text.json"
    if path.endswith(".entitlements"): return "text.plist.entitlements"
    if path.endswith(".plist"): return "text.plist.xml"
    if path.endswith(".yml"): return "text.yaml"
    if path.endswith(".xcprivacy"): return "text.xml"
    return "text"

# --- file references -------------------------------------------------------
# Один файл может входить в несколько таргетов (kyiv_metro.json — в приложение
# и в виджет). PBXFileReference на него всё равно один: два одинаковых объекта
# с одним UUID делают проект малформед-ным, и Xcode ругается на каждой сборке.
def unique(paths):
    seen, out = set(), []
    for path in paths:
        if path not in seen:
            seen.add(path)
            out.append(path)
    return out

ALL_FILES = unique(SHARED + APP_SRC + WIDGET_SRC + TEST_SRC + APP_RES + WIDGET_RES + OTHER)

fileref = {p: nid() for p in ALL_FILES}

app_product = nid()
widget_product = nid()
test_product = nid()

# --- build files -----------------------------------------------------------
bf_app_src = {p: nid() for p in APP_SRC + SHARED}
bf_app_res = {p: nid() for p in APP_RES}
bf_w_src = {p: nid() for p in WIDGET_SRC + SHARED}
bf_w_res = {p: nid() for p in WIDGET_RES}
bf_t_src = {p: nid() for p in TEST_SRC}
bf_embed = nid()

# --- groups ----------------------------------------------------------------
g_main, g_app, g_views, g_services, g_resources, g_shared, g_widget, g_tests, g_products = (
    nid(), nid(), nid(), nid(), nid(), nid(), nid(), nid(), nid())

# --- phases / targets / project -------------------------------------------
ph_app_sources, ph_app_res, ph_app_fw, ph_embed = nid(), nid(), nid(), nid()
ph_w_sources, ph_w_res, ph_w_fw = nid(), nid(), nid()
ph_t_sources, ph_t_fw = nid(), nid()
t_app, t_widget, t_tests = nid(), nid(), nid()
proj = nid()
dep_proxy, dep = nid(), nid()
test_dep_proxy, test_dep = nid(), nid()
cl_proj, cl_app, cl_widget, cl_tests = nid(), nid(), nid(), nid()
c_proj_d, c_proj_r, c_app_d, c_app_r, c_w_d, c_w_r, c_t_d, c_t_r = (nid() for _ in range(8))

def basename(p): return p.split("/")[-1]

L = []
add = L.append
add("// !$*UTF8*$!")
add("{")
add("\tarchiveVersion = 1;")
add("\tclasses = {\n\t};")
add("\tobjectVersion = 56;")
add("\tobjects = {")

add("\n/* Begin PBXBuildFile section */")
for p, i in sorted(bf_app_src.items()):
    add(f"\t\t{i} /* {basename(p)} in Sources */ = {{isa = PBXBuildFile; fileRef = {fileref[p]} /* {basename(p)} */; }};")
for p, i in sorted(bf_app_res.items()):
    add(f"\t\t{i} /* {basename(p)} in Resources */ = {{isa = PBXBuildFile; fileRef = {fileref[p]} /* {basename(p)} */; }};")
for p, i in sorted(bf_w_src.items()):
    add(f"\t\t{i} /* {basename(p)} in Sources */ = {{isa = PBXBuildFile; fileRef = {fileref[p]} /* {basename(p)} */; }};")
for p, i in sorted(bf_w_res.items()):
    add(f"\t\t{i} /* {basename(p)} in Resources */ = {{isa = PBXBuildFile; fileRef = {fileref[p]} /* {basename(p)} */; }};")
for p, i in sorted(bf_t_src.items()):
    add(f"\t\t{i} /* {basename(p)} in Sources */ = {{isa = PBXBuildFile; fileRef = {fileref[p]} /* {basename(p)} */; }};")
add(f"\t\t{bf_embed} /* MetroTimerWidget.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {widget_product} /* MetroTimerWidget.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
add("/* End PBXBuildFile section */")

add("\n/* Begin PBXContainerItemProxy section */")
add(f"\t\t{dep_proxy} /* PBXContainerItemProxy */ = {{")
add("\t\t\tisa = PBXContainerItemProxy;")
add(f"\t\t\tcontainerPortal = {proj} /* Project object */;")
add("\t\t\tproxyType = 1;")
add(f"\t\t\tremoteGlobalIDString = {t_widget};")
add("\t\t\tremoteInfo = MetroTimerWidget;")
add("\t\t};")
add(f"\t\t{test_dep_proxy} /* PBXContainerItemProxy */ = {{")
add("\t\t\tisa = PBXContainerItemProxy;")
add(f"\t\t\tcontainerPortal = {proj} /* Project object */;")
add("\t\t\tproxyType = 1;")
add(f"\t\t\tremoteGlobalIDString = {t_app};")
add("\t\t\tremoteInfo = MetroTimer;")
add("\t\t};")
add("/* End PBXContainerItemProxy section */")

add("\n/* Begin PBXCopyFilesBuildPhase section */")
add(f"\t\t{ph_embed} /* Embed Foundation Extensions */ = {{")
add("\t\t\tisa = PBXCopyFilesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add('\t\t\tdstPath = "";')
add("\t\t\tdstSubfolderSpec = 13;")
add("\t\t\tfiles = (")
add(f"\t\t\t\t{bf_embed} /* MetroTimerWidget.appex in Embed Foundation Extensions */,")
add("\t\t\t);")
add('\t\t\tname = "Embed Foundation Extensions";')
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXCopyFilesBuildPhase section */")

add("\n/* Begin PBXFileReference section */")
for p in ALL_FILES:
    add(f"\t\t{fileref[p]} /* {basename(p)} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype(p)}; path = {basename(p)}; sourceTree = \"<group>\"; }};")
add(f"\t\t{app_product} /* MetroTimer.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MetroTimer.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
add(f"\t\t{widget_product} /* MetroTimerWidget.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = MetroTimerWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
add(f"\t\t{test_product} /* MetroTimerTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MetroTimerTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
add("/* End PBXFileReference section */")

add("\n/* Begin PBXFrameworksBuildPhase section */")
for ph in (ph_app_fw, ph_w_fw):
    add(f"\t\t{ph} /* Frameworks */ = {{")
    add("\t\t\tisa = PBXFrameworksBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (\n\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
add(f"\t\t{ph_t_fw} /* Frameworks */ = {{")
add("\t\t\tisa = PBXFrameworksBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (\n\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXFrameworksBuildPhase section */")

def group(gid, name, children, path=None):
    add(f"\t\t{gid} /* {name} */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    for cid, cname in children:
        add(f"\t\t\t\t{cid} /* {cname} */,")
    add("\t\t\t);")
    if path:
        add(f"\t\t\tpath = {path};")
    elif name != "MainGroup":
        add(f"\t\t\tname = {name};")
    add('\t\t\tsourceTree = "<group>";')
    add("\t\t};")

add("\n/* Begin PBXGroup section */")
group(g_main, "MainGroup", [
    (g_app, "App"), (g_shared, "Shared"), (g_widget, "Widget"), (g_tests, "Tests"),
    (g_products, "Products"),
])
group(g_app, "App", [
    (fileref["App/MetroTimerApp.swift"], "MetroTimerApp.swift"),
    (fileref["App/Info.plist"], "Info.plist"),
    (fileref["App/MetroTimer.entitlements"], "MetroTimer.entitlements"),
    (fileref["App/Assets.xcassets"], "Assets.xcassets"),
    (fileref["App/PrivacyInfo.xcprivacy"], "PrivacyInfo.xcprivacy"),
    (g_views, "Views"), (g_services, "Services"), (g_resources, "Resources"),
], path="App")
group(g_views, "Views", [(fileref[p], basename(p)) for p in APP_SRC if "/Views/" in p], path="Views")
group(g_services, "Services", [(fileref[p], basename(p)) for p in APP_SRC if "/Services/" in p], path="Services")
group(g_resources, "Resources", [(fileref[p], basename(p)) for p in APP_RES if "/Resources/" in p], path="Resources")
group(g_shared, "Shared", [(fileref[p], basename(p)) for p in SHARED], path="Shared")
group(g_widget, "Widget", [
    (fileref["Widget/MetroActivityWidget.swift"], "MetroActivityWidget.swift"),
    (fileref["Widget/Info.plist"], "Info.plist"),
    (fileref["Widget/PrivacyInfo.xcprivacy"], "PrivacyInfo.xcprivacy"),
], path="Widget")
group(g_tests, "Tests", [(fileref[p], basename(p)) for p in TEST_SRC], path="Tests")
group(g_products, "Products", [(app_product, "MetroTimer.app"), (widget_product, "MetroTimerWidget.appex"),
                               (test_product, "MetroTimerTests.xctest")])
add("/* End PBXGroup section */")

add("\n/* Begin PBXNativeTarget section */")
add(f"\t\t{t_app} /* MetroTimer */ = {{")
add("\t\t\tisa = PBXNativeTarget;")
add(f"\t\t\tbuildConfigurationList = {cl_app} /* Build configuration list for PBXNativeTarget \"MetroTimer\" */;")
add("\t\t\tbuildPhases = (")
add(f"\t\t\t\t{ph_app_sources} /* Sources */,")
add(f"\t\t\t\t{ph_app_fw} /* Frameworks */,")
add(f"\t\t\t\t{ph_app_res} /* Resources */,")
add(f"\t\t\t\t{ph_embed} /* Embed Foundation Extensions */,")
add("\t\t\t);")
add("\t\t\tbuildRules = (\n\t\t\t);")
add("\t\t\tdependencies = (")
add(f"\t\t\t\t{dep} /* PBXTargetDependency */,")
add("\t\t\t);")
add("\t\t\tname = MetroTimer;")
add("\t\t\tproductName = MetroTimer;")
add(f"\t\t\tproductReference = {app_product} /* MetroTimer.app */;")
add('\t\t\tproductType = "com.apple.product-type.application";')
add("\t\t};")
add(f"\t\t{t_widget} /* MetroTimerWidget */ = {{")
add("\t\t\tisa = PBXNativeTarget;")
add(f"\t\t\tbuildConfigurationList = {cl_widget} /* Build configuration list for PBXNativeTarget \"MetroTimerWidget\" */;")
add("\t\t\tbuildPhases = (")
add(f"\t\t\t\t{ph_w_sources} /* Sources */,")
add(f"\t\t\t\t{ph_w_fw} /* Frameworks */,")
add(f"\t\t\t\t{ph_w_res} /* Resources */,")
add("\t\t\t);")
add("\t\t\tbuildRules = (\n\t\t\t);")
add("\t\t\tdependencies = (\n\t\t\t);")
add("\t\t\tname = MetroTimerWidget;")
add("\t\t\tproductName = MetroTimerWidget;")
add(f"\t\t\tproductReference = {widget_product} /* MetroTimerWidget.appex */;")
add('\t\t\tproductType = "com.apple.product-type.app-extension";')
add("\t\t};")
add(f"\t\t{t_tests} /* MetroTimerTests */ = {{")
add("\t\t\tisa = PBXNativeTarget;")
add(f"\t\t\tbuildConfigurationList = {cl_tests} /* Build configuration list for PBXNativeTarget \"MetroTimerTests\" */;")
add("\t\t\tbuildPhases = (")
add(f"\t\t\t\t{ph_t_sources} /* Sources */,")
add(f"\t\t\t\t{ph_t_fw} /* Frameworks */,")
add("\t\t\t);")
add("\t\t\tbuildRules = (\n\t\t\t);")
add("\t\t\tdependencies = (")
add(f"\t\t\t\t{test_dep} /* PBXTargetDependency */,")
add("\t\t\t);")
add("\t\t\tname = MetroTimerTests;")
add("\t\t\tproductName = MetroTimerTests;")
add(f"\t\t\tproductReference = {test_product} /* MetroTimerTests.xctest */;")
add('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
add("\t\t};")
add("/* End PBXNativeTarget section */")

add("\n/* Begin PBXProject section */")
add(f"\t\t{proj} /* Project object */ = {{")
add("\t\t\tisa = PBXProject;")
add("\t\t\tattributes = {")
add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
add("\t\t\t\tLastUpgradeCheck = 1500;")
add("\t\t\t};")
add(f"\t\t\tbuildConfigurationList = {cl_proj} /* Build configuration list for PBXProject \"MetroTimer\" */;")
add('\t\t\tcompatibilityVersion = "Xcode 14.0";')
add("\t\t\tdevelopmentRegion = uk;")
add("\t\t\thasScannedForEncodings = 0;")
add("\t\t\tknownRegions = (\n\t\t\t\tuk,\n\t\t\t\tBase,\n\t\t\t);")
add(f"\t\t\tmainGroup = {g_main};")
add(f"\t\t\tproductRefGroup = {g_products} /* Products */;")
add('\t\t\tprojectDirPath = "";')
add('\t\t\tprojectRoot = "";')
add("\t\t\ttargets = (")
add(f"\t\t\t\t{t_app} /* MetroTimer */,")
add(f"\t\t\t\t{t_widget} /* MetroTimerWidget */,")
add(f"\t\t\t\t{t_tests} /* MetroTimerTests */,")
add("\t\t\t);")
add("\t\t};")
add("/* End PBXProject section */")

add("\n/* Begin PBXResourcesBuildPhase section */")
add(f"\t\t{ph_app_res} /* Resources */ = {{")
add("\t\t\tisa = PBXResourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
for p, i in sorted(bf_app_res.items()):
    add(f"\t\t\t\t{i} /* {basename(p)} in Resources */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add(f"\t\t{ph_w_res} /* Resources */ = {{")
add("\t\t\tisa = PBXResourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
for p, i in sorted(bf_w_res.items()):
    add(f"\t\t\t\t{i} /* {basename(p)} in Resources */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXResourcesBuildPhase section */")

add("\n/* Begin PBXSourcesBuildPhase section */")
add(f"\t\t{ph_app_sources} /* Sources */ = {{")
add("\t\t\tisa = PBXSourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
for p, i in sorted(bf_app_src.items()):
    add(f"\t\t\t\t{i} /* {basename(p)} in Sources */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add(f"\t\t{ph_w_sources} /* Sources */ = {{")
add("\t\t\tisa = PBXSourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
for p, i in sorted(bf_w_src.items()):
    add(f"\t\t\t\t{i} /* {basename(p)} in Sources */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add(f"\t\t{ph_t_sources} /* Sources */ = {{")
add("\t\t\tisa = PBXSourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
for p, i in sorted(bf_t_src.items()):
    add(f"\t\t\t\t{i} /* {basename(p)} in Sources */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXSourcesBuildPhase section */")

add("\n/* Begin PBXTargetDependency section */")
add(f"\t\t{dep} /* PBXTargetDependency */ = {{")
add("\t\t\tisa = PBXTargetDependency;")
add(f"\t\t\ttarget = {t_widget} /* MetroTimerWidget */;")
add(f"\t\t\ttargetProxy = {dep_proxy} /* PBXContainerItemProxy */;")
add("\t\t};")
add(f"\t\t{test_dep} /* PBXTargetDependency */ = {{")
add("\t\t\tisa = PBXTargetDependency;")
add(f"\t\t\ttarget = {t_app} /* MetroTimer */;")
add(f"\t\t\ttargetProxy = {test_dep_proxy} /* PBXContainerItemProxy */;")
add("\t\t};")
add("/* End PBXTargetDependency section */")

COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "DEVELOPMENT_TEAM": "JC2G64UQ8N",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "COPY_PHASE_STRIP": "NO",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "16.1",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
DEBUG = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}
RELEASE = {
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
    "VALIDATE_PRODUCT": "YES",
}
# Платный аккаунт: MT_PAID_TEAM=1 python3 Scripts/gen_pbxproj.py
#
# Time Sensitive Notifications нельзя подписать бесплатным Personal Team.
# Без entitlement iOS молча понижает .timeSensitive до .active, и «Наступна —
# ваша» перестаёт пробивать «Не турбувати» / режими фокусування — то есть
# ровно в сценарии «дрімаю в метро», ради которого приложение и существует,
# уведомление не приходит. Поэтому переход на платный аккаунт обязан включать
# этот флаг; проверить в собранном бандле:
#   codesign -d --entitlements - build/.../MetroTimer.app
PAID_TEAM = os.environ.get("MT_PAID_TEAM") == "1"

APP = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "INFOPLIST_FILE": "App/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": '"Метро-таймер"',
    "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
    "PRODUCT_BUNDLE_IDENTIFIER": "ua.vlad.MetroTimer",
}
if PAID_TEAM:
    APP["CODE_SIGN_ENTITLEMENTS"] = "App/MetroTimer.entitlements"
TESTS = {
    "BUNDLE_LOADER": '"$(TEST_HOST)"',
    "GENERATE_INFOPLIST_FILE": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": "ua.vlad.MetroTimerTests",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    # Тесты грузятся в процесс приложения: Bundle.main = MetroTimer.app,
    # значит kyiv_metro.json на месте и MetroRepository работает как в бою.
    "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/MetroTimer.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MetroTimer"',
}
WIDGET = {
    "INFOPLIST_FILE": "Widget/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "MetroTimerWidget",
    "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
    "PRODUCT_BUNDLE_IDENTIFIER": "ua.vlad.MetroTimer.MetroTimerWidget",
    "SKIP_INSTALL": "YES",
}

def config(cid, name, *dicts):
    merged = {}
    for d in dicts:
        merged.update(d)
    add(f"\t\t{cid} /* {name} */ = {{")
    add("\t\t\tisa = XCBuildConfiguration;")
    add("\t\t\tbuildSettings = {")
    for k in sorted(merged):
        add(f"\t\t\t\t{k} = {merged[k]};")
    add("\t\t\t};")
    add(f"\t\t\tname = {name};")
    add("\t\t};")

add("\n/* Begin XCBuildConfiguration section */")
config(c_proj_d, "Debug", COMMON, DEBUG)
config(c_proj_r, "Release", COMMON, RELEASE)
config(c_app_d, "Debug", APP)
config(c_app_r, "Release", APP)
config(c_w_d, "Debug", WIDGET)
config(c_w_r, "Release", WIDGET)
config(c_t_d, "Debug", TESTS)
config(c_t_r, "Release", TESTS)
add("/* End XCBuildConfiguration section */")

add("\n/* Begin XCConfigurationList section */")
for cl, name, cd, cr in ((cl_proj, 'PBXProject "MetroTimer"', c_proj_d, c_proj_r),
                         (cl_app, 'PBXNativeTarget "MetroTimer"', c_app_d, c_app_r),
                         (cl_widget, 'PBXNativeTarget "MetroTimerWidget"', c_w_d, c_w_r),
                         (cl_tests, 'PBXNativeTarget "MetroTimerTests"', c_t_d, c_t_r)):
    add(f"\t\t{cl} /* Build configuration list for {name} */ = {{")
    add("\t\t\tisa = XCConfigurationList;")
    add("\t\t\tbuildConfigurations = (")
    add(f"\t\t\t\t{cd} /* Debug */,")
    add(f"\t\t\t\t{cr} /* Release */,")
    add("\t\t\t);")
    add("\t\t\tdefaultConfigurationIsVisible = 0;")
    add("\t\t\tdefaultConfigurationName = Release;")
    add("\t\t};")
add("/* End XCConfigurationList section */")

add("\t};")
add(f"\trootObject = {proj} /* Project object */;")
add("}")

import collections
import re as _re

_text = "\n".join(L)
_ids = _re.findall(r"^\t\t(AA[0-9A-F]{22}) /\*.*?\*/ = \{", _text, _re.M)
_dupes = sorted(k for k, n in collections.Counter(_ids).items() if n > 1)
assert not _dupes, f"один UUID определён дважды — проект малформед: {_dupes}"

out_dir = os.path.join(ROOT, "MetroTimer.xcodeproj")
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "project.pbxproj"), "w", encoding="utf-8") as f:
    f.write("\n".join(L) + "\n")
print("written", os.path.join(out_dir, "project.pbxproj"))
