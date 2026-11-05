/// Form validators. Each returns `null` when valid or a user-facing message.
class Validators {
  static String? required(String? v, String field) => (v == null || v.trim().isEmpty) ? '$field is required.' : null;

  static String? email(String? v) {
    final r = required(v, 'Email');
    if (r != null) return r;
    final ok = RegExp(r'^[\w.+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$').hasMatch(v!.trim());
    return ok ? null : 'Enter a valid email address, e.g. name@example.com.';
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Password is required.';
    if (v.length < 8) return 'Password must be at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Use at least one letter and one number.';
    }
    return null;
  }

  static String? confirmPassword(String? v, String original) {
    if (v == null || v.isEmpty) return 'Please re-enter your password.';
    return v == original ? null : 'Passwords do not match.';
  }

  static String? signInPassword(String? v) => (v == null || v.isEmpty) ? 'Password is required.' : null;

  /// SAP IDs are numeric identifiers; length is checked loosely because the
  /// institution's exact format is not specified in the reference material.
  static String? sapId(String? v) {
    final r = required(v, 'SAP ID');
    if (r != null) return r;
    final s = v!.trim();
    if (!RegExp(r'^\d+$').hasMatch(s)) return 'SAP ID must contain digits only.';
    if (s.length < 8 || s.length > 12) return 'SAP ID must be 8 to 12 digits long.';
    return null;
  }

  /// Roll numbers follow the division letter + 3 digits pattern (e.g. B001).
  static String? rollNumber(String? v, {String? division}) {
    final r = required(v, 'Roll number');
    if (r != null) return r;
    final s = v!.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]\d{3}$').hasMatch(s)) return 'Use your division letter followed by 3 digits, e.g. B001.';
    if (division != null && s[0] != division.toUpperCase()) {
      return 'Roll number should start with $division for Division $division.';
    }
    return null;
  }

  static String? displayName(String? v) {
    final r = required(v, 'Name');
    if (r != null) return r;
    final s = v!.trim();
    if (s.length < 2) return 'Name must be at least 2 characters.';
    if (s.length > 50) return 'Name must be at most 50 characters.';
    if (!RegExp(r"^[A-Za-z][A-Za-z .'\-]*$").hasMatch(s)) return 'Use letters, spaces, dots, hyphens or apostrophes.';
    return null;
  }

  static String? optionalUrl(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final u = Uri.tryParse(v.trim());
    if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) {
      return 'Enter a full link starting with https://';
    }
    return null;
  }

  static String? dateRange(DateTime? start, DateTime? end) {
    if (start != null && end != null && end.isBefore(start)) return 'End date cannot be before the start date.';
    return null;
  }

  static String? title(String? v, {int max = 140}) {
    final r = required(v, 'Title');
    if (r != null) return r;
    return v!.trim().length > max ? 'Title must be at most $max characters.' : null;
  }
}
