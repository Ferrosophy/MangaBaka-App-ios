# MangaBaka Native — M2

Independent iOS 26+ SwiftUI iPhone app on `feature/native-ios-m2`. Main and the M1 branch are preserved.

Seven native detail categories: Info, Covers, Related, Similar (including readers-also-like), News, Collections, Works. Home cards route by series ID, including upcoming works. Collections open paginated native release directories. Cover preview supports paging, zoom, pan, and system URL sharing. Library/Browse/News root tabs remain M1 placeholders; this milestone adds series-specific news only.

`brew install xcodegen && xcodegen generate` creates the Xcode project. Run scheme MangaBakaNative. No API credentials are needed.

The M2 Actions workflow first captures public response fixtures and publishes `Native-M2-API-validation`, then runs independent IPA build and simulator-test jobs. The workflow exports English/Chinese screenshots and an unsigned arm64 Release IPA; a produced IPA is not itself proof that UI checks passed. A fresh supported simulator is booted explicitly, with bounded boot and test timeouts. UI checks use captured responses; production does not enable fixture mode. `M2_DETAIL` and `M2_FIXTURES` launch environment variables are test-only entry points.

External publisher/source/news links open Safari inside the app. Collection and work metadata keep server order and use stable IDs, preserving different editions with the same volume number. Optional endpoints fail independently. No independent work detail, account, library writes, or reader is included.

The upcoming-home image bug is tracked separately; detail work tiles inspect all supplied work images and use the series cover as a fallback. Fullscreen sharing currently shares the original image URL, not a saved photo. Physical device, large-text, reduced-transparency and VoiceOver review must be reported separately from simulator checks.

Data/API mappings derived from Oazzies/MangaBaka-App, Apache-2.0. Artwork and metadata belong to the respective providers. See repository LICENSE and https://mangabaka.org/data/api for attribution and data terms.
