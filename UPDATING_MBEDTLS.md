# Updating mbedTLS

This document explains how to update the mbedTLS.xcframework to a newer version.

## Prerequisites

- Xcode Command Line Tools
- macOS development environment
- mbedTLS source code (from GitHub)

## Steps to Update

### 1. Download New mbedTLS Version

```bash
# Download from GitHub releases
wget https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/v3.x.x.tar.gz
tar -xzf v3.x.x.tar.gz
cd mbedtls-3.x.x
```

### 2. Enable EC-JPAKE Support

Edit `include/mbedtls/mbedtls_config.h` and ensure these are defined:

```c
#define MBEDTLS_ECJPAKE_C
#define MBEDTLS_KEY_EXCHANGE_ECJPAKE_ENABLED
```

### 3. Build for iOS Architectures

You need to build for:
- **iOS Device**: arm64
- **iOS Simulator**: arm64 + x86_64

Use the CMake toolchain files for iOS cross-compilation or Xcode build system.

**Key compiler flags needed:**
- `-DMBEDTLS_ECJPAKE_C`
- `-DMBEDTLS_KEY_EXCHANGE_ECJPAKE_ENABLED`

### 4. Create XCFramework

Once you have the static libraries built for each architecture:

```bash
xcodebuild -create-xcframework \
  -library build/ios-arm64/library/libmbedtls.a \
  -library build/ios-arm64/library/libmbedx509.a \
  -library build/ios-arm64/library/libmbedcrypto.a \
  -headers include \
  -library build/ios-simulator/library/libmbedtls.a \
  -library build/ios-simulator/library/libmbedx509.a \
  -library build/ios-simulator/library/libmbedcrypto.a \
  -headers include \
  -output mbedTLS.xcframework
```

Or combine all three libraries into one:

```bash
libtool -static -o libmbedtls-all.a libmbedtls.a libmbedx509.a libmbedcrypto.a
```

### 5. Replace in Package

```bash
cd /Users/philmargetson/Documents/Apps/ThreadCommissioner
rm -rf Frameworks/mbedTLS.xcframework
cp -R /path/to/new/mbedTLS.xcframework Frameworks/
```

### 6. Verify the Update

Build the package in an Xcode project to ensure it works:

1. Create a test iOS app in Xcode
2. Add the local package as a dependency
3. Build and verify no errors
4. Test Thread commissioning functionality

### 7. Commit Changes

```bash
git add Frameworks/mbedTLS.xcframework
git commit -m "Update mbedTLS to vX.X.X"
git tag vX.X.X
git push origin main --tags
```

## Current Version

- **mbedTLS Version**: 3.6.4
- **Built**: October 2024
- **Architectures**: arm64 (device), arm64 + x86_64 (simulator)
- **Features**: EC-JPAKE enabled, full TLS/DTLS support

## Notes

- The XCFramework includes all three mbedTLS libraries combined into `libmbedtls-all.a`
- Headers are included from the original mbedTLS distribution
- The `mbedtls_ssl_set_hs_ecjpake_password` function is declared in the umbrella header

## Build Script (TODO)

Consider creating an automated build script (`scripts/build-mbedtls.sh`) that:
1. Downloads specified mbedTLS version
2. Patches config for EC-JPAKE
3. Builds for all iOS architectures
4. Creates XCFramework
5. Replaces in package

## References

- [mbedTLS GitHub](https://github.com/Mbed-TLS/mbedtls)
- [mbedTLS Documentation](https://mbed-tls.readthedocs.io/)
- [iOS Cross-Compilation Guide](https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html)
