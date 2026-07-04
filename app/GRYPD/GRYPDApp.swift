import SwiftUI
import SwiftData
import UIKit

@main
struct GRYPDApp: App {
    @UIApplicationDelegateAdaptor(OrientationLockDelegate.self) private var delegate
    @State private var catalog = CatalogStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .environment(catalog)
                .environment(router)
                .task {
                    // Debounced remote refresh happens here once remoteBaseURL is set.
                    await catalog.refresh()
                }
        }
        .modelContainer(for: [WorkoutLog.self, MoveEntry.self, SetEntry.self])
    }
}

/// The app's four tabs. `AppRouter` owns the selection so any screen can switch
/// tabs (e.g. the empty History state jumping to Browse).
enum AppTab: Hashable {
    case browse, history, progress, settings
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .browse
}

/// Locks iPhone to portrait while allowing all orientations on iPad.
/// `UIRequiresFullScreen` is deprecated in iOS 26, so all orientations are
/// declared in the Info.plist (to satisfy App Store validation) and narrowed
/// at runtime here.
private final class OrientationLockDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }
}

struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    // Gates the onboarding cover; set true once the user finishes or skips.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Browse", systemImage: "square.grid.2x2", value: AppTab.browse) {
                BrowseView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                ProgressionView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
        }
    }
}
