#!/bin/bash
# JDK 25.0.5 static libraries for Android arm64, as built in WSL (Ubuntu) for the Embrace GraalVM 25
# Android experiment. Experiment only. Condensed from the scripts used on 17 to 19 Nov 2026.
#
# Toolchain: Android NDK 28.2.13676358 (clang), API level 28, boot and build JDK Temurin 25 (Linux x64),
#            GNU Make and Autoconf from Ubuntu.
# Source: this branch (jdk25u tag jdk-25.0.5.0.3-ga plus the commits on top).
# Note: the libraries used in the experiment so far were built from tag jdk-25.0.5-ga (25.0.5.0.2) with
# the same changes; a rebuild from this branch is pending.

set -e
SRC=${SRC:-$PWD}                      # this repository
NDK=${NDK:?set NDK to the Android NDK folder}
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64
BOOT=${BOOT:?set BOOT to a JDK 25 for Linux x64}   # a plain OpenJDK 25; GraalVM as boot JDK prints CDS
                                                   # messages that end up in generated sources
HDR=${HDR:?set HDR to a folder holding usr/include with cups, fontconfig, alsa and freetype headers}
API=28    # posix_spawn, nl_langinfo and iconv need API 28

cd "$SRC"
bash configure \
    --with-cups-include="$HDR/usr/include" \
    --with-fontconfig-include="$HDR/usr/include" \
    --with-alsa-include="$HDR/usr/include" \
    --with-alsa-lib="$HDR/usr/lib/x86_64-linux-gnu" \
    --with-conf-name=android-linux-aarch64 \
    --enable-headless-only \
    --with-boot-jdk="$BOOT" --with-build-jdk="$BOOT" \
    --with-toolchain-path="$TC/bin" --with-sysroot="$TC/sysroot" --with-toolchain-type=clang \
    --with-jvm-variants=minimal \
    --build=x86_64-unknown-linux-gnu --host=aarch64-linux-android --target=aarch64-linux-android \
    --with-version-opt=embrace-experiment \
    --with-extra-cflags="--target=aarch64-linux-android$API" \
    --with-extra-cxxflags="--target=aarch64-linux-android$API" \
    --with-extra-ldflags="--target=aarch64-linux-android$API" \
    --disable-warnings-as-errors
make CONF=android-linux-aarch64 static-libs
# Result: 24 static libraries under build/android-linux-aarch64/support/native/**.a

# ---- Post-build: combine into libvmone.a for Substrate (-Djavalibspath=<dir containing libvmone.a>)
W=${W:-$SRC/build/vmone}; OUT=$W/android-aarch64/lib
AR=$TC/bin/llvm-ar
rm -rf "$W/obj" "$OUT"; mkdir -p "$W/obj/jdk" "$W/obj/svm" "$W/obj/gluon" "$W/obj/fallback" "$OUT"
# 1. every object from every JDK static library, one folder per library so equal names do not collide
for a in $(find "$SRC/build/android-linux-aarch64/support/native" -name '*.a' | sort); do
    d="$W/obj/jdk/$(basename "$a" .a)"; mkdir -p "$d"; ( cd "$d" && "$AR" x "$a" )
done
# 2. GraalVM 25's own C support objects (libchelper, the JVM shim, libcontainer), compiled for Android
#    arm64 from oracle/graal tag vm-25.5.5.0.3 (SVM_CLIBS points at the compiled objects)
cp "$SVM_CLIBS"/libchelper/*.o "$SVM_CLIBS"/jvm/*.o "$SVM_CLIBS"/libcontainer/*.o "$W/obj/svm/"
# 3. four objects kept from Gluon's javaStaticSdk 24-2.1 android-aarch64 libvmone.a
( cd "$W/obj/gluon" && "$AR" x "$GLUON_VMONE" AccessController.o SecurityManager.o dummy.o debug.o )
# 4. fallback for JVM_GetManagement, which libmanagement references and GraalVM 25's JVM shim does not
#    define (Substrate defines it for iOS in ios/JvmFuncsFallbacks.c)
cat > "$W/obj/fallback/android_jvm_fallbacks.c" <<'EOC'
#include <stdio.h>
#include <stddef.h>
void* JVM_GetManagement(int version) {
    fputs("JVM_GetManagement called: unimplemented\n", stderr);
    return NULL;
}
EOC
"$TC/bin/aarch64-linux-android$API-clang" -c -fPIC -O2 -o "$W/obj/fallback/android_jvm_fallbacks.o" "$W/obj/fallback/android_jvm_fallbacks.c"
"$AR" rcs "$OUT/libvmone.a" $(find "$W/obj" -name '*.o' | sort)
