# Password reset setup

The app sends reset emails through Supabase, opens the recovery link in the app,
and lets the customer save a new password. New passwords require at least 8
characters; existing accounts can still sign in with their current password.

## Supabase project settings

These dashboard settings are separate from the app source. They have not been
changed or verified by the local implementation.

1. Open **Authentication > URL Configuration** for this app's Supabase project.
   Add this exact entry to **Redirect URLs**, preserving existing entries:

   ```text
   com.repairshop101://auth/reset-password
   ```

   Android and iOS now register this scheme. Supabase's link handler handles
   the callback and the router shows the new-password screen after a verified
   recovery event. Rebuild/reinstall the app for native link changes to apply.

2. For a web build, also allow its exact reset URL, for example
   `https://your-domain.example/#/reset-password` (or
   `https://your-domain.example/app/#/reset-password` for a subdirectory).
   Local web development needs the matching origin and port. Set the Site URL
   to your actual deployment URL. The application preserves its web base path.
   See [Supabase redirect configuration](https://supabase.com/docs/guides/auth/redirect-urls).

3. In **Authentication > Email Templates > Reset Password**, keep the reset
   button linked to `{{ .ConfirmationURL }}`. A link to only the Site URL or
   RedirectTo does not verify the recovery token. Do not include tokens in logs.

4. In the email/password provider settings, set **Minimum password length** to
   **8** so the server also enforces the app's rule. Keep any existing stronger
   project security settings. See
   [Supabase password security](https://supabase.com/docs/guides/auth/password-security).

5. Configure **custom SMTP** to deliver messages to customer email addresses.
   Supabase's default mail service only sends to project team addresses and
   has restrictive sending limits. Check Auth logs and mail-provider logs when
   investigating delivery failures. See
   [Supabase SMTP configuration](https://supabase.com/docs/guides/auth/auth-smtp).

## End-to-end verification

Use an account and inbox that you control. Automated tests use a local fake API
and do not send real emails or change a live account.

1. Install a fresh build. Enter your email on Sign in, then tap Forgot password.
   Verify that your email is carried over and submit Send reset link.
2. Open the newest email on the same device/browser that requested it. The SDK
   uses PKCE, so keep the requesting app installed and its storage intact.
3. Confirm New password appears both when the app is already open and after
   closing/reopening it through the link. Seven characters and mismatched
   confirmation must be rejected; eight or more matching characters can save.
4. After the saved confirmation, Continue opens the app. Sign out and verify
   the new password works. Reusing an expired/used link offers a new reset link.
5. Repeat with an unavailable network, then retry after reconnecting. A failed
   save must not claim that the password was changed.

An Android route-only check (not a valid recovery session) is:

```powershell
adb shell am start -a android.intent.action.VIEW -d 'com.repairshop101://auth/reset-password' com.example.flutter_101repairshop
```

Without a verified recovery token, no password can be changed. Complete the
email flow above to test the actual recovery screen.
