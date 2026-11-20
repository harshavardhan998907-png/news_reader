import 'package:firebase_auth/firebase_auth.dart';
import 'saved_articles_service.dart';

/// Service responsible for managing Firebase Authentication.
/// Keeps authentication logic decoupled from the UI.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Stream of user authentication state changes.
  /// Emits the current [User] when signed in, or null when signed out.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Gets the currently authenticated user, or null if unauthenticated.
  User? get currentUser => _auth.currentUser;

  /// Registers a new user with [email] and [password].
  /// Trims whitespace from the email before sending to Firebase.
  Future<UserCredential> register({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _getReadableErrorMessage(e);
    } catch (e) {
      throw 'An unexpected error occurred during registration. Please try again.';
    }
  }

  /// Logs in an existing user with [email] and [password].
  /// Trims whitespace from the email before sending to Firebase.
  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _getReadableErrorMessage(e);
    } catch (e) {
      throw 'An unexpected error occurred during login. Please try again.';
    }
  }

  /// Signs out the currently authenticated user and clears cached in-memory articles.
  Future<void> logout() async {
    try {
      SavedArticlesService().clearInMemory();
      await _auth.signOut();
    } catch (e) {
      throw 'Failed to sign out. Please check your connection and try again.';
    }
  }

  /// Maps Firebase error codes to student-friendly, human-readable error messages.
  String _getReadableErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid email or password. Please verify your credentials.';
      case 'email-already-in-use':
        return 'An account already exists for this email address.';
      case 'invalid-email':
        return 'The email address format is invalid.';
      case 'weak-password':
        return 'The password is too weak. Please use at least 6 characters.';
      case 'operation-not-allowed':
        return 'Email/Password sign-in is not enabled in Firebase Console.';
      case 'network-request-failed':
        return 'Network connection error. Please check your internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      default:
        return e.message ?? 'Authentication error occurred. Code: ${e.code}';
    }
  }
}
