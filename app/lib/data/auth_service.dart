import 'package:firebase_auth/firebase_auth.dart';

class AuthUser {
  final String uid;
  final String email;
  final bool emailVerified;
  const AuthUser(this.uid, this.email, this.emailVerified);
}

class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}

/// Thin wrapper over Firebase Authentication with user-friendly errors.
class AuthService {
  final FirebaseAuth? _injected;
  // Resolved lazily so tests can subclass without initialising Firebase.
  late final FirebaseAuth _auth = _injected ?? FirebaseAuth.instance;
  AuthService([FirebaseAuth? auth]) : _injected = auth;

  AuthUser? _map(User? u) => u == null ? null : AuthUser(u.uid, u.email ?? '', u.emailVerified);

  AuthUser? get current => _map(_auth.currentUser);
  Stream<AuthUser?> changes() => _auth.userChanges().map(_map);

  Future<AuthUser> signIn(String email, String password) =>
      _guard(() async => _map((await _auth.signInWithEmailAndPassword(email: email.trim(), password: password)).user)!);

  Future<AuthUser> register(String email, String password) => _guard(() async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await cred.user?.sendEmailVerification();
    return _map(cred.user)!;
  });

  Future<void> resendVerification() => _guard(() async => _auth.currentUser?.sendEmailVerification());

  Future<AuthUser?> reload() => _guard(() async {
    await _auth.currentUser?.reload();
    // The security rules read email_verified from the ID token, so fetch a
    // fresh token once verified instead of waiting for the hourly refresh.
    if (_auth.currentUser?.emailVerified ?? false) await _auth.currentUser!.getIdToken(true);
    return _map(_auth.currentUser);
  });

  Future<void> resetPassword(String email) => _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> signOut() => _auth.signOut();

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'invalid-email' => 'Enter a valid email address.',
        'user-disabled' => 'This account has been disabled. Contact the administrator.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Incorrect email or password.',
        'email-already-in-use' => 'An account already exists for this email. Try signing in.',
        'weak-password' => 'Choose a stronger password (at least 8 characters).',
        'too-many-requests' => 'Too many attempts. Please wait a moment and try again.',
        'network-request-failed' => 'No internet connection. Check your network and retry.',
        _ => e.message ?? 'Authentication failed (${e.code}).',
      });
    }
  }
}
