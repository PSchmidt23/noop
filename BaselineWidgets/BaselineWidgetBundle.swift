import WidgetKit
import SwiftUI

/// The `BaselineWidgets` extension's entry point: the Home Screen HRV widget (small and medium) and the
/// Lock Screen readiness accessories. Both read the one `BaselineWidgetSnapshot` the app publishes into
/// the App Group; nothing here opens the store or imports a NOOP package.
@main
struct BaselineWidgetBundle: WidgetBundle {
    var body: some Widget {
        HRVWidget()
        ReadinessLockWidget()
    }
}
