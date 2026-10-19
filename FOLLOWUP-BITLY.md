# Follow-up task: replace ShortMenu backend with Bitly backend

Correction from the user: ShortMenu-the-Mac-app is a Bitly client — it requires a Bitly API key, not a Short Menu platform account. We are replicating ShortMenu's UX/behavior (that part stays), but we do NOT depend on Short Menu's own platform or api.shortmenu.com. The shortening backend is Bitly API v4 directly. Keep working in /Users/ernest/projects/clipboard in this same project.

## Changes required

1. Rename `ShortMenuClient` → `BitlyClient`, `ShortMenuBackend` → `BitlyBackend`. Remove every reference to `api.shortmenu.com` and "Short Menu" as a service (the app may still be mentioned in docs as the UX inspiration, never as the API backend).
2. Bitly API v4 spec:
   - Base: `https://api-ssl.bitly.com/v4`
   - Shorten (auto slug): `POST /shorten` body `{"long_url": "...", "domain": "bit.ly"}` (domain optional, default bit.ly)
   - Shorten with custom slug / branded domain: `POST /bitlinks` body `{"long_url": "...", "domain": "<user domain>", "custom_slug": "<slug>", "group_guid": optional}`
   - Update: `PATCH /bitlinks/{bitlink}` body `{"long_url": "...", "tags": [...]}` (slug not editable — keep supportsUpdateSlug false)
   - Delete: `DELETE /bitlinks/{bitlink}`
   - Token verify: `GET /user`
   - Click analytics (new capability, do implement — this works unlike the old API): `GET /bitlinks/{bitlink}/clicks?units=-1&unit=day` returns click timeline; store `clickCount` on cached links and add a "Refresh clicks" action in Recent Links.
   - Auth header: `Authorization: Bearer <token>` + `Accept: application/json`
   - Errors to map to ShortenerError: 401 `INVALID_ARG_ACCESS_TOKEN`, 404, `BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`, `DNS_CONFIGURATION_ERROR`
3. Extend `ShortenerCapabilities` with `supportsClickStats` (true for Bitly). `bitlink` ids differ from ShortMenu's (`{guid}` or `bit.ly/xyz` form) — store the full `id`/`link` from the response.
4. Keychain: reuse existing KeychainStore; Settings → Integrations now says "Bitly", field label "Bitly access token", help link `https://dev.bitly.com/`, test-connection uses GET /user.
5. Update unit tests: ShortMenuBackendTests → BitlyBackendTests with URLProtocol mocks for: successful shorten (200 with id/link/long_url/created_at), 401 INVALID_ARG_ACCESS_TOKEN, 404, BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED, custom_slug path hitting /bitlinks, clicks refresh parsing. Rules engine and everything else stays as-is.
6. Update TESTING.md and any README/plan-derived docs that mention Short Menu as the backend.

## Constraints (same as before)
- Confine all changes to /Users/ernest/projects/clipboard. No global installs. No fabricated results.
- Gate before claiming done: `xcodebuild -scheme Clipshot build` AND `xcodebuild -scheme Clipshot test` must both pass.

## Final message must list
Files changed, exact test pass/fail counts, build result, and any deviations.
