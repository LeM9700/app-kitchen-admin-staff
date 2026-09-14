# Android release signing

## What's in place

- `android/upload-keystore.jks` — RSA 2048, alias `upload`, valid 10000 days (until 2054).
  Generated locally, **never committed** (gitignored alongside `key.properties`).
- `android/key.properties` — store/key passwords + alias + relative path to the keystore.
  Also gitignored.
- `android/app/build.gradle.kts` — the `release` build type signs with the `upload` key when
  `key.properties` exists, and silently falls back to the debug key otherwise (so a fresh
  clone or CI job that only runs `flutter test` doesn't break).

## If you need the keystore on another machine (CI, another dev, a new laptop)

`key.properties` and `upload-keystore.jks` are local secrets — copy them out-of-band (password
manager / secure transfer), never through git. Once copied, `key.properties`'s `storeFile` path
is relative to `android/app/` (`../upload-keystore.jks`), so keep the keystore at
`android/upload-keystore.jks` relative to wherever you place `key.properties`, or switch to an
absolute path if that's inconvenient.

## If the keystore is lost

As long as the app has **never been uploaded to the Play Store**, just delete
`android/upload-keystore.jks` and regenerate (see command below) — no consequence.

**Once a release has been uploaded to Play Console**, losing this keystore is effectively
unrecoverable for that app listing: Google can't reissue it, and without Play App Signing
enrollment you'd be unable to publish any future update to the same listing. Back up
`upload-keystore.jks` + the two passwords in a password manager (not just this repo checkout)
before the first real Play Store upload.

## Regenerating the keystore

```bash
keytool -genkeypair -v \
  -keystore android/upload-keystore.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -storepass '<store password>' -keypass '<key password>' \
  -dname "CN=<name>, OU=<org unit>, O=<org>, L=<city>, ST=<state>, C=<country code>"
```

Then update `android/key.properties` accordingly.

## Still open before a real Play Store submission

- `applicationId` in `android/app/build.gradle.kts` is still the Flutter template default
  (`com.example.app_admin_staff`) — Play Console rejects the `com.example.*` namespace outright.
  Needs a real, unique application ID before any store upload (also touches
  `android/app/src/main/kotlin/**/MainActivity.kt` package path and any Firebase config tied to
  the package name, if added later).
- The DN used to generate the current certificate (`CN=App Admin Staff, O=Pizza SaaS, ...`) is a
  placeholder — cosmetic only (Play Console doesn't validate it), fine to leave as-is or
  regenerate with real org info before a public listing.
- Local `flutter doctor` Android toolchain check is currently broken/timing out on this dev
  machine — a real `flutter build apk --release` should be smoke-tested (here or in CI) before
  relying on this signing config for an actual release.
