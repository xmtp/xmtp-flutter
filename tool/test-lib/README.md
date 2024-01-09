# dynamic libraries for testing

These are the dynamic test libraries for `libxmtp_bindings_flutter`.

They are used during `flutter test` runs.

All of these artifacts are produced by `libxmtp/bindings_flutter/`.

During test runs (`env[FLUTTER_TEST]`) the `libxmtp` bindings attempt to load a dynamic library.

This library is based on the current platform (`libxmtp_bindings_flutter.so` for `linux`, `libxmtp_bindings_flutter.dylib` for `macos`, etc).

See `libxmtp/bindings_flutter/loader.dart` (using `dlopen()` during test runs).

### Continuous Integration Testing

So we need to make sure these dynamic libraries are available during test runs.
We do this by specifying the `LD_LIBRARY_PATH` in our github actions workflow.

See `xmtp-flutter/.github/workflows/test.yml` (arranging the `LD_LIBRARY_PATH`).

### Local Testing

For running on your local machine you can do something similar.

You can either specify the `LD_LIBRARY_PATH` (`linux`, `windows`) or `DYLD_LIBRARY_PATH` (`macos`) 
alongside your `flutter test` command:
```bash
[/xmtp-flutter] $ DYLD_LIBRARY_PATH=tool/test-lib/apple-darwin flutter test
```

Or you can copy the proper library to the project root (which is part of the search path):

```bash
[/xmtp-flutter] $ cp tool/test-lib/apple-darwin/libxmtp_bindings_flutter.dylib .
[/xmtp-flutter] $ flutter test
```
(This works nicely within `Android Studio` which executes `flutter test` from the project root.)

### App Builds

Note: we don't need to do any of this lib shuffling for app or example app builds. 

For each supported platform (`android`, `ios`) we have integrated the static libraries into the 
build systems so they are automatically linked.

See `libxmtp/bindings_flutter/android/CMakeLists.txt` (works w/ gradle, arranges `jniLibs`).

See `libxmtp/bindings_flutter/ios/xmtp_bindings_flutter.podspec` (works w/ cocoapods, arranges `XCFramework`).
