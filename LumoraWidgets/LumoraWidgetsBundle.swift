import SwiftUI
import WidgetKit

@main
struct LumoraWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayProgressWidget()
        DailyGoalWidget()
        RhythmWidget()
        UniverseSnapshotWidget()
        DayOrbitWidget()
        HabitsWidget()
        StandByClockWidget()
        FocusLiveActivity()
        if #available(iOS 18.0, *) {
            FocusControl()
        }
    }
}
