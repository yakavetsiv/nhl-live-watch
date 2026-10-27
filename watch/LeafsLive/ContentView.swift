import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tracker: GameTracker
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TabView(selection: $tracker.page) {
                ScoreView().tag(0)
                EventsView().tag(1)
                SettingsView().tag(2)
            }
            .tabViewStyle(.verticalPage)
        }
        .onAppear { tracker.startPolling() }
        .onChange(of: scenePhase) { _, phase in
            tracker.isActive = phase == .active
            if phase == .active { tracker.refreshNow() }
        }
    }
}

// MARK: - Score

struct ScoreView: View {
    @EnvironmentObject var tracker: GameTracker
    @EnvironmentObject var runner: BackgroundRunner

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let game = tracker.game {
                    header(game)
                    scoreboard(game)
                    liveButton(game)
                    if tracker.spoilerDelay > 0 {
                        Label("Delayed \(tracker.spoilerDelay) s", systemImage: "hourglass")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                } else if let error = tracker.error {
                    Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
                if let error = tracker.error, tracker.game != nil {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .containerBackground(Color.leafsBlue.gradient, for: .tabView)
        .navigationTitle("Leafs Live")
    }

    private func header(_ game: ScheduledGame) -> some View {
        let pbp = tracker.live?.id == game.id ? tracker.live : nil
        return Group {
            if let pbp, GameState.isLive(pbp.gameState) {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("LIVE").foregroundStyle(.red)
                    Text(pbp.periodDescriptor?.label ?? "")
                    if let clock = pbp.clock {
                        Text(clock.inIntermission ? "INT \(clock.timeRemaining)" : clock.timeRemaining)
                            .monospacedDigit()
                    }
                }
                .font(.headline)
            } else if pbp.map({ GameState.isFinished($0.gameState) }) ?? (game.isFinished && tracker.spoilerDelay == 0) {
                Text("FINAL").font(.headline)
            } else {
                VStack(spacing: 0) {
                    Text(game.startTimeUTC, format: .dateTime.weekday(.abbreviated).month().day())
                    Text(game.startTimeUTC, format: .dateTime.hour().minute())
                        .font(.title3.bold())
                    if game.startTimeUTC > Date() {
                        Text("in \(game.startTimeUTC, style: .relative)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func scoreboard(_ game: ScheduledGame) -> some View {
        let pbp = tracker.live?.id == game.id ? tracker.live : nil
        let away = pbp?.awayTeam.abbrev ?? game.awayTeam.abbrev
        let home = pbp?.homeTeam.abbrev ?? game.homeTeam.abbrev
        // With a spoiler delay, schedule scores are not delayed, so wait for the first delayed snapshot.
        let useSchedule = tracker.spoilerDelay == 0
        let started = pbp.map { GameState.isLive($0.gameState) || GameState.isFinished($0.gameState) }
            ?? (game.isLive || game.isFinished)
        let awayScore = started ? pbp?.awayTeam.score ?? (useSchedule ? game.awayTeam.score : nil) : nil
        let homeScore = started ? pbp?.homeTeam.score ?? (useSchedule ? game.homeTeam.score : nil) : nil
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                teamColumn(away, awayScore, sog: pbp?.awayTeam.sog)
                Text("@").font(.caption).foregroundStyle(.secondary)
                teamColumn(home, homeScore, sog: pbp?.homeTeam.sog)
            }
            if let label = pbp?.strengthLabel, pbp.map({ GameState.isLive($0.gameState) }) == true {
                Text(label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(label.hasPrefix("PP") || label == "EMPTY NET" ? Color.green.opacity(0.5) : Color.orange.opacity(0.5),
                                in: Capsule())
            }
            if let penalty = pbp?.activePenaltySummary {
                Text(penalty).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
            }
            if let goal = pbp?.lastGoalSummary {
                Label(goal, systemImage: "flag.checkered")
                    .font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            }
        }
    }

    private func teamColumn(_ abbrev: String, _ score: Int?, sog: Int?) -> some View {
        let leafs = abbrev == Club.abbrev
        return VStack(spacing: 0) {
            Text(abbrev)
                .font(.caption.bold())
                .foregroundStyle(leafs ? .white : .secondary)
            Text(score.map(String.init) ?? "–")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let sog { Text("SOG \(sog)").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func liveButton(_ game: ScheduledGame) -> some View {
        if runner.isRunning {
            Button(role: .destructive) { tracker.stopLive() } label: {
                Label("Stop Live", systemImage: "stop.fill")
            }
            Text("Taps on: \(runner.mode.rawValue)").font(.system(size: 10)).foregroundStyle(.secondary)
        } else if !game.isFinished {
            Button { Task { await tracker.goLive() } } label: {
                Label("Go Live", systemImage: "applewatch.radiowaves.left.and.right")
            }
            .tint(.leafsBright)
            if let err = runner.lastError {
                Text(err).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }
}

// MARK: - Events

struct EventsView: View {
    @EnvironmentObject var tracker: GameTracker

    var body: some View {
        List {
            if tracker.events.isEmpty {
                Text("Goals, penalties and period changes show up here while the app is tracking.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(tracker.events) { event in
                HStack(alignment: .top) {
                    Image(systemName: event.kind.symbol)
                        .foregroundStyle(event.kind == .leafsGoal || event.kind == .powerPlay ? Color.leafsBright : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.footnote.bold())
                        Text(event.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Events")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var tracker: GameTracker

    var body: some View {
        List {
            Section("Tap my wrist for") {
                ForEach(EventKind.allCases) { kind in
                    Toggle(kind.settingTitle, isOn: Binding(
                        get: { tracker.isEnabled(kind) },
                        set: { tracker.setEnabled(kind, $0) }))
                }
            }
            Section("Feel the patterns") {
                ForEach(EventKind.allCases) { kind in
                    Button { tracker.preview(kind) } label: {
                        Label(kind.settingTitle, systemImage: kind.symbol)
                    }
                }
            }
            Section {
                Picker("Spoiler delay", selection: $tracker.spoilerDelay) {
                    ForEach(GameTracker.delayOptions, id: \.self) { seconds in
                        Text(seconds == 0 ? "Off" : seconds < 60 ? "\(seconds) s" : seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s")
                            .tag(seconds)
                    }
                }
            } footer: {
                Text("Holds back score, events and taps so they don't get ahead of your stream.")
            }
            Section {
                Button { Notifier.sendTestPrompt(for: tracker.game) } label: {
                    Label("Test game-start alert", systemImage: "bell.badge")
                }
            } footer: {
                Text("At each puck drop you get an alert with a Go Live button. This sends one in 5 s.")
            }
            if let updated = tracker.lastUpdate {
                Text("Updated \(updated, format: .dateTime.hour().minute().second())")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
