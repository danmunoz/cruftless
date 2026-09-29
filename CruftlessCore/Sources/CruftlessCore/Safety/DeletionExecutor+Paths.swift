import Foundation

extension DeletionExecutor {
    func executePath(_ request: PathDeletionRequest) async -> ItemOutcome {
        report(DeletionProgress(verb: .clear, targetName: request.target.name, phase: .mutating))
        let location = LocationCatalog.all.first { request.affectedLocationIds.contains($0.id) }
        let pathRequest = PathDeletionRequest(
            target: request.target,
            validatedPath: request.validatedPath,
            fingerprint: request.fingerprint,
            bytes: request.bytes,
            precondition: request.precondition,
            affectedLocationIds: request.affectedLocationIds,
            revalidate: { [protectedPathsStore] in
                let policy = protectedPathsStore.protectedPaths()
                guard !policy.isProtected(request.validatedPath.url),
                      !policy.containsProtectedDescendant(in: request.validatedPath.url)
                else { return false }
                guard let location else {
                    let roots = request.validatedPath.allowlistedRootPaths
                        .map { URL(fileURLWithPath: $0, isDirectory: true) }
                    return Self.validate(
                        request.validatedPath,
                        roots: roots,
                        protectedPaths: policy
                    )
                }
                guard location.mutationPolicy != .readOnly else { return false }
                if location.mutationPolicy == .simctl { return request.precondition != nil }
                return Self.validate(
                    request.validatedPath,
                    roots: location.resolveRoots(),
                    protectedPaths: policy
                )
            }
        )
        return await Self.offCooperativePool { Self.performPathDeletion(pathRequest) }
    }

    private static func validate(
        _ path: ValidatedPath,
        roots: [URL],
        protectedPaths: ProtectedPaths
    ) -> Bool {
        let pathGuard = PathGuard(roots: roots, protectedPaths: protectedPaths)
        do {
            if path.isRoot {
                _ = try pathGuard.validateRoot(path.url)
            } else {
                _ = try pathGuard.validate(path.url)
            }
            return true
        } catch {
            return false
        }
    }
}
