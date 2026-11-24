#if DEBUG
    import CruftlessCore
    import CruftlessFixtures
    import Darwin

    extension AccessListModel {
        /// A list over `areas` that touches nothing on disk; with `failing`, that area's request comes back unavailable.
        static func preview(_ areas: [AccessAreaSummary], failing: ProtectedArea? = nil) -> AccessListModel {
            let model = AccessListModel(service: .preview(areas, outcome: failing == nil ? .allowed : .unavailable(errno: ENOENT)))
            if let failing {
                Task {
                    await model.refresh()
                    model.allow(failing)
                }
            }
            return model
        }

        /// A list whose request for `requesting` never gets an answer, so it stays in flight.
        static func previewAwaitingAnswer(_ areas: [AccessAreaSummary], requesting: ProtectedArea) -> AccessListModel {
            let model = AccessListModel(service: .previewAwaitingAnswer(areas))
            Task {
                await model.refresh()
                model.allow(requesting)
            }
            return model
        }
    }
#endif
