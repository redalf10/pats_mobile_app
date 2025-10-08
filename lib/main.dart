import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'views/home_screen.dart';
import 'providers/theme_provider.dart';
import 'config/theme_config.dart';
import 'views/login_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/auth_service.dart';
import 'services/audio_service.dart';
import 'services/network_service.dart';
import 'services/local_db_service.dart';
import 'viewmodels/walkie_talkie_viewmodel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize Firebase-backed LocalDbService
  final dbService = LocalDbService();
  await dbService.init();

  runApp(MyApp(dbService: dbService));
}

class MyApp extends StatelessWidget {
  final LocalDbService dbService;

  const MyApp({super.key, required this.dbService});

  @override
  Widget build(BuildContext context) {
    // Provide a way for the viewmodel to access current auth user without direct import
    WalkieTalkieViewModel.globalAuthGetter =
        () => AuthService.instance.currentUser;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider<AudioService>(create: (_) => AudioService()),
        Provider<NetworkService>(create: (_) => NetworkService()),
        Provider<LocalDbService>(create: (_) => dbService),
        ChangeNotifierProvider<WalkieTalkieViewModel>(
          create: (context) {
            final audio = context.read<AudioService>();
            final network = context.read<NetworkService>();
            final localDb = context.read<LocalDbService>();
            String fallbackName =
                'User ${DateTime.now().millisecondsSinceEpoch % 1000}';
            String name;
            try {
              name =
                  AuthService.instance.currentUser?.displayName ?? fallbackName;
            } catch (_) {
              name = fallbackName;
            }
            final viewModel = WalkieTalkieViewModel(
              userName: name,
              audioService: audio,
              networkService: network,
              localDbService: localDb,
            );
            viewModel.initialize().catchError((error) {
              // ignore: avoid_print
              print('Initialization error: $error');
            });
            return viewModel;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'P.A.T.S',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: _buildHomeWithAuthFallback(),
          );
        },
      ),
    );
  }
}

Widget _buildHomeWithAuthFallback() {
  try {
    final stream = AuthService.instance.authStateChanges();
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  } catch (_) {
    // If Firebase/Auth is unavailable, fall back to HomeScreen so app remains usable
    return const HomeScreen();
  }
}
