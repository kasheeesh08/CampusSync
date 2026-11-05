import 'package:campussync/data/registration_errors.dart';
import 'package:campussync/data/repository.dart';
import 'package:campussync/domain/models.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseException fx(String code) => FirebaseException(plugin: 'cloud_firestore', code: code, message: 'raw $code details');

// Exact text the web build produced for a denied transaction (seen in the Chrome E2E run).
const webWrapped = "Error: Dart exception: [cloud_firestore/permission-denied] \n"
    "evaluation error at L136:21 for 'get' @ L136, false for 'get' @ L136";

void main() {
  group('firestoreErrorCode', () {
    test('reads FirebaseException codes', () {
      expect(firestoreErrorCode(fx('permission-denied')), 'permission-denied');
      expect(firestoreErrorCode(fx('unavailable')), 'unavailable');
    });
    test('reads codes from web-wrapped transaction errors', () {
      expect(firestoreErrorCode(webWrapped), 'permission-denied');
      expect(firestoreErrorCode(Exception('Dart exception: [cloud_firestore/unavailable] Failed to get document because the client is offline.')), 'unavailable');
    });
    test('returns null for unrelated errors', () {
      expect(firestoreErrorCode(Exception('boom')), isNull);
      expect(firestoreErrorCode(StateError('permission-denied mentioned in prose')), isNull, reason: 'only the [cloud_firestore/…] form counts');
    });
  });

  group('classifyRegistrationError', () {
    test('a denied claim check means another account holds the SAP ID', () {
      expect(classifyRegistrationError(fx('permission-denied'), duringWrite: false).kind, RegistrationFailure.duplicateSapId);
      expect(classifyRegistrationError(webWrapped, duringWrite: false).kind, RegistrationFailure.duplicateSapId);
    });
    test('a denied write (after the claim re-check) means the details were rejected, not a duplicate', () {
      expect(classifyRegistrationError(fx('permission-denied'), duringWrite: true).kind, RegistrationFailure.rejectedDetails);
      expect(classifyRegistrationError(webWrapped, duringWrite: true).kind, RegistrationFailure.rejectedDetails);
    });
    test('offline and timeouts are network failures', () {
      for (final c in ['unavailable', 'deadline-exceeded']) {
        expect(classifyRegistrationError(fx(c), duringWrite: false).kind, RegistrationFailure.network);
        expect(classifyRegistrationError(fx(c), duringWrite: true).kind, RegistrationFailure.network);
      }
    });
    test('anything else is unexpected and reports only the code', () {
      final e = classifyRegistrationError(fx('internal'), duringWrite: true);
      expect(e.kind, RegistrationFailure.unexpected);
      expect(e.message, contains('(internal)'));
      expect(classifyRegistrationError(Exception('boom'), duringWrite: false).kind, RegistrationFailure.unexpected);
    });
    test('messages never leak raw Firestore or security-rule text', () {
      for (final e in [fx('permission-denied'), webWrapped, fx('unavailable'), fx('internal')]) {
        for (final w in [false, true]) {
          final m = classifyRegistrationError(e, duringWrite: w).message;
          expect(m, isNot(contains('evaluation error')));
          expect(m, isNot(contains('raw ')));
          expect(m, isNot(contains('cloud_firestore')));
        }
      }
    });
    test('is a RepositoryException, so existing UI error handling shows it', () {
      expect(RegistrationException(RegistrationFailure.network), isA<RepositoryException>());
      expect(RegistrationException(RegistrationFailure.duplicateSapId).message, startsWith('This SAP ID is already registered'));
    });
  });

  group('registration groups', () {
    const divB = AcademicGroup(id: 'g-b', type: 'division', academicYearId: 'ay', semester: 5, label: 'Div B');
    test('an empty answer from the server is returned as "none configured"', () {
      expect(checkedRegistrationGroups(const [], fromCache: false), isEmpty);
    });
    test('an empty answer from the offline cache means the server was not reached', () {
      expect(() => checkedRegistrationGroups(const [], fromCache: true), throwsA(isA<ServerUnreachableException>()));
    });
    test('cached groups are still usable offline', () {
      expect(checkedRegistrationGroups(const [divB], fromCache: true), [divB]);
    });
    test('isNetworkError covers connection failures only', () {
      expect(isNetworkError(const ServerUnreachableException()), isTrue);
      expect(isNetworkError(fx('unavailable')), isTrue);
      expect(isNetworkError(fx('deadline-exceeded')), isTrue);
      expect(isNetworkError(fx('permission-denied')), isFalse);
      expect(isNetworkError(Exception('boom')), isFalse);
    });
  });
}
