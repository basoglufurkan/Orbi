import SwiftData
import SwiftUI

/// "Collection": every cosmic artifact, earned or still in orbit. Opens as a
/// sheet over Insights (and from Today's latest artifacts).
struct CollectionView: View {
    enum Filter: Hashable { case all, earned, inOrbit }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AchievementUnlock.unlockedAt, order: .reverse) private var unlocks: [AchievementUnlock]
    @State private var filter: Filter = .all
    @State private var revealed: AchievementDefinition?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        StatsReader { stats, _ in
            ZStack {
                CosmicBackgroundView(mood: .home, light: 0.3, starOpacity: 0.6)
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.m) {
                        HStack(alignment: .top, spacing: LMSpace.s) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Collection")
                                    .font(LMFont.largeTitle)
                                    .foregroundStyle(LMColor.textPrimary)
                                    .accessibilityAddTraits(.isHeader)
                                Text("\(earnedIDs.count) of \(AchievementCatalog.all.count) cosmic artifacts found")
                                    .font(LMFont.callout.weight(.regular))
                                    .foregroundStyle(LMColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(LMColor.textSecondary)
                                    .frame(width: 44, height: 44)
                                    .glassCard(radius: 22)
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel(Text("Close"))
                            .accessibilityIdentifier("collection.close")
                        }
                        .padding(.top, LMSpace.l)

                        if let latest = unlocks.first, let def = latest.definition {
                            featured(def, date: latest.unlockedAt)
                        }

                        CosmicSegmented(options: [(Filter.all, String(localized: "All")),
                                                  (Filter.earned, String(localized: "Earned")),
                                                  (Filter.inOrbit, String(localized: "In orbit"))],
                                        selection: $filter)

                        let items = filtered
                        if items.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LMSpace.s),
                                                     count: typeSize.isAccessibilitySize ? 1 : 2),
                                      spacing: LMSpace.s) {
                                ForEach(items) { def in
                                    let unlock = unlockMap[def.id]
                                    Button {
                                        if unlock != nil {
                                            app.haptics.selection()
                                            revealed = def
                                        }
                                    } label: {
                                        AchievementCardView(definition: def, unlockedAt: unlock?.unlockedAt,
                                                            progress: def.requirement.progress(in: stats))
                                    }
                                    .buttonStyle(PressScaleStyle())
                                    .disabled(unlock == nil)
                                }
                            }
                        }
                        Color.clear.frame(height: LMSpace.l)
                    }
                    .padding(.horizontal, LMSpace.l)
                    .readableColumn()
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(item: $revealed) { def in
            ArtifactRevealView(definition: def, unlockedAt: unlockMap[def.id]?.unlockedAt ?? .now)
        }
        .telemetryScreen("collection")
    }

    private var unlockMap: [String: AchievementUnlock] {
        Dictionary(unlocks.map { ($0.achievementID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var earnedIDs: Set<String> { Set(unlocks.map(\.achievementID)) }

    private var filtered: [AchievementDefinition] {
        switch filter {
        case .all: AchievementCatalog.all
        case .earned: AchievementCatalog.all.filter { earnedIDs.contains($0.id) }
        case .inOrbit: AchievementCatalog.all.filter { !earnedIDs.contains($0.id) }
        }
    }

    private func featured(_ def: AchievementDefinition, date: Date) -> some View {
        Button { revealed = def } label: {
            AdaptiveStack(spacing: LMSpace.m) {
                ArtifactMotifView(motif: def.motif, earned: true).frame(width: 90, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(def.rarity == .common ? String(localized: "Latest") : String(localized: "New · \(def.rarity.label)"),
                                color: LMColor.reward)
                    Text(def.title).font(LMFont.title).foregroundStyle(LMColor.textPrimary)
                    Text(def.detail).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
                .multilineTextAlignment(.leading)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(typeSize.isAccessibilitySize ? LMSpace.m : LMSpace.s)
            .glassCard(radius: typeSize.isAccessibilitySize ? LMRadius.card : 40, border: LMColor.rewardFill.opacity(0.3))
        }
        .buttonStyle(PressScaleStyle())
    }

    private var emptyState: some View {
        VStack(spacing: LMSpace.s) {
            PellView(mood: filter == .earned ? .curious : .proud, showsLabel: false)
            Text(filter == .earned ? String(localized: "Your first artifact surfaces after your first session.")
                                   : String(localized: "Every artifact is yours. Nothing left in orbit."))
                .font(LMFont.body)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LMSpace.xxl)
    }
}
