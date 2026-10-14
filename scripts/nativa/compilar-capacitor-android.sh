#!/bin/zsh
# La Capacitor de debug para las pruebas de la migración en el emulador, compilada desde android/ del repo SIN tocarlo:
# android/ (sin lo compilado), public/ y la config se copian a una carpeta aparte, y ahí corren `cap sync` y Gradle.
# Firma con la clave de debug de esta Mac (~/.android/debug.keystore), la misma que usa la nativa de debug: instalar una
# encima de la otra es un update real (mismo paquete, misma firma).
# Uso: scripts/nativa/compilar-capacitor-android.sh   → ~/Developer/nativa-evidencia/dd/cap-android/cap-main-debug.apk
set -e
RAIZ=${0:A:h}/../..
DD=~/Developer/nativa-evidencia/dd/cap-android
SRC=$DD/src
# Los node_modules de la Capacitor: los del repo, o los del clon principal (los worktrees no los tienen).
NM=${NODE_MODULES:-$RAIZ/node_modules}
[ -d $NM/@capacitor/android ] || NM=~/Developer/mypump-nativa/node_modules
[ -d $NM/@capacitor/android ] || { echo "✗ faltan los node_modules de la Capacitor (npm ci en el clon)"; exit 1 }
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}

rm -rf $SRC
mkdir -p $SRC
rsync -a --exclude build/ --exclude .gradle/ --exclude local.properties $RAIZ/android/ $SRC/android/
rsync -a $RAIZ/public/ $SRC/public/
cp $RAIZ/capacitor.config.json $RAIZ/package.json $SRC/
ln -s $NM $SRC/node_modules
( cd $SRC && npx --no-install cap sync android )
( cd $SRC/android && ./gradlew -q assembleDebug )
cp $SRC/android/app/build/outputs/apk/debug/app-debug.apk $DD/cap-main-debug.apk
echo "listo: $DD/cap-main-debug.apk"
