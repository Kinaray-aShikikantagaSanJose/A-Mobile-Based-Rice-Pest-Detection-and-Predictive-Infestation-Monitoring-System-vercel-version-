// Client-side copies of the server's rules for review texts
// (POST /sync/scans/{id}/review), so the reviewer sees the problem before
// sending. Messages are English (the same text the server sends) and are
// translated where shown.

String _normalize(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

int _words(String s) => s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;

/// Why the reviewer note can't be sent yet, or null when it is fine:
/// at least 10 characters and 2 words, and the reviewer's own words (not a
/// copy of the diagnosis or the guidance the farmer reads).
String? reviewerNoteProblem(String note, {String diagnosis = '', String guidance = ''}) {
  final n = note.trim();
  if (n.length < 10 || _words(n) < 2) {
    return 'Add a reviewer note: what you checked and why you chose this level.';
  }
  final norm = _normalize(n);
  if ((diagnosis.trim().isNotEmpty && norm == _normalize(diagnosis)) ||
      (guidance.trim().isNotEmpty && norm == _normalize(guidance))) {
    return 'The reviewer note must be your own note, not a copy of the diagnosis or guidance.';
  }
  return null;
}

/// Why a Return reason (at least 6 characters, 2 words) or an Escalate
/// reason (at least 10 characters, 2 words) can't be sent yet, or null.
String? decisionReasonProblem(String reason, {required bool escalate}) {
  final r = reason.trim();
  if (escalate) {
    return r.length < 10 || _words(r) < 2 ? 'Explain the escalation in a sentence the agriculturist can use.' : null;
  }
  return r.length < 6 || _words(r) < 2 ? 'Write a clear reason the farmer can act on.' : null;
}
