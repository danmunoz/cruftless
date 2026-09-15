import SwiftUI

struct LoadStateView<Content: View>: View {
    let isLoading: Bool
    let loadingTitle: String
    let error: String?
    let errorTitle: String
    let isEmpty: Bool
    let emptySymbol: String
    let emptyTitle: String
    let emptyMessage: String
    let retry: () -> Void
    @ViewBuilder var content: Content

    init(
        isLoading: Bool,
        loadingTitle: String,
        error: String?,
        errorTitle: String,
        isEmpty: Bool,
        emptySymbol: String,
        emptyTitle: String,
        emptyMessage: String,
        retry: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isLoading = isLoading
        self.loadingTitle = loadingTitle
        self.error = error
        self.errorTitle = errorTitle
        self.isEmpty = isEmpty
        self.emptySymbol = emptySymbol
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.retry = retry
        self.content = content()
    }

    var body: some View {
        if isLoading {
            PopoverPlaceholder(symbol: "hourglass", title: loadingTitle)
        } else if let error {
            PopoverPlaceholder(symbol: "exclamationmark.triangle", title: errorTitle, message: error) {
                Button("Try Again", action: retry)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        } else if isEmpty {
            PopoverPlaceholder(symbol: emptySymbol, title: emptyTitle, message: emptyMessage)
        } else {
            content
        }
    }
}

#if DEBUG
    #Preview("LoadStateView: Loading") {
        LoadStateView(
            isLoading: true,
            loadingTitle: "Reading simulators…",
            error: nil,
            errorTitle: "Couldn't read simulators",
            isEmpty: false,
            emptySymbol: "iphone.slash",
            emptyTitle: "No simulators",
            emptyMessage: "CoreSimulator has no devices on this Mac.",
            retry: {},
            content: { Text("Content") }
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("LoadStateView: Error") {
        LoadStateView(
            isLoading: false,
            loadingTitle: "Reading simulators…",
            error: "CoreSimulator: permission denied",
            errorTitle: "Couldn't read simulators",
            isEmpty: false,
            emptySymbol: "iphone.slash",
            emptyTitle: "No simulators",
            emptyMessage: "CoreSimulator has no devices on this Mac.",
            retry: {},
            content: { Text("Content") }
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("LoadStateView: Empty") {
        LoadStateView(
            isLoading: false,
            loadingTitle: "Reading simulators…",
            error: nil,
            errorTitle: "Couldn't read simulators",
            isEmpty: true,
            emptySymbol: "iphone.slash",
            emptyTitle: "No simulators",
            emptyMessage: "CoreSimulator has no devices on this Mac.",
            retry: {},
            content: { Text("Content") }
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("LoadStateView: Content") {
        LoadStateView(
            isLoading: false,
            loadingTitle: "Reading simulators…",
            error: nil,
            errorTitle: "Couldn't read simulators",
            isEmpty: false,
            emptySymbol: "iphone.slash",
            emptyTitle: "No simulators",
            emptyMessage: "CoreSimulator has no devices on this Mac.",
            retry: {},
            content: { Text("Content").padding() }
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
