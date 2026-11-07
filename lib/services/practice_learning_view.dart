import 'writing_practice.dart';
import 'writing_practice_history.dart';
import 'writing_preferences.dart';

/// A local review snapshot, never a training sample or request context.
/// Rebuild before displaying current state; historical preference snapshots
/// and try/reject decisions cannot authorize a learning rule.
class PracticeLearningView {
  final WritingPracticeCase record;
  final int preferenceVersion;
  final List<PracticeLearningCandidate> candidates;
  final List<ConfirmedWritingPreference> confirmed;
  final List<ConfirmedWritingPreference> revoked;

  PracticeLearningView._(this.record, WritingPreferences current)
    : preferenceVersion = current.version,
      candidates = List.unmodifiable([
        for (final observation in record.feedback.observations)
          PracticeLearningCandidate._(
            observation,
            false,
            record.feedbackSource != null,
          ),
        if (record.revisionFeedback case final feedback?)
          for (final observation in feedback.observations)
            PracticeLearningCandidate._(
              observation,
              true,
              record.revisionFeedbackSource != null,
            ),
      ]),
      confirmed = List.unmodifiable(
        current.active.where((item) => item.sourceCaseId == record.id),
      ),
      revoked = List.unmodifiable(
        current.items.where(
          (item) => item.sourceCaseId == record.id && !item.active,
        ),
      );

  /// Reads one fully validated case, then the current preference store. No
  /// source writes, ledger scans, inference, model calls or export are made.
  /// The returned state is a snapshot, not permission for a later model call.
  static Future<PracticeLearningView> load(
    String root,
    String book,
    String caseId,
  ) async {
    final record = await WritingPracticeHistory.loadCase(root, book, caseId);
    final current = await WritingPreferenceStore.load(root, book);
    return PracticeLearningView._(record, current);
  }
}

/// Even when an author separately confirms a preference, model directions
/// remain suggestions. A stored source link is not a verified ledger entry.
class PracticeLearningCandidate {
  final PracticeObservation observation;
  final bool fromRevision;
  final bool hasStoredSource;

  const PracticeLearningCandidate._(
    this.observation,
    this.fromRevision,
    this.hasStoredSource,
  );
}
