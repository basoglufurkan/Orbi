import SwiftData
import SwiftUI

/// Focus together: invite friends or join with a code, wait in the lobby,
/// then begin at the same moment. Late arrivals begin when they join.
struct TogetherSheet: View {
    /// What a hosted room will be.
    var minutes: Int
    var category: FocusCategory

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var joining = false
    @State private var name = ""
    @State private var code = ""

    var body: some View {
        let together = app.together
        NavigationStack {
            ZStack {
                CosmicBackgroundView(mood: .reward, light: 0.4, starOpacity: 0.7)
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.l) {
                        switch together.phase {
                        case .idle:
                            if joining || together.pendingJoinCode != nil { joinForm } else { choose }
                        case .lobby, .countdown:
                            if let room = together.room { lobby(room: room) }
                        case .focusing, .finished:
                            EmptyView()
                        }
                        if let error = together.error {
                            Label(error.localizedDescription, systemImage: "exclamationmark.circle")
                                .font(LMFont.callout).foregroundStyle(LMColor.warm)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(LMSpace.l)
                    .readableColumn()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) {
                        if together.phase == .lobby || together.phase == .countdown { together.leave() }
                        together.pendingJoinCode = nil
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // The last session together is over; start fresh, keeping a new invite.
            if together.phase == .finished {
                let invite = together.pendingJoinCode
                together.leave()
                together.pendingJoinCode = invite
            }
            name = app.preferences.displayName
            if let pending = together.pendingJoinCode { code = pending; joining = true }
        }
        // A swipe would leave the room open with the friend waiting; Close leaves it properly.
        .interactiveDismissDisabled(together.phase == .lobby || together.phase == .countdown)
        .onChange(of: together.phase) { _, phase in
            if phase == .focusing { dismiss() }
        }
        .telemetryScreen("together")
    }

    // MARK: Choose

    private var choose: some View {
        VStack(alignment: .leading, spacing: LMSpace.m) {
            header(title: String(localized: "Focus together"),
                   line: String(localized: "Invite up to 7 friends. You'll sit together in one galaxy, each at your own desk, while you focus."))
            nameField
            CosmicButton(title: "Invite friends", systemImage: "person.2.fill", kind: .reward) {
                Task { await app.together.host(minutes: minutes, category: category, name: rememberName()) }
            }
            .disabled(app.together.isBusy)
            .accessibilityIdentifier("together.invite")
            CosmicButton(title: "I have a code", systemImage: "number", kind: .secondary, height: 52) {
                joining = true
            }
            .accessibilityIdentifier("together.haveCode")
            privacyNote
        }
    }

    // MARK: Join

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: LMSpace.m) {
            header(title: String(localized: "Join a friend"),
                   line: String(localized: "Enter the code your friend sent you."))
            TextField(String(localized: "Code"), text: $code)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .padding(LMSpace.m)
                .glassCard(radius: 18)
                .onChange(of: code) { _, value in
                    let tidy = TogetherInvite.normalize(value)
                    if tidy != value { code = tidy }
                }
                .accessibilityIdentifier("together.code")
            nameField
            CosmicButton(title: "Join", systemImage: "arrow.right", kind: .reward) {
                Task { await app.together.join(code: code, name: rememberName()) }
            }
            .disabled(!TogetherInvite.isValid(code) || app.together.isBusy)
            .accessibilityIdentifier("together.join")
            privacyNote
        }
    }

    // MARK: Lobby

    private func lobby(room: TogetherRoom) -> some View {
        let together = app.together
        let isHost = together.role == .host
        return VStack(alignment: .leading, spacing: LMSpace.m) {
            header(title: isHost ? String(localized: "Your room") : String(localized: "You're in"),
                   line: String(localized: "\(room.minutes) min · \(room.category.displayName)"))
            Text(room.code)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .kerning(6)
                .foregroundStyle(LMColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LMSpace.m)
                .glassCard(radius: 22)
                .accessibilityLabel(Text("Room code \(room.code.map(String.init).joined(separator: " "))"))
                .accessibilityIdentifier("together.roomCode")

            if together.phase == .countdown, let at = room.startsAt {
                countdown(to: at)
            } else {
                TimelineView(.periodic(from: .now, by: 5)) { timeline in
                    people(in: room, at: timeline.date)
                }
                if isHost {
                    CosmicButton(title: "Start together", systemImage: "sparkles", kind: .reward) {
                        Task { await together.startTogether() }
                    }
                    .disabled(together.isBusy)
                    .accessibilityIdentifier("together.start")
                } else {
                    friendRow(String(localized: "Waiting for \(room.hostName) to start…"), joined: false)
                }
                ShareLink(item: TogetherInvite.link(for: room.code),
                          message: Text("Focus with me in Orbi ✦ Tap to join, or enter the code \(room.code) in Orbi.")) {
                    Label(String(localized: "Send invite"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(CosmicButtonStyle(kind: .secondary, height: 52))
                .simultaneousGesture(TapGesture().onEnded { Telemetry.log(.togetherInviteShared) })
                .accessibilityIdentifier("together.share")
                Text("Up to 8 people. Friends can join even after you start.")
                    .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(String(localized: "Leave room")) {
                together.leave()
                dismiss()
            }
            .font(LMFont.callout.weight(.semibold)).foregroundStyle(LMColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    /// Who's in the room: each person a seat, this device marked.
    private func people(in room: TogetherRoom, at now: Date) -> some View {
        let together = app.together
        let here = together.present(at: now)
        return VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "In the room · \(here.count) of \(TogetherRoom.capacity)"), color: LMColor.calm)
            ForEach(here) { member in
                HStack(spacing: LMSpace.s) {
                    Image(systemName: member.isHost ? "star.fill" : "sparkle")
                        .foregroundStyle(member.isHost ? LMColor.reward : LMColor.calm)
                        .frame(width: 20)
                    Text(member.slot == together.slot ? String(localized: "\(member.name) (you)") : member.name)
                        .font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                    Spacer(minLength: 0)
                }
            }
            if here.count < 2 {
                HStack(spacing: LMSpace.s) {
                    ProgressView().tint(LMColor.textSecondary).frame(width: 20)
                    Text("Waiting for friends…").font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LMSpace.m)
        .glassCard(radius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("together.status")
        .animation(LMSpring.snap, value: here.map(\.slot))
    }

    private func countdown(to date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let left = max(0, Int(date.timeIntervalSince(timeline.date).rounded(.up)))
            VStack(spacing: LMSpace.xs) {
                Text("\(left)")
                    .font(LMFont.timer(size: 72)).foregroundStyle(LMColor.reward)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.25), value: left)
                Text("Starting together…").font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Pieces

    private func header(title: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(LMFont.voice(.largeTitle)).foregroundStyle(LMColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(line).font(LMFont.body).foregroundStyle(LMColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowText(String(localized: "Your name for your friends"), color: LMColor.calm)
            TextField(String(localized: "First name"), text: $name)
                .textContentType(.givenName)
                .padding(LMSpace.m)
                .glassCard(radius: 18)
                .accessibilityIdentifier("together.name")
        }
    }

    private func friendRow(_ text: String, joined: Bool) -> some View {
        HStack(spacing: LMSpace.s) {
            if joined {
                Image(systemName: "sparkle").foregroundStyle(LMColor.reward)
            } else {
                ProgressView().tint(LMColor.textSecondary)
            }
            Text(text).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(LMSpace.m)
        .glassCard(radius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("together.waiting")
    }

    private var privacyNote: some View {
        Label(String(localized: "Only your first name, the session length and when you start, finish or leave pass through iCloud, and only to the people with your code."),
              systemImage: "lock.fill")
            .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rememberName() -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, app.preferences.displayName.isEmpty {
            app.preferences.displayName = trimmed
            app.dataStore.save()
        }
        return trimmed
    }
}

/// Shown on the summary when this session was focused together.
struct TogetherSummaryCard: View {
    var sessionID: UUID
    @Environment(AppModel.self) private var app

    var body: some View {
        let id: UUID? = sessionID
        if let shared = try? app.dataStore.context.fetch(FetchDescriptor<SharedFocus>(predicate: #Predicate { $0.sessionID == id })).first {
            HStack(spacing: LMSpace.s) {
                Image(systemName: "person.2.fill").font(.title3).foregroundStyle(LMColor.calm)
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(String(localized: "Focused together"), color: LMColor.calm)
                    Text("A bridge of light now joins your stars.")
                        .font(LMFont.callout.weight(.semibold)).foregroundStyle(LMColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status(shared))
                        .font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(LMSpace.m)
            .glassCard(radius: 22, border: LMColor.calm.opacity(0.35))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("summary.together")
        }
    }

    private func status(_ shared: SharedFocus) -> String {
        app.together.friendFinished || shared.friendFinished
            ? String(localized: "\(shared.friendName) finished too ✦")
            : String(localized: "Still focusing: \(shared.friendName)")
    }
}
