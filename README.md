# Puck Pulse (nhl-live-watch)

Apple Watch app that follows your NHL teams live and taps your wrist on game events.
On first launch you pick any number of teams; change them later in Settings → Teams.
Each followed game gets its own page.
Data comes from the public NHL web API (`api-web.nhle.com`), polled every 8 s during a game.

## Haptic patterns

| Event | Pattern |
|---|---|
| Your team goal | three strong taps |
| Opponent goal | one failure buzz |
| Goal overturned | two retry taps |
| Your team power play | four even taps |
| Your team penalty (short-handed) | quick double tap |
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

Shows team logos (abbreviations on tinted watch faces), the next game with a countdown, or the live score with a red LIVE dot, the active
penalty (PP/PK, time left, who is in the box) or the last scorer. From 15 minutes before puck
drop it asks watchOS to raise it in the Smart Stack until Live mode is on; tapping it starts
Live mode. The app shares state with the widget through the App Group
`group.com.yakavetsiv.leafslive`.

## Build

Team logos are NHL trademarks, so they are not in the repo. Fetch them once (needs network;
converts the official SVGs into a gitignored asset catalog). Without them the app shows
team abbreviations.

    ./scripts/fetch-logos.sh

Put your team in `watch/Config/Secrets.xcconfig` (gitignored):

    DEVELOPMENT_TEAM = <team id>

Then build to the watch:

    cd watch
    xcodebuild -project PuckPulse.xcodeproj -scheme PuckPulse \
      -destination 'platform=watchOS,id=<watch udid>' -derivedDataPath build -allowProvisioningUpdates
    xcrun devicectl device install app --device <watch udid> build/Build/Products/Debug-watchos/PuckPulse.app

With a free Personal Team the signing expires after 7 days; rebuild and reinstall weekly.

Bundle ids (`com.yakavetsiv.leafslive.watchkitapp`) and the App Group (`group.com.yakavetsiv.leafslive`)
keep the app's original name so existing installs update in place. The icon is drawn by
`scripts/make-icon.swift`.
