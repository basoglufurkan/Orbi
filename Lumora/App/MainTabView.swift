import SwiftUI

/// The five destinations behind the floating orbit bar. Only the selected
/// screen is alive, so hidden canvases never render.
struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            Group {
                switch app.selectedTab {
                case .today: HomeView()
                case .plan: PlanView()
                case .universe: UniverseExplorerView()
                case .odyssey: OdysseyView()
                case .insights: InsightsView()
                }
            }
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBarScrim()

            OrbitBar(selection: $app.selectedTab)
                .padding(.horizontal, LMSpace.l)
                .readableColumn(560)
                .padding(.bottom, 4)
        }
        .pellPeekHost(.main)
        // A note belongs to the screen it was said on; each tab has its own hello.
        .onAppear { Telemetry.log(.screenView(screen: app.selectedTab.rawValue)) }
        .onChange(of: app.selectedTab) { _, tab in
            Telemetry.log(.screenView(screen: tab.rawValue))
            app.pell.clear(scope: .main)
            // A Year in review link is only for this visit to Insights.
            if tab != .insights { app.pendingYearInReview = false }
            switch tab {
            case .universe: app.pell.offer(.universe)
            case .insights: app.pell.offer(.insights)
            case .today, .plan, .odyssey: break
            }
        }
        .animation(LMSpring.settle, value: app.selectedTab)
        .sheet(isPresented: $app.isShowingTasks, onDismiss: {
            // The focus flow is a full-screen cover; it can only appear once the sheet is gone.
            if let id = app.focusAfterTasks {
                app.focusAfterTasks = nil
                app.beginFocus(taskID: id)
            }
            app.runPendingPlanFocus()
        }) {
            TasksView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $app.isShowingSettings, onDismiss: app.runPendingPlanFocus) {
            SettingsView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $app.isShowingPlanner, onDismiss: app.runPendingPlanFocus) {
            DayPlannerView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $app.isShowingHabits, onDismiss: app.runPendingHabitFocus) {
            HabitsView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $app.isShowingCollection) {
            CollectionView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .fullScreenCover(isPresented: $app.isShowingDayOrbit, onDismiss: {
            app.runPendingPlanFocus()
            app.runPendingHabitFocus()
        }) {
            DayOrbitView()
                .preferredColorScheme(app.colorScheme)
        }
    }
}

/// Content scrolling under the floating orbit bar fades into the sky
/// instead of showing its edges around and below the bar. It starts just
/// above the bar, clear of the buttons and cards that rest on it.
private struct TabBarScrim: View {
    var body: some View {
        GeometryReader { geo in
            // From just above the bar down through the home indicator.
            let inset = geo.safeAreaInsets.bottom
            LinearGradient(stops: [.init(color: LMColor.bgBase.opacity(0), location: 0),
                                   .init(color: LMColor.bgBase.opacity(0.75), location: 0.3),
                                   .init(color: LMColor.bgBase.opacity(0.92), location: 0.6),
                                   .init(color: LMColor.bgBase.opacity(0.96), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 72 + inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: inset)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
