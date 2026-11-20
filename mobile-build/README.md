# JDK 25 for Android and iOS (Embrace experiment)

This branch is the JDK source for the static libraries that Embrace's mobile experiment links into
GraalVM Native Image builds for Android and iOS. It is an experiment, not a release.

## What the branch contains

- **Base:** `openjdk/jdk25u` tag `jdk-25.0.5.0.3-ga`, the JDK release that GraalVM Community
  `25.5.5.0.3` is built on. The static libraries must come from the same JDK release as the GraalVM.
- **OpenJDK Mobile's build support:** the changes from `openjdk/mobile` for JDK 25
  (`c59e44a7a..73d1892dc`), carried onto the release tag. Differences from that diff:
  - `.jcheck/conf` is not changed (repository metadata only).
  - `make/autoconf/libraries.m4` has only the fontconfig change. jdk25u's X11 condition already
    includes `ENABLE_HEADLESS_ONLY`, and these builds use `--enable-headless-only`.
- **Our change:** `ProcessImpl_md.c` defines `_GNU_SOURCE`, because Android's C library declares
  `pipe2` only with it.

## Building

- `build-android.sh`: configure, `make static-libs` and the combined `libvmone.a` for Android arm64.
- `build-ios.sh`: the same for iOS arm64, with the Xcode and SDK versions used.

Both scripts also list the non-JDK objects that go into `libvmone.a`: GraalVM's own C support code and
4 objects from Gluon's static JDK archive.

## Licence

The JDK is licensed under GPL v2 with the Classpath Exception; see `LICENSE` at the repository root.
