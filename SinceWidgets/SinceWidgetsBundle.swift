import SwiftUI
import WidgetKit

@main
struct SinceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CounterWidget()
        CounterGridWidget()
        CounterListWidget()
        CountdownWidget()
        CountdownGridWidget()
        CountdownListWidget()
        ParcelsWidget()
        CountdownLiveActivity()
    }
}
