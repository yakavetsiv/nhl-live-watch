import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tracker: GameTracker
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            if tracker.teams.isEmpty {
                TeamPickerView(isOnboarding: true)
            } else {
                TabView(selection: $tracker.page) {
                    if tracker.slots.isEmpty {
                        ScoreView(slot: nil).tag(0)
                    }
                    ForEach(Array(tracker.slots.enumerated()), id: \.element.id) { index, slot in
                        ScoreView(slot: slot).tag(index)
                    }
                    EventsView().tag(GameTracker.eventsPage)
                    SettingsView().tag(GameTracker.settingsPage)
                }
                .tabViewStyle(.verticalPage)
            }
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
    let slot: GameSlot?
    @EnvironmentObject var tracker: GameTracker
    @EnvironmentObject var runner: BackgroundRunner

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let slot {
                    statusPill(slot)
                    matchup(slot)
                    infoCard(slot)
                    liveButton(slot.game)
                } else if let error = tracker.error {
                    Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
                if let error = tracker.error, slot != nil {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 2)
        }
        .containerBackground(Color.rink.gradient, for: .tabView)
        .navigationTitle(slot?.team ?? "Hockey Live")
    }

    private func state(_ slot: GameSlot) -> (live: Bool, finished: Bool) {
        let pbp = slot.live
        let live = pbp.map { GameState.isLive($0.gameState) } ?? false
        let finished = pbp.map { GameState.isFinished($0.gameState) } ?? (slot.game.isFinished && tracker.spoilerDelay == 0)
        return (live, finished)
    }

    /// LIVE with period and clock, FINAL, or the start time with a countdown.
    @ViewBuilder private func statusPill(_ slot: GameSlot) -> some View {
        let (live, finished) = state(slot)
        let game = slot.game
        Group {
            if live, let pbp = slot.live {
                HStack(spacing: 6) {
                    LiveDot(size: 7)
                    Text(pbp.statusLabel).monospacedDigit()
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            } else if finished {
                Text(slot.live?.statusLabel ?? "FINAL")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 1) {
                    Text(game.startTimeUTC, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    if game.startTimeUTC > Date() {
                        Text("in \(game.startTimeUTC, style: .relative)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(live ? 0.12 : 0.06)))
    }

    private func matchup(_ slot: GameSlot) -> some View {
        let game = slot.game
        let pbp = slot.live
        let (live, finished) = state(slot)
        let started = live || finished
        // With a spoiler delay, schedule scores are not delayed, so wait for the first delayed snapshot.
        let useSchedule = tracker.spoilerDelay == 0
        let awayScore = started ? pbp?.awayTeam.score ?? (useSchedule ? game.awayTeam.score : nil) : nil
        let homeScore = started ? pbp?.homeTeam.score ?? (useSchedule ? game.homeTeam.score : nil) : nil
        return HStack(alignment: .center, spacing: 4) {
            teamColumn(game.awayTeam.abbrev, awayScore, sog: pbp?.awayTeam.sog,
                       followed: game.awayTeam.abbrev == slot.team, started: started)
            Text(started ? ":" : "@")
                .font(.system(size: started ? 30 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, started ? 34 : 0)
            teamColumn(game.homeTeam.abbrev, homeScore, sog: pbp?.homeTeam.sog,
                       followed: game.homeTeam.abbrev == slot.team, started: started)
        }
    }

    private func teamColumn(_ abbrev: String, _ score: Int?, sog: Int?, followed: Bool, started: Bool) -> some View {
        VStack(spacing: 3) {
            TeamLogo(abbrev: abbrev, size: started ? 42 : 54)
                .overlay(Circle().stroke(Color.rinkBright, lineWidth: followed ? 2.5 : 0).padding(-3))
            Text(abbrev)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(followed ? .primary : .secondary)
            if started {
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                if let sog {
                    Text("\(sog) SOG").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Strength chip, active penalty and last goal while the game is on.
    @ViewBuilder private func infoCard(_ slot: GameSlot) -> some View {
        let pbp = slot.live
        let strength = pbp.flatMap { GameState.isLive($0.gameState) ? $0.strengthLabel(for: slot.team) : nil }
        let penalty = pbp?.activePenaltySummary(for: slot.team)
        let goal = pbp?.lastGoalSummary
        if strength != nil || goal != nil || tracker.spoilerDelay > 0 {
            VStack(alignment: .leading, spacing: 6) {
                if let strength {
                    let good = strength.hasPrefix("PP") || strength == "EMPTY NET"
                    Text(strength)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(good ? Color.green.opacity(0.35) : Color.orange.opacity(0.35)))
                }
                if let penalty {
                    infoRow("exclamationmark.triangle.fill", penalty, tint: .orange)
                }
                if let goal {
                    infoRow("light.beacon.max.fill", goal, tint: .rinkBright)
                }
                if tracker.spoilerDelay > 0 {
                    infoRow("hourglass", "Delayed \(tracker.spoilerDelay) s", tint: .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
        }
    }

    private func infoRow(_ symbol: String, _ text: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint)
            Text(text).font(.system(size: 13)).lineLimit(2)
        }
    }

    @ViewBuilder
    private func liveButton(_ game: ScheduledGame) -> some View {
        if runner.isRunning {
            Button(role: .destructive) { tracker.stopLive() } label: {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right").symbolEffect(.variableColor.iterative)
                    Text("Live taps on")
                    Spacer()
                    Image(systemName: "stop.fill")
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .tint(.green)
        } else if !game.isFinished {
            Button { Task { await tracker.goLive() } } label: {
                Label("Go Live", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(.rinkBright)
            if let err = runner.lastError {
                Text(err).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
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
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("Goals, penalties and periods show up here during a game.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            ForEach(tracker.events) { event in
                HStack(alignment: .top, spacing: 8) {
                    if let team = event.team {
                        TeamLogo(abbrev: team, size: 28)
                    } else {
                        Image(systemName: event.kind.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.white.opacity(0.12)))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(event.kind == .leafsGoal ? Color.rinkBright : .primary)
                        Text(event.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(event.date, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
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
            NavigationLink {
                TeamPickerView(isOnboarding: false)
            } label: {
                HStack(spacing: -6) {
                    ForEach(tracker.teams.prefix(4)) { TeamLogo(abbrev: $0.abbrev, size: 26) }
                    Text("Teams").font(.system(size: 15, weight: .semibold)).padding(.leading, 14)
                }
            }
            Section {
                Picker(selection: $tracker.spoilerDelay) {
                    ForEach(GameTracker.delayOptions, id: \.self) { seconds in
                        Text(seconds == 0 ? "Off" : seconds < 60 ? "\(seconds) s" : seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s")
                            .tag(seconds)
                    }
                } label: {
                    Label("Spoiler delay", systemImage: "hourglass")
                }
            } footer: {
                Text("Holds back score, events and taps so they don't get ahead of your stream.")
            }
            Section("Tap my wrist for") {
                ForEach(EventKind.allCases) { kind in
                    Toggle(isOn: Binding(get: { tracker.isEnabled(kind) }, set: { tracker.setEnabled(kind, $0) })) {
                        Label(kind.settingTitle, systemImage: kind.symbol)
                    }
                }
            }
            Section("Feel the patterns") {
                ForEach(EventKind.allCases) { kind in
                    Button { tracker.preview(kind) } label: {
                        Label(kind.settingTitle, systemImage: "hand.tap")
                    }
                }
            }
            Section {
                Button { Notifier.sendTestPrompt(for: tracker.slots.first?.game, team: tracker.slots.first?.team) } label: {
                    Label("Test game-start alert", systemImage: "bell.badge")
                }
            } footer: {
                Text("At each puck drop you get an alert with a Go Live button. This sends one in 5 s.")
            }
            if let updated = tracker.lastUpdate {
                Text("Updated \(updated, format: .dateTime.hour().minute().second())")
                    .font(.caption2).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Team picker

/// Pick the teams to follow. Shown on first launch and from Settings.
struct TeamPickerView: View {
    let isOnboarding: Bool
    @EnvironmentObject var tracker: GameTracker
    @Environment(\.dismiss) private var dismiss
    @State private var all: [Team] = []
    @State private var selected: Set<String> = []
    @State private var failed = false

    var body: some View {
        List {
            if isOnboarding {
                VStack(spacing: 6) {
                    Image(systemName: "hockey.puck.fill").font(.system(size: 30)).foregroundStyle(Color.rinkBright)
                    Text("Pick the teams to follow. Change them later in Settings.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            if all.isEmpty {
                if failed {
                    Button("Retry") { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
            Section("NHL") {
                ForEach(all.filter { $0.league == .nhl }) { team in
                    let on = selected.contains(team.id)
                    Button { toggle(team) } label: {
                        HStack(spacing: 10) {
                            TeamLogo(abbrev: team.abbrev, size: 30)
                            Text(team.name).font(.system(size: 14, weight: on ? .semibold : .regular)).lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(on ? Color.rinkBright : .secondary)
                        }
                    }
                }
            }
            Section {
                EmptyView()
            } header: {
                Text("AHL")
            } footer: {
                Text("AHL teams are coming: the AHL score feed needs an access key.")
            }
        }
        .navigationTitle(isOnboarding ? "Your teams" : "Teams")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    tracker.setTeams(all.filter { selected.contains($0.id) })
                    if !isOnboarding { dismiss() }
                }
                .disabled(selected.isEmpty)
            }
        }
        .task {
            selected = Set(tracker.teams.map(\.id))
            await load()
        }
    }

    private func toggle(_ team: Team) {
        if selected.contains(team.id) { selected.remove(team.id) } else { selected.insert(team.id) }
    }

    private func load() async {
        failed = false
        do { all = try await NHLClient().teams() } catch { failed = true }
    }
}
