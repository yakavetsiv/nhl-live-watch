# Installing Puck Pulse

Puck Pulse is not on the App Store. You build it from source with Xcode and install it on your
own Apple Watch. A free Apple ID is enough.

## What you need

- A Mac with **Xcode 27** or later.
- An **Apple Watch on watchOS 11** or later, paired with an iPhone.
- An **Apple ID** signed in to Xcode (Xcode → Settings → Accounts). The free Personal Team works.

## 1. Get the code

```bash
git clone https://github.com/yakavetsiv/nhl-live-watch.git
cd nhl-live-watch
```

## 2. Fetch the team logos

Logos are NHL trademarks, so they are not stored in the repository. This script downloads the
official SVGs and renders them into `watch/Shared/TeamLogos.xcassets`, which is gitignored:

```bash
./scripts/fetch-logos.sh
```

It takes about a minute and prints each team. You can skip this step: the app then shows team
abbreviations instead of logos.

## 3. Set your signing team

Find your team ID in Xcode → Settings → Accounts → your Apple ID → the team row, or at
[developer.apple.com/account](https://developer.apple.com/account) under Membership. Then create
`watch/Config/Secrets.xcconfig` (gitignored):

```bash
echo 'DEVELOPMENT_TEAM = <your team id>' > watch/Config/Secrets.xcconfig
```

### Bundle ids

The bundle ids are `com.yakavetsiv.leafslive.watchkitapp` and
`com.yakavetsiv.leafslive.watchkitapp.LeafsWidget`, and the App Group is
`group.com.yakavetsiv.leafslive`. A bundle id can belong to only one team. If signing fails with
"bundle identifier is not available", replace `com.yakavetsiv` with your own prefix in these
three places:

- `watch/PuckPulse.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`, four entries)
- `watch/Config/PuckPulse.entitlements` and `watch/Config/PuckPulseWidget.entitlements`
- `appGroup` in `watch/Shared/GameSummary.swift`

## 4. Prepare the watch

1. On the iPhone, open the Watch app and make sure the watch is paired and unlocked.
2. On the watch, turn on **Developer Mode**: Settings → Privacy & Security → Developer Mode,
   then restart the watch when asked. The option appears only after the watch has been
   connected to Xcode once, so open Xcode → Window → Devices and Simulators first and wait for
   the watch to show up.
3. Keep the watch on its charger near the Mac. Wireless installs to a watch are slow and drop
   less often when it is charging.

## 5. Build and install

### With Xcode

1. Open `watch/PuckPulse.xcodeproj`.
2. Pick the **PuckPulse** scheme and your watch as the run destination.
3. Press **Run** (⌘R). The first build to a watch can take several minutes while Xcode copies
   debug symbols.

### From the command line

Find the watch's identifier:

```bash
xcrun devicectl list devices
```

Then build and install, replacing `<watch udid>`:

```bash
cd watch
xcodebuild -project PuckPulse.xcodeproj -scheme PuckPulse \
  -destination 'platform=watchOS,id=<watch udid>' -derivedDataPath build -allowProvisioningUpdates
xcrun devicectl device install app --device <watch udid> build/Build/Products/Debug-watchos/PuckPulse.app
```

If either command fails with "Timed out waiting… Connecting to watch" or `IXRemoteErrorDomain`
error 6, wake the watch and run it again. It usually works on the second try.

### Trust the developer

If the first launch says the developer is not trusted, open Settings → General → VPN & Device
Management on the paired iPhone, tap your Apple ID and tap **Trust**, then open the app again.

## 6. First launch

1. Pick your teams and tap **Done**.
2. Allow **notifications** so you get the Go Live prompt at each puck drop.
3. Allow **Health** when you first tap Go Live. Puck Pulse runs a workout session only to stay
   awake with the screen off; it saves nothing to Health. If you decline, Live mode still works
   but watchOS stops it after about an hour.

### Add the widget

Long-press the watch face or scroll the Smart Stack, tap **Edit**, then **+**, and choose
**Puck Pulse → Next game**. Circular and inline complications are under the same name when you
edit a watch face.

## Free Apple ID: reinstall every 7 days

Apps signed with a free Personal Team stop opening after 7 days. Repeat step 5 to renew. Your
teams and settings are kept. A paid Apple Developer Program membership extends this to a year.

## Simulator

To try it without a watch, run the PuckPulse scheme on any Apple Watch simulator in Xcode, or:

```bash
cd watch
xcodebuild -project PuckPulse.xcodeproj -scheme PuckPulse \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 2 (49mm)' -derivedDataPath build
```

Haptics and screen-off Live mode only work on a real watch.

## Uninstall

Long-press the app icon on the watch and tap the delete button, or remove it from the iPhone's
Watch app under Installed on Apple Watch.
