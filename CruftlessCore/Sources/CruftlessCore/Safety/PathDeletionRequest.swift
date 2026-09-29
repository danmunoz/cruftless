import Foundation

package struct PathDeletionRequest: Sendable {
    let target: DeletionTarget
    let validatedPath: ValidatedPath
    let fingerprint: Fingerprint
    let bytes: Int64
    let precondition: DeletionPrecondition?
    let affectedLocationIds: Set<String>
    let policyGeneration: UInt64
    let gradleCacheRiskAcknowledgement: GradleCacheRiskAcknowledgement?
    let revalidate: @Sendable () -> Bool

    package init(
        target: DeletionTarget,
        validatedPath: ValidatedPath,
        fingerprint: Fingerprint,
        bytes: Int64,
        precondition: DeletionPrecondition?,
        affectedLocationIds: Set<String>,
        policyGeneration: UInt64 = 0,
        gradleCacheRiskAcknowledgement: GradleCacheRiskAcknowledgement? = nil,
        revalidate: @escaping @Sendable () -> Bool = { true }
    ) {
        self.target = target
        self.validatedPath = validatedPath
        self.fingerprint = fingerprint
        self.bytes = bytes
        self.precondition = precondition
        self.affectedLocationIds = affectedLocationIds
        self.policyGeneration = policyGeneration
        self.gradleCacheRiskAcknowledgement = gradleCacheRiskAcknowledgement
        self.revalidate = revalidate
    }
}
