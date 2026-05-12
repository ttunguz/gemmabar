# GemmaBar signing

GemmaBar should not be distributed or repeatedly installed with the default ad-hoc signature. It asks for Accessibility permission and posts synthetic paste events, so macOS TCC works best when each rebuild has the same bundle identifier and a stable certificate-backed designated requirement.

## Local permanent signing

This machine already has valid code-signing identities named `GemmaBar Signing`:

```sh
security find-identity -v -p codesigning
```

Build the bundle with that identity. Because this keychain currently has two identities with the same name, prefer the SHA-1 hash from `security find-identity`:

```sh
SIGN_IDENTITY=392694E99447A713A4C51543CD52432E5F345811 ./scripts/build_gemmabar_bundle.sh
```

Then install the resulting app from:

```text
.build/GemmaBar-bundled/GemmaBar.app
```

Use the same signing certificate for future builds. Recreating the certificate changes the app's designated requirement and can make macOS ask for Accessibility and microphone permissions again. The current local certificate expires on May 11, 2027, so replace it deliberately before then rather than generating throwaway certificates per build.

## Developer ID distribution

For a public build, use an Apple Developer ID Application certificate and notarize the archive:

```sh
SIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" ./scripts/build_gemmabar_bundle.sh
ditto -c -k --keepParent .build/GemmaBar-bundled/GemmaBar.app .build/GemmaBar.zip
xcrun notarytool submit .build/GemmaBar.zip --keychain-profile AC_PASSWORD --wait
xcrun stapler staple .build/GemmaBar-bundled/GemmaBar.app
spctl --assess --type execute --verbose=4 .build/GemmaBar-bundled/GemmaBar.app
```

The bundle script signs the nested `SwiftLM` helper first, then the main `GemmaBar` executable with microphone entitlement, then the `.app` bundle. It intentionally avoids `codesign --deep` so signing failures are visible instead of being masked.
