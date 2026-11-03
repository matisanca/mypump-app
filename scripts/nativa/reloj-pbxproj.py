#!/usr/bin/env python3
"""reloj-pbxproj.py — agrega al proyecto de iOS los targets del Apple Watch (tanda 3, 2.2), sin tocar los de siempre.

    python3 scripts/nativa/reloj-pbxproj.py            agrega MyPumpWatch (app watchOS) y MyPumpWatchComplicaciones
                                                     (extensión WidgetKit embebida en el reloj) y el esquema MyPumpWatch
    python3 scripts/nativa/reloj-pbxproj.py --revisar  solo dice si ya están
    python3 scripts/nativa/reloj-pbxproj.py --embeber  RECIÉN cuando existan el App ID y los perfiles del reloj: embebe
                                                     MyPumpWatch.app en MyPump.app (Watch/) y lo hace dependencia del
                                                     target MyPump (ver docs/NATIVA_TANDAS_2_A_4.md)

Es idempotente (si ya están, no hace nada) y con ids fijos (6B20…01xx), así el resultado es siempre el mismo.

Lo que NO hace, a propósito: no embebe el reloj en el target MyPump ni lo agrega al esquema MyPump (el que compila
codemagic.yaml con los tags nios-*). Hasta que exista el App ID del reloj y su perfil de firma, el reloj es un target
y un esquema aparte que compila y corre solo en el simulador. Los pasos para embeberlo están en
docs/NATIVA_TANDAS_2_A_4.md («Tanda 3: embeber el reloj»).
"""
import pathlib
import sys

RAIZ = pathlib.Path(__file__).resolve().parents[2]
PBX = RAIZ / "apps/ios/MyPump.xcodeproj/project.pbxproj"
ESQUEMA = RAIZ / "apps/ios/MyPump.xcodeproj/xcshareddata/xcschemes/MyPumpWatch.xcscheme"
MARCA = "6B2000000000000000000106 /* MyPumpWatch */"

W = {  # el reloj
    "app": "6B2000000000000000000101", "grupo": "6B2000000000000000000102", "fw": "6B2000000000000000000103",
    "src": "6B2000000000000000000104", "res": "6B2000000000000000000105", "target": "6B2000000000000000000106",
    "lista": "6B2000000000000000000107", "debug": "6B2000000000000000000108", "release": "6B2000000000000000000109",
    "prod": "6B200000000000000000010A", "bf": "6B200000000000000000010B", "plist": "6B200000000000000000010C",
    "ent": "6B200000000000000000010D", "embed": "6B200000000000000000010E", "bfext": "6B200000000000000000010F",
    "proxy": "6B2000000000000000000110", "dep": "6B2000000000000000000111",
}
C = {  # las complicaciones
    "app": "6B2000000000000000000121", "grupo": "6B2000000000000000000122", "fw": "6B2000000000000000000123",
    "src": "6B2000000000000000000124", "res": "6B2000000000000000000125", "target": "6B2000000000000000000126",
    "lista": "6B2000000000000000000127", "debug": "6B2000000000000000000128", "release": "6B2000000000000000000129",
    "prod": "6B200000000000000000012A", "bf": "6B200000000000000000012B", "plist": "6B200000000000000000012C",
    "ent": "6B200000000000000000012D",
}
PROYECTO = "6B2000000000000000000010"


def ajustes(t, nombre, bundle, plist, ent, extension):
    rpath = '"@executable_path/Frameworks",' + ('\n\t\t\t\t\t"@executable_path/../../Frameworks",' if extension else "")
    extra = "" if extension else (
        '\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown";\n'
        "\t\t\t\tINFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.pumpteam.mypump;\n"
        "\t\t\t\tINFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = NO;\n")
    bloques = []
    for clave, conf in (("debug", "Debug"), ("release", "Release")):
        bloques.append(f"""\t\t{t[clave]} /* {conf} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = {ent};
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = "{plist}";
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Pump Team";
{extra}\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t{rpath}
\t\t\t\t);
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {bundle};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchos watchsimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
\t\t\t}};
\t\t\tname = {conf};
\t\t}};
""")
    return "".join(bloques)


def fase(id_, isa, nombre, archivos=""):
    return f"""\t\t{id_} /* {nombre} */ = {{
\t\t\tisa = {isa};
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{archivos}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""


def insertar(texto, seccion, contenido):
    fin = f"/* End {seccion} section */"
    assert fin in texto, seccion
    return texto.replace(fin, contenido + fin, 1)


def en_lista(texto, ancla, nuevo):
    """Agrega `nuevo` al final de la lista `( … );` que sigue a `ancla`."""
    i = texto.index(ancla)
    j = texto.index(");", i)
    return texto[:j] + nuevo + texto[j:]


def aplicar(t):
    t = insertar(t, "PBXBuildFile",
                 f"\t\t{W['bf']} /* MyPumpKitReloj in Frameworks */ = {{isa = PBXBuildFile; productRef = {W['prod']} /* MyPumpKitReloj */; }};\n"
                 f"\t\t{W['bfext']} /* MyPumpWatchComplicaciones.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {C['app']} /* MyPumpWatchComplicaciones.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n"
                 f"\t\t{C['bf']} /* MyPumpKitReloj in Frameworks */ = {{isa = PBXBuildFile; productRef = {C['prod']} /* MyPumpKitReloj */; }};\n")
    t = insertar(t, "PBXFileReference",
                 f"\t\t{W['app']} /* MyPumpWatch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MyPumpWatch.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
                 f"\t\t{W['plist']} /* MyPumpWatch-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = \"MyPumpWatch-Info.plist\"; sourceTree = \"<group>\"; }};\n"
                 f"\t\t{W['ent']} /* MyPumpWatch.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = MyPumpWatch.entitlements; sourceTree = \"<group>\"; }};\n"
                 f"\t\t{C['app']} /* MyPumpWatchComplicaciones.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = MyPumpWatchComplicaciones.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
                 f"\t\t{C['plist']} /* MyPumpWatchComplicaciones-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = \"MyPumpWatchComplicaciones-Info.plist\"; sourceTree = \"<group>\"; }};\n"
                 f"\t\t{C['ent']} /* MyPumpWatchComplicaciones.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = MyPumpWatchComplicaciones.entitlements; sourceTree = \"<group>\"; }};\n")
    t = insertar(t, "PBXContainerItemProxy", f"""\t\t{W['proxy']} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROYECTO} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {C['target']};
\t\t\tremoteInfo = MyPumpWatchComplicaciones;
\t\t}};
""")
    t = insertar(t, "PBXCopyFilesBuildPhase", f"""\t\t{W['embed']} /* Embed Foundation Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{W['bfext']} /* MyPumpWatchComplicaciones.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""")
    t = insertar(t, "PBXFileSystemSynchronizedRootGroup",
                 f"\t\t{W['grupo']} /* MyPumpWatch */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = MyPumpWatch;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
                 f"\t\t{C['grupo']} /* MyPumpWatchComplicaciones */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = MyPumpWatchComplicaciones;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    t = insertar(t, "PBXFrameworksBuildPhase",
                 fase(W["fw"], "PBXFrameworksBuildPhase", "Frameworks", f"\t\t\t\t{W['bf']} /* MyPumpKitReloj in Frameworks */,\n")
                 + fase(C["fw"], "PBXFrameworksBuildPhase", "Frameworks", f"\t\t\t\t{C['bf']} /* MyPumpKitReloj in Frameworks */,\n"))
    # Los grupos: en el principal (después de Compartido) y los productos.
    t = t.replace("\t\t\t\t6B200000000000000000005E /* Compartido */,\n\t\t\t\t6B2000000000000000000005 /* Products */,",
                  "\t\t\t\t6B200000000000000000005E /* Compartido */,\n"
                  f"\t\t\t\t{W['plist']} /* MyPumpWatch-Info.plist */,\n\t\t\t\t{W['ent']} /* MyPumpWatch.entitlements */,\n"
                  f"\t\t\t\t{W['grupo']} /* MyPumpWatch */,\n"
                  f"\t\t\t\t{C['plist']} /* MyPumpWatchComplicaciones-Info.plist */,\n\t\t\t\t{C['ent']} /* MyPumpWatchComplicaciones.entitlements */,\n"
                  f"\t\t\t\t{C['grupo']} /* MyPumpWatchComplicaciones */,\n"
                  "\t\t\t\t6B2000000000000000000005 /* Products */,", 1)
    t = t.replace("\t\t\t\t6B2000000000000000000050 /* DescansoWidget.appex */,\n\t\t\t);\n\t\t\tname = Products;",
                  "\t\t\t\t6B2000000000000000000050 /* DescansoWidget.appex */,\n"
                  f"\t\t\t\t{W['app']} /* MyPumpWatch.app */,\n\t\t\t\t{C['app']} /* MyPumpWatchComplicaciones.appex */,\n"
                  "\t\t\t);\n\t\t\tname = Products;", 1)
    t = insertar(t, "PBXNativeTarget", f"""\t\t{W['target']} /* MyPumpWatch */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {W['lista']} /* Build configuration list for PBXNativeTarget "MyPumpWatch" */;
\t\t\tbuildPhases = (
\t\t\t\t{W['src']} /* Sources */,
\t\t\t\t{W['fw']} /* Frameworks */,
\t\t\t\t{W['res']} /* Resources */,
\t\t\t\t{W['embed']} /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{W['dep']} /* PBXTargetDependency */,
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{W['grupo']} /* MyPumpWatch */,
\t\t\t);
\t\t\tname = MyPumpWatch;
\t\t\tpackageProductDependencies = (
\t\t\t\t{W['prod']} /* MyPumpKitReloj */,
\t\t\t);
\t\t\tproductName = MyPumpWatch;
\t\t\tproductReference = {W['app']} /* MyPumpWatch.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{C['target']} /* MyPumpWatchComplicaciones */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {C['lista']} /* Build configuration list for PBXNativeTarget "MyPumpWatchComplicaciones" */;
\t\t\tbuildPhases = (
\t\t\t\t{C['src']} /* Sources */,
\t\t\t\t{C['fw']} /* Frameworks */,
\t\t\t\t{C['res']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{C['grupo']} /* MyPumpWatchComplicaciones */,
\t\t\t);
\t\t\tname = MyPumpWatchComplicaciones;
\t\t\tpackageProductDependencies = (
\t\t\t\t{C['prod']} /* MyPumpKitReloj */,
\t\t\t);
\t\t\tproductName = MyPumpWatchComplicaciones;
\t\t\tproductReference = {C['app']} /* MyPumpWatchComplicaciones.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};
""")
    t = t.replace("\t\t\t\t\t6B2000000000000000000052 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t};\n",
                  "\t\t\t\t\t6B2000000000000000000052 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t};\n"
                  f"\t\t\t\t\t{W['target']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t}};\n"
                  f"\t\t\t\t\t{C['target']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t}};\n", 1)
    t = t.replace("\t\t\t\t6B2000000000000000000052 /* DescansoWidget */,\n\t\t\t);\n\t\t};\n/* End PBXProject section */",
                  "\t\t\t\t6B2000000000000000000052 /* DescansoWidget */,\n"
                  f"\t\t\t\t{W['target']} /* MyPumpWatch */,\n\t\t\t\t{C['target']} /* MyPumpWatchComplicaciones */,\n"
                  "\t\t\t);\n\t\t};\n/* End PBXProject section */", 1)
    t = insertar(t, "PBXResourcesBuildPhase", fase(W["res"], "PBXResourcesBuildPhase", "Resources") + fase(C["res"], "PBXResourcesBuildPhase", "Resources"))
    t = insertar(t, "PBXSourcesBuildPhase", fase(W["src"], "PBXSourcesBuildPhase", "Sources") + fase(C["src"], "PBXSourcesBuildPhase", "Sources"))
    t = insertar(t, "PBXTargetDependency", f"""\t\t{W['dep']} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {C['target']} /* MyPumpWatchComplicaciones */;
\t\t\ttargetProxy = {W['proxy']} /* PBXContainerItemProxy */;
\t\t}};
""")
    t = insertar(t, "XCBuildConfiguration",
                 ajustes(W, "MyPumpWatch", "com.pumpteam.mypump.watchkitapp", "MyPumpWatch-Info.plist", "MyPumpWatch.entitlements", False)
                 + ajustes(C, "MyPumpWatchComplicaciones", "com.pumpteam.mypump.watchkitapp.complicaciones",
                           "MyPumpWatchComplicaciones-Info.plist", "MyPumpWatchComplicaciones.entitlements", True))
    for x, nombre in ((W, "MyPumpWatch"), (C, "MyPumpWatchComplicaciones")):
        t = insertar(t, "XCConfigurationList", f"""\t\t{x['lista']} /* Build configuration list for PBXNativeTarget "{nombre}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{x['debug']} /* Debug */,
\t\t\t\t{x['release']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
""")
    t = insertar(t, "XCSwiftPackageProductDependency",
                 f"\t\t{W['prod']} /* MyPumpKitReloj */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = MyPumpKitReloj;\n\t\t}};\n"
                 f"\t\t{C['prod']} /* MyPumpKitReloj */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = MyPumpKitReloj;\n\t\t}};\n")
    return t


E = {"bf": "6B2000000000000000000131", "fase": "6B2000000000000000000132", "proxy": "6B2000000000000000000133",
     "dep": "6B2000000000000000000134"}
MARCA_EMBEBIDO = f"{E['fase']} /* Embed Watch Content */"


def embeber(t):
    """El reloj dentro del iPhone: fase «Embed Watch Content» ($(CONTENTS_FOLDER_PATH)/Watch) y dependencia en MyPump."""
    t = insertar(t, "PBXBuildFile",
                 f"\t\t{E['bf']} /* MyPumpWatch.app in Embed Watch Content */ = {{isa = PBXBuildFile; fileRef = {W['app']} /* MyPumpWatch.app */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
    t = insertar(t, "PBXContainerItemProxy", f"""\t\t{E['proxy']} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROYECTO} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {W['target']};
\t\t\tremoteInfo = MyPumpWatch;
\t\t}};
""")
    t = insertar(t, "PBXCopyFilesBuildPhase", f"""\t\t{E['fase']} /* Embed Watch Content */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
\t\t\tdstSubfolderSpec = 16;
\t\t\tfiles = (
\t\t\t\t{E['bf']} /* MyPumpWatch.app in Embed Watch Content */,
\t\t\t);
\t\t\tname = "Embed Watch Content";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""")
    t = insertar(t, "PBXTargetDependency", f"""\t\t{E['dep']} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {W['target']} /* MyPumpWatch */;
\t\t\ttargetProxy = {E['proxy']} /* PBXContainerItemProxy */;
\t\t}};
""")
    t = t.replace("\t\t\t\t6B200000000000000000005A /* Embed Foundation Extensions */,\n\t\t\t);",
                  f"\t\t\t\t6B200000000000000000005A /* Embed Foundation Extensions */,\n\t\t\t\t{E['fase']} /* Embed Watch Content */,\n\t\t\t);", 1)
    t = t.replace("\t\t\t\t6B200000000000000000005C /* PBXTargetDependency */,\n\t\t\t);",
                  f"\t\t\t\t6B200000000000000000005C /* PBXTargetDependency */,\n\t\t\t\t{E['dep']} /* PBXTargetDependency */,\n\t\t\t);", 1)
    assert t.count(MARCA_EMBEBIDO) >= 2, "no se encontró la fase del target MyPump"
    return t


def referencia(id_, nombre, producto):
    return f"""            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{id_}"
               BuildableName = "{producto}"
               BlueprintName = "{nombre}"
               ReferencedContainer = "container:MyPump.xcodeproj">
            </BuildableReference>"""


def esquema():
    app = referencia(W["target"], "MyPumpWatch", "MyPumpWatch.app")
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!-- El reloj (tanda 3, 2.2): esquema aparte, solo simulador hasta que exista el App ID del reloj. NO lo usa
     codemagic.yaml (que compila el esquema MyPump). Generado por scripts/nativa/reloj-pbxproj.py. -->
<Scheme
   LastUpgradeVersion = "2600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
{app}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{app}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{app}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main():
    texto = PBX.read_text()
    ya = MARCA in texto
    if "--revisar" in sys.argv:
        print("el reloj ya está en el proyecto" if ya else "el reloj no está en el proyecto")
        return
    if not ya:
        nuevo = aplicar(texto)
        # El target MyPump no se toca: ni dependencia ni fase de copia del reloj.
        antes = texto[texto.index("6B2000000000000000000006 /* MyPump */ = {"):]
        despues = nuevo[nuevo.index("6B2000000000000000000006 /* MyPump */ = {"):]
        assert antes[:antes.index("};")] == despues[:despues.index("};")], "se tocó el target MyPump"
        PBX.write_text(nuevo)
        print("✓ targets MyPumpWatch y MyPumpWatchComplicaciones agregados")
    else:
        print("el reloj ya estaba en el proyecto")
    if "--embeber" in sys.argv:
        texto = PBX.read_text()
        if MARCA_EMBEBIDO in texto:
            print("el reloj ya estaba embebido")
        else:
            PBX.write_text(embeber(texto))
            print("✓ MyPumpWatch.app embebido en MyPump.app (Watch/)")
    if not ESQUEMA.exists():
        ESQUEMA.write_text(esquema())
        print("✓ esquema MyPumpWatch")


if __name__ == "__main__":
    main()
