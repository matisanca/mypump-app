#!/bin/zsh
# La matriz de emuladores de Android para probar la nativa sin un teléfono (Mati, 14-oct: «prefiero que busques la
# forma de simularlo desde la mac»). Todos con Google Play (FCM de verdad; Health Connect desde Play en 9-13) y con la
# misma memoria que nativa36. Crea solo los que faltan; no toca nativa36 ni nativa36b.
#
#   nativa28  Android 9   teléfono chico (720x1280)      Health Connect como app aparte (desde Play), la más vieja que lo soporta
#   nativa30  Android 11  pixel 4a                         Health Connect como app aparte (se instala desde Play)
#   nativa33  Android 13  pixel 6                          ídem, y el permiso de notificaciones por primera vez
#   nativa34  Android 14  pixel 8 pro (pantalla grande)    Health Connect integrado
#   nativa35  Android 15  tablet (2560x1600)               Health Connect integrado
#
# Uso: scripts/nativa/crear-emuladores.sh   (las imágenes, con `sdkmanager --sdk_root=~/Library/Android/sdk --install "system-images;android-NN;google_apis_playstore;arm64-v8a"`)
set -e
# avdmanager de Homebrew busca las imágenes en SU carpeta (no en ~/Library/Android/sdk, donde las deja
# `sdkmanager --sdk_root`): el AVD se arma a mano, con la config de nativa36 y la imagen y la pantalla de cada uno.
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
AVD=$HOME/.android/avd
# api  pantalla (ancho alto densidad)  equipo
filas=(
  "28 720 1280 320 teléfono chico"
  "30 1080 2340 440 pixel 4a"
  "33 1080 2400 420 pixel 6"
  "34 1344 2992 480 pixel 8 pro"
  "35 2560 1600 320 tablet"
)
for f in $filas; do
  set -- ${=f}
  api=$1; ancho=$2; alto=$3; dpi=$4; shift 4; equipo="$*"
  nombre=nativa$api
  if [ -d $AVD/$nombre.avd ]; then echo "· $nombre ya existe"; continue; fi
  sysdir="system-images/android-$api/google_apis_playstore/arm64-v8a/"
  if [ ! -f $SDK/$sysdir/system.img ]; then
    echo "✗ falta la imagen de $nombre: sdkmanager --sdk_root=$SDK --install \"system-images;android-$api;google_apis_playstore;arm64-v8a\""; continue
  fi
  mkdir -p $AVD/$nombre.avd
  cat > $AVD/$nombre.ini <<INI
avd.ini.encoding=UTF-8
path=$AVD/$nombre.avd
path.rel=avd/$nombre.avd
target=android-$api
INI
  cat > $AVD/$nombre.avd/config.ini <<CFG
AvdId=$nombre
PlayStore.enabled=true
abi.type=arm64-v8a
avd.ini.displayname=$nombre
avd.ini.encoding=UTF-8
disk.dataPartition.size=6G
hw.cpu.arch=arm64
hw.cpu.ncore=2
hw.lcd.density=$dpi
hw.lcd.height=$alto
hw.lcd.width=$ancho
hw.ramSize=2048
hw.keyboard=yes
hw.gpu.enabled=yes
hw.gpu.mode=auto
image.sysdir.1=$sysdir
tag.display=Google Play
tag.id=google_apis_playstore
CFG
  echo "✓ $nombre: Android $api, ${ancho}x${alto} @${dpi} ($equipo)"
done
