import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tracker: GameTracker
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "widgetPreview") {
                WidgetPreview()
            } else {
                pages
            }
            #else
            pages
            #endif
        }
        .onAppear {
            tracker.startPolling()
            #if DEBUG
            WidgetPreview.pushSampleIfAsked()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            tracker.isActive = phase == .active
            if phase == .active { tracker.refreshNow() }
        }
    }

    @ViewBuilder private var pages: some View {
        if tracker.teams.isEmpty {
            TeamPickerView(isOnboarding: true)
        } else {
            TabView(selection: $tracker.page) {
                if tracker.slots.isEmpty {
                    ScoreView(slot: nil).tag(0)
                }
                ForEach(Array(tracker.slots.enumerated()), id: \.element.id) { index, slot in
                    ScoreView(slot: slot, isCurrent: tracker.page == index).tag(index)
                }
                EventsView().tag(GameTracker.eventsPage)
                SettingsView().tag(GameTracker.settingsPage)
            }
            .tabViewStyle(.verticalPage)
        }
    }
}

// MARK: - Score

struct ScoreView: View {
    let slot: GameSlot?
    /// Only the page on screen takes the double-tap gesture.
    var isCurrent = true
    @EnvironmentObject var tracker: GameTracker
    @EnvironmentObject var runner: BackgroundRunner

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.size(10)) {
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
        #if DEBUG
        // Simulator screenshots: `-scrollToBottom YES` opens each game page scrolled to the end.
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "scrollToBottom") ? .bottom : .top)
        #endif
        .containerBackground(Color.rink.gradient, for: .tabView)
        .navigationTitle(slot?.team ?? "Puck Pulse")
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
                    LiveDot(size: Layout.size(7))
                    Text(pbp.statusLabel).monospacedDigit()
                }
                .scaledFont(15, relativeTo: .headline, weight: .semibold, design: .rounded)
            } else if finished {
                Text(slot.live?.statusLabel ?? "FINAL")
                    .scaledFont(15, relativeTo: .headline, weight: .semibold, design: .rounded)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 1) {
                    Text(game.startTimeUTC, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .scaledFont(16, relativeTo: .headline, weight: .semibold, design: .rounded)
                    if game.startTimeUTC > Date() {
                        Text("in \(game.startTimeUTC, style: .relative)")
                            .scaledFont(13, relativeTo: .footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, Layout.size(10)).padding(.vertical, Layout.size(4))
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
                .scaledFont(started ? 30 : 16, relativeTo: .title, weight: .bold, design: .rounded)
                .foregroundStyle(.secondary)
                .padding(.top, started ? Layout.size(34) : 0)
            teamColumn(game.homeTeam.abbrev, homeScore, sog: pbp?.homeTeam.sog,
                       followed: game.homeTeam.abbrev == slot.team, started: started)
        }
        // The score row is sized to the screen; very large text sizes would push it off the page.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func teamColumn(_ abbrev: String, _ score: Int?, sog: Int?, followed: Bool, started: Bool) -> some View {
        VStack(spacing: 3) {
            TeamLogo(abbrev: abbrev, size: Layout.size(started ? 42 : 54))
                .overlay(Circle().stroke(Color.rinkBright, lineWidth: followed ? 2.5 : 0).padding(-3))
            Text(abbrev)
                .scaledFont(13, relativeTo: .footnote, weight: .semibold, design: .rounded)
                .lineLimit(1)
                .foregroundStyle(followed ? .primary : .secondary)
            if started {
                Text(score.map(String.init) ?? "–")
                    .scaledFont(44, relativeTo: .largeTitle, weight: .heavy, design: .rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let sog {
                    Text("\(sog) SOG").scaledFont(11, relativeTo: .caption2, weight: .medium).foregroundStyle(.secondary)
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
                        .scaledFont(12, relativeTo: .caption, weight: .bold, design: .rounded)
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
            .padding(Layout.size(10))
            .background(RoundedRectangle(cornerRadius: Layout.size(14)).fill(.white.opacity(0.08)))
        }
    }

    private func infoRow(_ symbol: String, _ text: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).scaledFont(11, relativeTo: .caption2).foregroundStyle(tint)
            Text(text).scaledFont(13, relativeTo: .footnote).lineLimit(3)
        }
    }

    @ViewBuilder
    private func liveButton(_ game: ScheduledGame) -> some View {
        if runner.isRunning {
            Button(role: .destructive) { tracker.stopLive() } label: {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right").symbolEffect(.variableColor.iterative)
                    Text("Live taps on").lineLimit(1).minimumScaleFactor(0.8)
                    Spacer()
                    Image(systemName: "stop.fill")
                }
                .scaledFont(15, relativeTo: .headline, weight: .semibold)
            }
            .tint(.green)
        } else if !game.isFinished {
            Button { Task { await tracker.goLive() } } label: {
                Label("Go Live", systemImage: "applewatch.radiowaves.left.and.right")
                    .scaledFont(16, relativeTo: .headline, weight: .semibold)
                    .frame(maxWidth: .infinity)
            }
            .tint(.rinkBright)
            // Double tap (Series 9 and later, Ultra 2 and later) starts Live mode without touching the screen.
            .handGestureShortcut(.primaryAction, isEnabled: isCurrent)
            if let err = runner.lastError {
                Text(err).scaledFont(10, relativeTo: .caption2).foregroundStyle(.orange).lineLimit(2)
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
                    Image(systemName: "list.bullet.rectangle").scaledFont(28, relativeTo: .title).foregroundStyle(.secondary)
                    Text("Goals, penalties and periods show up here during a game.")
                        .scaledFont(13, relativeTo: .footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            ForEach(tracker.events) { event in
                HStack(alignment: .top, spacing: 8) {
                    if let team = event.team {
                        TeamLogo(abbrev: team, size: Layout.size(28))
                    } else {
                        Image(systemName: event.kind.symbol)
                            .scaledFont(13, relativeTo: .footnote, weight: .semibold)
                            .frame(width: Layout.size(28), height: Layout.size(28))
                            .background(Circle().fill(.white.opacity(0.12)))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .scaledFont(14, relativeTo: .subheadline, weight: .semibold)
                            .foregroundStyle(event.kind == .teamGoal ? Color.rinkBright : .primary)
                        Text(event.detail).scaledFont(12, relativeTo: .caption).foregroundStyle(.secondary)
                        Text(event.date, style: .relative).scaledFont(10, relativeTo: .caption2).foregroundStyle(.tertiary)
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
                    ForEach(tracker.teams.prefix(4)) { TeamLogo(abbrev: $0.abbrev, size: Layout.size(26)) }
                    Text("Teams").scaledFont(15, relativeTo: .headline, weight: .semibold).padding(.leading, 14)
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
                    Image(systemName: "hockey.puck.fill").scaledFont(30, relativeTo: .title).foregroundStyle(Color.rinkBright)
                    Text("Pick the teams to follow. Change them later in Settings.")
                        .scaledFont(13, relativeTo: .footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                            TeamLogo(abbrev: team.abbrev, size: Layout.size(30))
                            Text(team.name).scaledFont(14, relativeTo: .subheadline, weight: on ? .semibold : .regular).lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .scaledFont(18, relativeTo: .title3)
                                .foregroundStyle(on ? Color.rinkBright : .secondary)
                        }
                    }
                }
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
