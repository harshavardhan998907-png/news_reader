import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/saved_articles_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isFirebaseInitialized = false;
  String? initializationError;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    isFirebaseInitialized = true;
  } catch (e) {
    initializationError = e.toString();
  }

  runApp(NewsReaderApp(
    isFirebaseInitialized: isFirebaseInitialized,
    initializationError: initializationError,
  ));
}

class NewsReaderApp extends StatelessWidget {
  final bool isFirebaseInitialized;
  final String? initializationError;

  const NewsReaderApp({
    super.key,
    required this.isFirebaseInitialized,
    this.initializationError,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'News Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), // Slate/Navy Blue
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      home: isFirebaseInitialized
          ? const AuthGate()
          : FirebaseErrorScreen(error: initializationError),
    );
  }
}

/// The AuthGate listens to Firebase Auth state changes.
/// Automatically directs user to HomeScreen if authenticated,
/// or LoginScreen if not authenticated.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // While Firebase is restoring auth state from cache/storage
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading News Reader...'),
                ],
              ),
            ),
          );
        }

        // If user is authenticated, ensure saved articles service is scoped to user's UID
        if (snapshot.hasData && snapshot.data != null) {
          SavedArticlesService().init(userId: snapshot.data!.uid);
          return const HomeScreen();
        }

        // When unauthenticated, clear in-memory articles and render LoginScreen
        SavedArticlesService().clearInMemory();
        return const LoginScreen();
      },
    );
  }
}

/// Fallback screen in case Firebase initialization fails
class FirebaseErrorScreen extends StatelessWidget {
  final String? error;

  const FirebaseErrorScreen({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Firebase Initialization Failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                error ?? 'An unknown error occurred while initializing Firebase.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
