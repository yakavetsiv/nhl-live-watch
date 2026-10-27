# Leafs Live

Apple Watch app that follows the Toronto Maple Leafs live and taps your wrist on game events.
Data comes from the public NHL web API (`api-web.nhle.com`), polled every 8 s during a game.

## Haptic patterns

| Event | Pattern |
|---|---|
| Leafs goal | five strong taps (goal horn) |
| Opponent goal | one failure buzz |
| Goal overturned | two retry taps |
| Leafs power play | two rising taps |
| Leafs penalty | one falling tap |
| Period start / end | start tap |
| Final | win: celebration, loss: failure + stop |

Each event can be turned off in the Settings page, which also lets you feel each pattern.

## Screen-off tracking

Tap **Go Live** before or during a game. The app starts a workout session with no workout
builder, which keeps it running with the screen off for the whole game. Nothing is saved to
Health. If Health access is declined it falls back to an extended runtime session, which
watchOS caps at about an hour. Live mode stops by itself at the final horn.
A local notification 10 minutes before each game reminds you to open the app.

## Build

Put your team in `watch/Config/Secrets.xcconfig` (gitignored):

    DEVELOPMENT_TEAM = <team id>

Then build to the watch:

    cd watch
    xcodebuild -project LeafsLive.xcodeproj -scheme LeafsLive \
      -destination 'platform=watchOS,id=<watch udid>' -derivedDataPath build -allowProvisioningUpdates
    xcrun devicectl device install app --device <watch udid> build/Build/Products/Debug-watchos/LeafsLive.app

With a free Personal Team the signing expires after 7 days; rebuild and reinstall weekly.
To follow another team, change `Club.abbrev` in `NHLModels.swift`.
