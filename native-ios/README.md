# MangaBaka Native — M3

iOS 26+ SwiftUI app on `feature/native-ios-m3`, based on M2. Main/M1/M2 are preserved.

M3 implements account-only cloud library management, seven reading states, chapters/volumes/rereads/rating editors, account profiles, library search/layout/sorting, statistics, recent changes/additions, and versioned JSON backup/restore. No guest records or offline write queue. Offline access is a read-only account cache. Cloud saves are acknowledged before updating local state. Full paginated reconciliation is used on activation and manual refresh so remote deletions are detected without relying on timestamp-only sync. Incomplete responses never prune the cache.

## OAuth configuration is required

Upstream `.env.example` contains no client ID and only a placeholder redirect. The native app needs a **registered public OAuth client**, with custom-scheme callback authorized by MangaBaka. Configure GitHub repository variables `MANGABAKA_APP_CLIENT_ID` and `MANGABAKA_APP_REDIRECT_URI`, or set corresponding Xcode build settings `MANGABAKA_CLIENT_ID` and `MANGABAKA_REDIRECT_URI` (and `MANGABAKA_CALLBACK_SCHEME`). No client secret is used or embedded. The default native redirect is `dev.ferrosophy.mangabaka.native://oauthredirect`; it must be registered, not merely added to Info.plist.

For a local build: set environment variables `MANGABAKA_CLIENT_ID` and `MANGABAKA_REDIRECT_URI`, run `python scripts/configure_oauth.py` (PyYAML required), then `xcodegen generate`. The script writes build configuration. Missing configuration produces a review preview with a clear sign-in error, **not a functioning account release**.

System authentication uses `ASWebAuthenticationSession`, OAuth authorization code + S256 PKCE, state validation and exact callback matching. This directly uses Apple's system browser instead of adding the Flutter app's AppAuth dependency. Token refresh is serialized, 401 recovers once, credentials live only in Keychain, and account/session generation prevents old requests from crossing logins. No credentials are included in logs, backup files or test fixtures.

## Manual CI and verification boundaries

`native-ios-m3.yml` is workflow_dispatch-only. It captures public API samples, builds an unsigned arm64 IPA, and runs unit/simulator navigation tests. No developer push automatically triggers this workflow. Simulator auth tests use a mock HTTP transport and memory credential vault; they **do not prove real OAuth or cross-device sync works**. Real login requires registered configuration, a user-driven browser authorization, and separate device checks. Test credentials are synthetic and never used for public API writes.

On-device acceptance: sign in/cancel/relaunch/refresh; fetch full library; create a disposable series record, update its status/progress/rating/rereads and clear its score; verify website/another device sees edits, then delete it; verify remote deletion, network loss, sign out and another account isolation; JSON roundtrip with partial failure; Dynamic Type, VoiceOver and reduced transparency. A missing registered client blocks these checks and must be reported in delivery.

JSON restore previews target account and duplicate choices, keeps cloud values by default, never removes cloud-only entries, and retries failed records only. It is not a cross-request transaction. Backups contain personal reading history but no tokens. No third-party import format or account deletion is included.

The homepage upcoming-cover issue remains separate. Root Browse/News are still placeholders; seven M2 detail categories remain functional. See repository LICENSE for Apache-2.0 attribution to Oazzies/MangaBaka-App and https://mangabaka.org/data/api for data terms.
