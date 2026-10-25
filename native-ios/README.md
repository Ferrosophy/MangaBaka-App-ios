# MangaBaka Native — M3 (PAT)

iOS 26+ SwiftUI app on `feature/native-ios-m3`. Main, M1 and M2 are preserved. Chinese/English, light/dark mode.

## Connect your account

1. Open https://mangabaka.org/my/settings/api-and-apps in your browser and sign in.
2. Under **Personal access tokens (PAT) for API**, choose **New token**.
3. In the app, choose **Sign in**, enter the `mb-` token and tap **Connect account**.
4. The app verifies `/v1/my/profile` using **`x-api-key`**, then stores the token in this device's Keychain and syncs the library. No OAuth client registration, `.env`, CI secrets, or redirect URI is required.

Tokens never go into UserDefaults, SwiftData, JSON backups, URLs, build variables, fixtures or logs. The app does not automatically read the clipboard. Invalid/revoked tokens cause reauthentication; PATs do not use OAuth refresh. Sign out removes this device's saved token and account cache; to revoke the token itself use the website. Network failures and 403 permission errors do not discard a valid session. Cross-host redirects never receive the token. Keychain failure prevents login, with no plaintext fallback. The unsigned simulator can report Keychain entitlement failures; account UI tests use a memory vault, and physical-device Keychain must be checked after installation/signing.

## Library behavior

Seven states; chapters/volumes/rereads/rating editing; completed-status confirmation; account profile and statistics; recent additions/changes; local search, layout and sorting; versioned JSON backup/restore. No guest library and no offline write queue. Offline mode shows a read-only account cache. Changes update local state only after cloud acknowledgement. Account/session identity guards every operation, including restore loops.

Read **`/v2/my/library`** (`entry`, `series`, `lists`) with full metadata; create/update/delete through documented `/v1/my/library/{series_id}`. Creates send one POST with all tracked fields; edits PATCH only changed fields. Follow pagination to completion before pruning remote deletions; malformed/incomplete pages preserve the old cache. Missing server timestamps remain unknown rather than inventing dates. Fractional chapters/volumes and scores are preserved. API limits: progress 0–10000, rereads 0–1000, score 0–100. **The API normalizes score 0 to null (not rated)**, so zero is excluded from mean-score statistics. Null progress/re-read counts display as zero.

JSON backups contain reading history and cached metadata, never the PAT. They preserve private-entry flags, priority, reading links and recorded dates; ordinary progress edits do not overwrite these website fields. Custom website lists are outside M3. Restore previews the target account and duplicate selections, keeps cloud records by default, never deletes cloud-only entries, and retries failed entries only. Restore is not a transaction across HTTP requests. No third-party import formats or account deletion.

## Build and checks

`brew install xcodegen && xcodegen generate` then build scheme MangaBakaNative. `.github/workflows/native-ios-m2.yml` on the M3 branch is named Native iOS M3 and supports **manual dispatch only**. `test_scope=full` is the default; `unit` is available for a small follow-up data change after the UI regression has already passed. The registered workflow path is retained so main need not change. It captures public API samples, builds an unsigned arm64 IPA and runs unit/simulator tests.

Simulator review tests use a synthetic PAT and local mock API, exercising login and account UI/edits without touching real accounts. The review transport and memory-vault entry point compile **only for DEBUG simulator**, never Release/device IPA. Tests are not proof of real PAT account/device verification. Enter a real token **inside the installed app**, not in chat or GitHub, to verify actual account login, cross-device sync and Keychain persistence. No real user token has been used in CI.

Public contract: https://mangabaka.org/api.json (security scheme `x-api-key`; PATs start with `mb-`). M4 replaces the root Browse/News placeholders and removes the homepage Upcoming Releases shelf. M2 detail categories remain functional. Source/API mappings derived from Oazzies/MangaBaka-App under Apache-2.0; artwork belongs to its providers. See LICENSE and https://mangabaka.org/data/api.

## M4 (0.4.0)

Branch: `feature/native-ios-m4`, based on the completed M3 PAT build. Main is unchanged.

Adds native Browse/search/filter/rank/random lists, News with referenced-series links,
Mix seed discovery, account recommendation queues, and local General/Content settings.
Removes Upcoming Releases and its request completely. No OAuth configuration is needed.

Content exclusions filter visible cards, never delete cloud records or alter numerical
statistics. Cover blur is separate. Existing caches decode new optional rating/title fields.
Preferences and recommendation dismissals stay on-device; dismissals are account-scoped.
Queue additions use M3 write acknowledgement and require an online, fully synced library.

Manual CI only: full regression by default, focused unit follow-up available. Debug
simulator-only fixtures (`M4_FIXTURES=1`) contain synthetic series/news and no credentials.
Real PAT cross-device writes require an installed app and a token entered by its owner;
synthetic screenshots must not be described as real-account validation.

## M4 layout and translation follow-up (0.4.1)

Every bitmap thumbnail now lives in a clipped GeometryReader viewport with aspect-fill;
its intrinsic dimensions cannot size a card. Grid titles reserve two lines; progress,
relationship, release and price rows reserve their own slots. Fullscreen zoom remains fit.
Horizontal shelves snap to aligned cards and permit rendering into their safe margins.
Refresh cleanup ends the native control and corrects only an overscrolled top offset;
a 60-second cancellable deadline prevents an unbounded paginated read holding refresh.

Details use one add-to-library state menu, a pinned glass tab strip, a continuous blurred
cover backdrop extending through the top safe area, and aligned source-logo score cells.
Seven source icons were extracted from MangaBaka's actual HTML; see ICON-SOURCES.json.
SVG sources were converted to vector PDF; bitmap sources keep their original pixels.

Translation is opt-in per description. Google Cloud Basic v2, Volcengine TranslateText
(2020-06-01, cn-north-1), and Microsoft Translator v3 use user-owned credentials stored
only in a separate ThisDeviceOnly Keychain service. No shared service keys are shipped.
Google is selected by default; unconfigured providers lead to Settings. Test Connection
always contacts the selected service, bypassing translation caches. Redirects are rejected
so provider credentials cannot be forwarded to another host. Description and credential
fingerprints partition the in-memory cache; switching descriptions/providers cancels stale
UI updates. Only public descriptions, never MangaBaka PAT/library data, are translated.

Verification adds independent Volcengine signing vectors, response fixtures for all three
providers, cancellation/deadline tests, and layout screenshots with portrait/landscape/
square/missing images, long/short titles and known/unknown progress. Live paid translation
requires the user's own credentials and must be reported separately from fixture tests.
