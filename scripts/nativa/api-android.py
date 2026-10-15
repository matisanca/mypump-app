#!/usr/bin/env python3
"""Chequea que la app de Android no use APIs de Java o de Android más nuevas que su minSdk.

Las pruebas de :core corren en la JVM de la Mac (Java 21), que tiene todo: una llamada a algo de Android 13 pasa las
pruebas y cierra la app en Android 9. Pasó con `URLDecoder.decode(String, Charset)` (API 33) al abrir el link del coach
(lo encontró el emulador de Android 9 el 15-oct). Lint no mira los módulos JVM de :core.

Lee los .class (javap) de los jars de :core y busca cada referencia a java/*, javax/*, android/* y org/json en el
api-versions.xml del SDK: lo que es de una versión mayor al minSdk es un error. :app no se mira acá: ahí puede haber un
`if (Build.VERSION.SDK_INT >= …)` que el bytecode no muestra, y lo vigila lint (NewApi es fatal en el release). Las
librerías (Kotlin, OkHttp, kotlinx) tampoco: soportan Android viejo por su cuenta.

Uso: scripts/nativa/api-android.py [minSdk]   (compila antes con Gradle, sin red)
"""
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
ANDROID = RAIZ / "apps" / "android"


def buscar_sdk():
    """El SDK de Android: ANDROID_HOME, ANDROID_SDK_ROOT (Codemagic) o el de la Mac."""
    candidatos = [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"), str(Path.home() / "Library/Android/sdk")]
    for c in candidatos:
        if c and list(Path(c).glob("platforms/android-*/data/api-versions.xml")):
            return Path(c)
    sys.exit("✗ no encontré api-versions.xml en ningún SDK: " + ", ".join(str(c) for c in candidatos if c))


def buscar_java():
    """Un JDK con javap: JAVA_HOME si existe, el que da java_home (macOS), el de Homebrew o el del PATH. En Codemagic
    JAVA_HOME puede no estar y el de Homebrew no existe: con eso el primer intento falló en 5 segundos (15-oct)."""
    candidatos = [os.environ.get("JAVA_HOME")]
    for args in (["/usr/libexec/java_home", "-v", "21"], ["/usr/libexec/java_home"]):
        try:
            candidatos.append(subprocess.run(args, capture_output=True, text=True).stdout.strip())
        except OSError:
            pass
    candidatos.append("/opt/homebrew/opt/openjdk@21")
    for c in candidatos:
        if c and (Path(c) / "bin" / "javap").exists():
            return c
    javap = shutil.which("javap")
    if javap:
        return str(Path(javap).resolve().parent.parent)
    sys.exit("✗ no encontré javap (probé " + ", ".join(c for c in candidatos if c) + " y el PATH)")


SDK = buscar_sdk()
JAVA_HOME = buscar_java()
PREFIJOS = ("java/", "javax/", "android/", "org/json/")
REF = re.compile(r"// (Method|InterfaceMethod|Field|class) ([\w/$]+)(?:\.(\"?[\w$<>]+\"?):(\S+))?")


def version(texto, defecto=0.0):
    """«36», «36.1» (las versiones menores desde Android 16) o «36:1» como número: 36.0, 36.1. Un SDK con una plataforma
    menor trae «since="36.1"» y un int() ahí rompía el chequeo."""
    m = re.match(r"(\d+)(?:[.:](\d+))?", str(texto or ""))
    return float(f"{m.group(1)}.{m.group(2) or 0}") if m else defecto


def cargar_apis():
    """{clase: (since, padres, {metodo: since}, {campo: since})} del api-versions.xml más nuevo del SDK."""
    plataformas = sorted(SDK.glob("platforms/android-*/data/api-versions.xml"),
                         key=lambda p: version(p.parts[-3].removeprefix("android-")))
    if not plataformas:
        sys.exit("✗ no encontré api-versions.xml en el SDK")
    print(f"api-versions de {plataformas[-1].parts[-3]}")
    apis = {}
    for c in ET.parse(plataformas[-1]).getroot().iter("class"):
        since = version(c.get("since"), 1.0)
        padres = [e.get("name") for e in c if e.tag in ("extends", "implements")]
        metodos = {m.get("name"): version(m.get("since"), since) for m in c.iter("method")}
        campos = {f.get("name"): version(f.get("since"), since) for f in c.iter("field")}
        apis[c.get("name")] = (since, padres, metodos, campos)
    return apis


def since_de(apis, clase, miembro, tipo, vistos=None):
    """La versión desde la que existe el miembro, buscando también en las clases e interfaces padre."""
    vistos = vistos or set()
    if clase not in apis or clase in vistos:
        return None
    vistos.add(clase)
    since_clase, padres, metodos, campos = apis[clase]
    tabla = campos if tipo == "Field" else metodos
    if miembro in tabla:
        return tabla[miembro]
    for p in padres:
        s = since_de(apis, p, miembro, tipo, vistos)
        if s is not None:
            return s
    return None


def clases(origen):
    """(classpath, [nombres]) de un jar o de una carpeta de .class."""
    if origen.suffix == ".jar":
        with zipfile.ZipFile(origen) as z:
            nombres = [n[:-6].replace("/", ".") for n in z.namelist() if n.endswith(".class") and not n.startswith("META-INF")]
    else:
        nombres = [str(p.relative_to(origen))[:-6].replace("/", ".") for p in origen.rglob("*.class")]
    return str(origen), nombres


def referencias(classpath, nombres):
    """(clase que usa, tipo, clase usada, miembro) de cada referencia en el bytecode."""
    javap = Path(JAVA_HOME) / "bin" / "javap"
    for i in range(0, len(nombres), 150):
        tanda = nombres[i:i + 150]
        salida = subprocess.run([str(javap), "-c", "-p", "-classpath", classpath, *tanda],
                                capture_output=True, text=True).stdout
        actual = None
        for linea in salida.splitlines():
            if linea.startswith("Compiled from") or not linea.strip():
                continue
            m = re.match(r"^(?:[\w ]+ )?(?:class|interface|enum) ([\w.$]+)", linea)
            if m and not linea.startswith(" "):
                actual = m.group(1)
                continue
            r = REF.search(linea)
            if r and r.group(2).startswith(PREFIJOS):
                tipo, clase, nombre, desc = r.groups()
                miembro = None
                if nombre:
                    nombre = nombre.strip('"')
                    miembro = nombre if tipo == "Field" else f"{nombre}{desc}"
                yield actual, tipo, clase, miembro


def main():
    min_sdk = int(sys.argv[1]) if len(sys.argv) > 1 else 26
    print(f"SDK {SDK} · JDK {JAVA_HOME}")
    env = dict(os.environ, JAVA_HOME=JAVA_HOME, ANDROID_HOME=str(SDK))
    r = subprocess.run(["./gradlew", "-q", ":core:modelos:jar", ":core:reglas:jar", ":core:datos:jar"],
                       cwd=ANDROID, env=env, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-3000:])
        sys.exit("✗ no compiló")
    origenes = sorted(ANDROID.glob("core/*/build/libs/*.jar"))
    if len(origenes) < 3:
        sys.exit(f"✗ faltan los jars de :core: {[str(o) for o in origenes]}")
    apis = cargar_apis()
    malos = {}
    total = 0
    for o in origenes:
        cp, nombres = clases(o)
        for usa, tipo, clase, miembro in referencias(cp, nombres):
            total += 1
            if miembro is None:
                s = apis.get(clase, (None,))[0]
            else:
                s = since_de(apis, clase, miembro, tipo)
            if s is not None and s > min_sdk:
                malos.setdefault((clase, miembro, s), set()).add(usa or "?")
    print(f"{total} referencias a java/android en {len(origenes)} orígenes; minSdk {min_sdk}")
    if not malos:
        print("✓ nada más nuevo que el minSdk")
        return 0
    for (clase, miembro, s), usos in sorted(malos.items(), key=lambda x: -x[0][2]):
        print(f"✗ API {s:g}: {clase}{'.' + miembro if miembro else ''}")
        for u in sorted(usos)[:5]:
            print(f"     usado en {u}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
