# Leafs Live

Apple Watch app that follows the Toronto Maple Leafs live and taps your wrist on game events.
Data comes from the public NHL web API (`api-web.nhle.com`), polled every 8 s during a game.

## Haptic patterns

| Event | Pattern |
|---|---|
| Leafs goal | three strong taps |
| Opponent goal | one failure buzz |
| Goal overturned | two retry taps |
| Leafs power play | four even taps |
| Leafs penalty (short-handed) | quick double tap |
| Period start | one tap |
| Period end, final | two taps, pause, one tap |

Each event can be turned off in the Settings page, which also lets you feel each pattern.

## Screen-off tracking

Tap **Go Live** before or during a game. The app starts a workout session with no workout
builder, which keeps it running with the screen off for the whole game. Nothing is saved to
Health. If Health access is declined it falls back to an extended runtime session, which
watchOS caps at about an hour. Live mode stops by itself at the final horn.
At puck drop of each game a notification with a **Go Live** button starts Live mode in one tap.
Prompts for the next 20 games are scheduled whenever the app runs, and refreshed by background refresh.

## Spoiler delay

Settings → Spoiler delay (10 s to 5 min) holds back the score, events, taps and the widget so
they line up with a delayed stream.

## Smart Stack widget

Shows the next game with a countdown, or the live score with a red LIVE dot, the active
penalty (PP/PK, time left, who is in the box) or the last scorer. From 15 minutes before puck
drop it asks watchOS to raise it in the Smart Stack until Live mode is on; tapping it starts
Live mode. The app shares state with the widget through the App Group
`group.com.yakavetsiv.leafslive`.

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
