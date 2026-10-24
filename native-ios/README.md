# MangaBaka Native — M1

Independent SwiftUI iPhone app, iOS 26+. All changes live on `feature/native-ios-m1`; the Flutter app and main branch are preserved.

Generate the project with `brew install xcodegen && xcodegen generate`, open `MangaBakaNative.xcodeproj`, and run the MangaBakaNative scheme. No API key is required. Six public discovery shelves, five tabs, English/Simplified Chinese, system/light/dark appearance, disk image cache and settings persistence are included. Library/Browse/News are explicitly marked as future features. No sign-in or native details are implemented.

Actions builds simulator unit tests and an unsigned arm64 Release IPA. Download `MangaBaka-Native-M1-IPA`. Signing is outside this milestone.

Known scope: “View on MangaBaka” opens the website discovery page; it is not a native all-results or release-calendar implementation. Website content is not translated by this app. Live endpoint and website link smoke checks, physical-device accessibility/appearance review, and screenshots require a device or browser connected to the build environment. No such validation is claimed by the unit tests.

API mappings were derived from Oazzies/MangaBaka-App (Apache-2.0). Native app source is distributed under the repository's Apache-2.0 license. Publisher/series artwork belongs to its respective owners and is served by MangaBaka.
