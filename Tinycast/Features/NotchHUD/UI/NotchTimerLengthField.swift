import SwiftUI

/// What the reader has typed for a custom timer; the dialog's caller reads it back on confirm.
@Observable
final class NotchTimerLengthState {
    var text = ""

    var minutes: Int? { NotchTimerPreset.minutes(from: text) }
}

struct NotchTimerLengthField: View {
    @Bindable var state: NotchTimerLengthState
    let onSubmit: () -> Void

    var body: some View {
        TextField("Minutes", text: $state.text)
            .dialogTextField()
            .onSubmit(onSubmit)
    }
}
