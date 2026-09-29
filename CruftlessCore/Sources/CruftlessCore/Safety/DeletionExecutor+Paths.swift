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
            policyGeneration: request.policyGeneration,
            gradleCacheRiskAcknowledgement: request.gradleCacheRiskAcknowledgement,
            revalidate: { [protectedPathsStore, policyGenerationAuthority] in
                let policy = protectedPathsStore.protectedPaths()
                if request.gradleCacheRiskAcknowledgement != nil {
                    return Self.revalidateGradleCacheRequest(
                        request,
                        protectedPaths: policy,
                        policyGenerationAuthority: policyGenerationAuthority
                    )
                }
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

    private static func revalidateGradleCacheRequest(
        _ request: PathDeletionRequest,
        protectedPaths: ProtectedPaths,
        policyGenerationAuthority: PolicyGenerationAuthority
    ) -> Bool {
        guard let acknowledgement = request.gradleCacheRiskAcknowledgement,
              acknowledgement.matches(
                  request.target,
                  affectedLocationIDs: request.affectedLocationIds,
                  planPolicyGeneration: request.policyGeneration
              ),
              policyGenerationAuthority.currentGeneration == request.policyGeneration
        else { return false }
        do {
            _ = try PathGuard(roots: [], protectedPaths: protectedPaths)
                .validateGradleCacheEntry(request.validatedPath.url)
            return DirectoryWalker
                .walk(url: request.validatedPath.url, inodeSet: InodeSet())
                .skippedMountCount == 0
        } catch {
            return false
        }
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
