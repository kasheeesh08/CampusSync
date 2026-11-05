import 'package:firebase_core/firebase_core.dart';

import '../domain/models.dart';
import 'repository.dart';

/// Why a registration (profile + SAP ID claim) was not saved.
enum RegistrationFailure { duplicateSapId, rejectedDetails, unverifiedEmail, network, unexpected }

/// A registration failure with a student-facing message. Raw Firestore text
/// (which can include security-rule details) is never shown.
class RegistrationException extends RepositoryException {
  final RegistrationFailure kind;
  final String? code;
  RegistrationException(this.kind, {this.code}) : super(_messages(kind, code));

  static String _messages(RegistrationFailure kind, String? code) => switch (kind) {
    RegistrationFailure.duplicateSapId =>
      'This SAP ID is already registered to another account. If it is yours, contact the administrator.',
    RegistrationFailure.rejectedDetails =>
      'The server did not accept these details. Check your name, roll number and division and try again. '
          'If it keeps happening, contact the administrator.',
    RegistrationFailure.unverifiedEmail => 'Verify your email first: open the link we sent you, then tap "I have verified".',
    RegistrationFailure.network => 'Could not reach the server. Check your internet connection and try again. Nothing was saved.',
    RegistrationFailure.unexpected =>
      'Registration failed unexpectedly${code == null ? '' : ' ($code)'}. Please try again or contact the administrator.',
  };
}

final _wrappedCode = RegExp(r'\[cloud_firestore/([a-z-]+)\]');

/// The Firestore error code of [e]: from a [FirebaseException], or parsed from
/// the wrapped text web builds produce for errors inside transactions
/// ("Dart exception: [cloud_firestore/permission-denied] …"). Null if none.
String? firestoreErrorCode(Object e) {
  if (e is FirebaseException) return e.code;
  return _wrappedCode.firstMatch('$e')?.group(1);
}

const _networkCodes = {'unavailable', 'deadline-exceeded'};

/// The server could not be reached and the device cache had nothing to offer.
class ServerUnreachableException extends RepositoryException {
  const ServerUnreachableException() : super('Could not reach the server.');
}

/// True when [e] means "no connection" rather than a refusal or a bug.
bool isNetworkError(Object e) => e is ServerUnreachableException || _networkCodes.contains(firestoreErrorCode(e));

/// Offline, Firestore answers queries from the device cache instead of
/// failing, so an empty cached list says nothing about the server. Only an
/// empty answer from the server means no academic groups are configured.
List<AcademicGroup> checkedRegistrationGroups(List<AcademicGroup> groups, {required bool fromCache}) {
  if (groups.isEmpty && fromCache) throw const ServerUnreachableException();
  return groups;
}

/// Classifies an error from the claim check ([duringWrite] false) or from the
/// write transaction ([duringWrite] true).
///
/// A verified user may read a SAP ID claim only when it is free or their own,
/// so "permission-denied" on the check means another account holds it. On the
/// write it means the rules rejected the profile (the caller re-checks the
/// claim first, to tell a lost race apart from rejected details).
RegistrationException classifyRegistrationError(Object e, {required bool duringWrite}) {
  if (e is RegistrationException) return e;
  final code = firestoreErrorCode(e);
  if (code == 'permission-denied') {
    return RegistrationException(duringWrite ? RegistrationFailure.rejectedDetails : RegistrationFailure.duplicateSapId);
  }
  if (_networkCodes.contains(code)) return RegistrationException(RegistrationFailure.network, code: code);
  return RegistrationException(RegistrationFailure.unexpected, code: code);
}
