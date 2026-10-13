# Android build and installation

The Android workflow builds an installable release APK and an Android App Bundle (AAB) on every push to `main`.

## Download the APK

1. Open the repository's Actions tab.
2. Select the latest successful **Build Android APK** run.
3. Under Artifacts, download `inv-management-android` and extract it.
4. Install `app-release.apk` on the Android device. Android may ask you to allow installation from the browser/file manager you used.
5. Sign in with an existing app account.

## Required repository variables

In GitHub: Settings → Secrets and variables → Actions → Variables, define:

- `SUPABASE_URL`: the project URL for the dedicated inventory project.
- `SUPABASE_PUBLISHABLE_KEY`: the project's publishable key (or legacy anon key if the project still uses it).

These are client-side values, not service-role credentials. Never place a service-role or secret key in the app.

If either variable is absent, the APK can still build but will open the setup screen instead of connecting to Supabase.

## Important release note

The APK built by this workflow is suitable for direct installation/testing. A Play Store release additionally requires a protected Android upload/signing key, package ID review, app icon/splash assets, privacy policy, and a tested signed AAB. Never commit a keystore or passwords to the repository.
