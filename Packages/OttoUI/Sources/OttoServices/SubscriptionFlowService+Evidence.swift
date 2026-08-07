import Foundation
import OttoDomain

// The evidence-note methods (spec §5.4, a list since v1.9) - their own file
// because the dispute evidence grew from one field into a small CRUD surface.

extension SubscriptionFlowService {

    /// Adds a note to the open episode's evidence (spec §5.4, a list since
    /// v1.9) - the user coming back from the vendor page with a confirmation
    /// number, or logging the next round of the fight. Empty text is a no-op:
    /// there is nothing to record.
    public func appendCancellationEvidence(
        subscriptionID: UUID,
        text: String,
        now: Date
    ) async throws {
        guard var record = try await cancellations.openEpisode(forSubscription: subscriptionID) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        record.evidenceNotes.append(EvidenceNote(
            id: UUID(), text: trimmed, createdAt: now, updatedAt: now
        ))
        record.updatedAt = now
        try await cancellations.save(record)
    }

    /// Edits one of the open episode's notes in place - a user correcting
    /// their own note is not a state exit. Empty text tombstones the note
    /// deliberately (spec §3.5: removal is a soft delete, never a hard one).
    public func updateCancellationEvidence(
        subscriptionID: UUID,
        noteID: UUID,
        text: String?,
        now: Date
    ) async throws {
        guard var record = try await cancellations.openEpisode(forSubscription: subscriptionID),
              let index = record.evidenceNotes.firstIndex(where: { $0.id == noteID })
        else { return }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            guard record.evidenceNotes[index].text != trimmed else { return }
            record.evidenceNotes[index].text = trimmed
            record.evidenceNotes[index].updatedAt = now
        } else {
            guard record.evidenceNotes[index].deletedAt == nil else { return }
            record.evidenceNotes[index].deletedAt = now
            record.evidenceNotes[index].updatedAt = now
        }
        record.updatedAt = now
        try await cancellations.save(record)
    }
}
