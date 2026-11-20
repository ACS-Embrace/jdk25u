#!/bin/bash
# JDK 25.0.5.0.3 static libraries for iOS arm64 (device), as built on the Mac on 17 Nov 2026
# for the Embrace GraalVM 25 iOS experiment. Experiment only.
#
# Toolchain: macOS 26 (Darwin 25.6), Xcode 27.2 (27B52), Apple clang 21.0.0, iPhoneOS 27.2 SDK,
#            GNU Make 3.81 (system), GNU Autoconf 2.73 (Homebrew), boot and build JDK Temurin 25.0.5+8.
#
# Source changes (see jdk25-ios-source.diff, a git diff against jdk25u tag jdk-25.0.5.0.3-ga):
#   - The OpenJDK Mobile build support (openjdk/mobile, c59e44a7a..73d1892dc), applied as the
#     Android-side port of it (jdk25.0.5-android-support.patch), plus one line added on the Mac:
#     the opening "#ifndef __IOS__" before "#include <sys/socket.h>" in
#     src/java.base/macosx/native/libjava/java_props_macosx.c. With that line the file matches
#     openjdk/mobile 73d1892dc exactly.
#   - Differences from the openjdk/mobile 73d1892dc diff, file by file:
#       .jcheck/conf (project=mobile): not applied; repository metadata only.
#       make/autoconf/libraries.m4: only the fontconfig hunk (adds xios). The mobile X11 hunk
#         (adds xandroid and xios) is not applied, because jdk25u already has a different X11
#         condition (it includes ENABLE_HEADLESS_ONLY) and this build uses --enable-headless-only.
#       src/java.base/unix/native/libjava/ProcessImpl_md.c: extra, from the Android port
#         (#define _GNU_SOURCE so bionic declares pipe2). No effect on iOS.
#     All other 40 files have the same changed lines as the mobile diff.

set -e
SRC=$HOME/GraalVM25/jdk/src25ga          # git clone --depth 1 --branch jdk-25.0.5.0.3-ga https://github.com/openjdk/jdk25u.git
B=$HOME/GraalVM25/bootjdk/Contents/Home  # Temurin 25.0.5+8, macOS aarch64
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CUPS=$HOME/GraalVM25/cups-include        # cups/ headers copied from the macOS SDK (usr/include/cups); iOS has none

cd "$SRC"
git apply jdk25-ios-source.diff          # or: the mobile patch, then the java_props_macosx.c guard

bash configure --with-conf-name=ios-aarch64 --enable-headless-only \
  --with-boot-jdk=$B --with-build-jdk=$B \
  --openjdk-target=aarch64-macos-ios \
  --with-cups-include=$CUPS --with-sysroot=$SDK \
  --with-jvm-variants=minimal --disable-fallback-linker \
  --with-version-opt=embrace-experiment --disable-warnings-as-errors
# minimal variant and --disable-fallback-linker: the default zero variant and the fallback linker need
# libffi, which the iPhoneOS SDK lacks. The app is built with -H:-ForeignAPISupport.

make CONF=ios-aarch64 JOBS=4 static-libs
# Result: 24 static libraries under build/ios-aarch64/support/native/**.a, all objects platform iOS.

# ---- Post-build: combine into libvmone.a for Substrate (-Djavalibspath=<dir containing libvmone.a>)
W=$HOME/GraalVM25/vmone-ios; OUT=$W/ios-arm64/lib
mkdir -p $W/obj/jdk $W/obj/svm $W/obj/gluon $OUT
# 1. every object from every JDK static library
for a in $(find $SRC/build/ios-aarch64/support/native -name '*.a' | sort); do
  d=$W/obj/jdk/$(basename $a .a); mkdir -p $d; (cd $d && ar x $a)
done
# 2. GraalVM 25's own C support objects (libchelper, the JVM shim, the darwin Foundation helper),
#    compiled for iOS arm64 from oracle/graal tag vm-25.5.5.0.3 with svm-clibs-ios.sh (16 objects).
cp $HOME/GraalVM25/svm-clibs-ios/libchelper/*.o $HOME/GraalVM25/svm-clibs-ios/jvm/*.o $HOME/GraalVM25/svm-clibs-ios/darwin/*.o $W/obj/svm/
# 3. four objects kept from Gluon's javaStaticSdk 24-2.1 ios-arm64 libvmone.a:
#    AccessController.o SecurityManager.o dummy.o debug.o
#    (splashscreen_stubs.o is not needed: the new libjli.a defines the DoSplash* functions itself)
(cd $W/obj/gluon && ar x $HOME/.gluon/substrate/javaStaticSdk/24-2.1/ios-arm64/lib/libvmone.a AccessController.o SecurityManager.o dummy.o debug.o)
xcrun ar rcs $OUT/libvmone.a $(find $W/obj -name '*.o' | sort)
xcrun ranlib $OUT/libvmone.a
# Result: 253 members, thin arm64.
#
# Stubs: no JVM_GetManagement stub was added; Substrate's ios/JvmFuncsFallbacks.c already defines it.
# Substrate side (experiment/graalvm25, not part of the JDK): 4 abort-stubs removed because GraalVM 25
# now defines them itself (JVM_LoadLibrary, JVM_UnloadLibrary, JVM_IsSupportedJNIVersion in JvmFuncs.c;
# fprintfSD in libchelper varargs_helper.c), and ios/cap regenerated in the arm64 simulator.
