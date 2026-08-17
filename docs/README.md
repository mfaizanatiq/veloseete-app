# Hosted legal pages

Static Privacy Policy and Terms for App Store Connect.

## URLs (after Pages is enabled)

- Privacy: https://mfaizanatiq.github.io/Veloseete-iOS/privacy/
- Terms: https://mfaizanatiq.github.io/Veloseete-iOS/terms/
- Support: m.faizan.atiq@icloud.com

## Enable GitHub Pages

1. Push `docs/` to `main`
2. Repo **Settings → Pages → Build and deployment**
3. Source: **Deploy from a branch**
4. Branch: `main` / folder `/docs`
5. Save, wait ~1 minute, then open the Privacy URL

When `veloseete.com` is live, point DNS and update `AppLegal.privacyPolicyURL` / `termsOfUseURL`.

## Keep in sync

Edit `Veloseete/Resources/Legal/*.md` (shipped in-app), then refresh `docs/privacy/index.html` and `docs/terms/index.html` to match before release.
