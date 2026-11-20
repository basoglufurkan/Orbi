import SwiftUI

/// Today's orbit on Plan: a small living route of the day's blocks with a
/// countdown to what's now or next. Tapping it opens the full orbit; the
/// play button begins a focus on that block. With nothing planned it invites
/// planning the day. The section above it carries the title and lit count.
struct DayOrbitCard: View {
    /// Today's blocks, in order.
    var blocks: [PlanBlock]

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if blocks.isEmpty {
            invitation
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                card(DayTimeline(blocks: blocks, now: app.clock.now))
            }
        }
    }

    private var invitation: some View {
        Button {
            app.haptics.selection()
            app.isShowingPlanner = true
        } label: {
            HStack(spacing: LMSpace.s) {
                ZStack {
                    Circle().strokeBorder(LMColor.focus.opacity(0.6), style: StrokeStyle(lineWidth: 1.25, dash: [2, 4]))
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LMColor.focus)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan your day, hour by hour")
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textPrimary)
                    Text("It becomes an orbit you can follow.")
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LMColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LMSpace.m)
            .padding(.vertical, LMSpace.s)
            .glassCard(radius: 22)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("plan.planDay")
    }

    private func card(_ timeline: DayTimeline) -> some View {
        let focus = timeline.focus
        return HStack(spacing: LMSpace.s) {
            Button {
                app.haptics.selection()
                app.isShowingDayOrbit = true
            } label: {
                VStack(alignment: .leading, spacing: LMSpace.xs) {
                    if !typeSize.isAccessibilitySize {
                        MiniOrbitRoute(blocks: timeline.blocks)
                            .frame(height: 34)
                    }
                    line(timeline)
                }
                .padding(.vertical, 2)
                // Full width even when the route steps aside for large text.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spoken(timeline)))
            .accessibilityHint(Text("Opens today's orbit"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("plan.orbit")

            if let focus, !typeSize.isAccessibilitySize {
                Button {
                    app.haptics.selection()
                    app.requestPlanFocus(focus.id, source: "plan_tab")
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(timeline.current != nil ? LMColor.onAccent : LMColor.starlightLabel)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(timeline.current != nil ? LMColor.calm : LMColor.starlightFill))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(Text("Focus on \(focus.title)"))
                .accessibilityIdentifier("plan.orbitFocus")
            }
        }
        .padding(.horizontal, LMSpace.m)
        .padding(.vertical, LMSpace.s)
        .glassCard(radius: 22, tint: timeline.current != nil ? LMColor.calm : nil)
    }

    @ViewBuilder
    private func line(_ timeline: DayTimeline) -> some View {
        if let current = timeline.current {
            HStack(spacing: 6) {
                Text(current.title).lineLimit(1)
                Text("·").foregroundStyle(LMColor.textTertiary)
                Text("\(PlanFormat.countdown(current.end.timeIntervalSince(timeline.now))) left")
                    .monospacedDigit()
                    .foregroundStyle(LMColor.calm)
                    .layoutPriority(1)
            }
            .font(LMFont.callout)
            .foregroundStyle(LMColor.textPrimary)
        } else if let next = timeline.next {
            HStack(spacing: 6) {
                Text(next.title).lineLimit(1)
                Text("·").foregroundStyle(LMColor.textTertiary)
                Text("in \(PlanFormat.countdown(next.start.timeIntervalSince(timeline.now)))")
                    .monospacedDigit()
                    .foregroundStyle(LMColor.focus)
                    .layoutPriority(1)
            }
            .font(LMFont.callout)
            .foregroundStyle(LMColor.textPrimary)
        } else {
            Text(timeline.litCount == timeline.blocks.count
                 ? String(localized: "Every stop is lit. A bright day.") : String(localized: "Today's orbit is complete."))
                .font(LMFont.callout)
                .foregroundStyle(LMColor.reward)
        }
    }

    private func spoken(_ timeline: DayTimeline) -> String {
        var parts = [String(localized: "Today's orbit"),
                     String(localized: "\(timeline.litCount) of \(timeline.blocks.count) blocks lit")]
        if let current = timeline.current {
            parts.append(String(localized: "Now: \(current.title)"))
            parts.append(PlanFormat.status(current, in: timeline))
        } else if let next = timeline.next {
            parts.append(String(localized: "Next: \(next.title), at \(PlanFormat.time(next.start))"))
        }
        return parts.joined(separator: ", ")
    }
}
