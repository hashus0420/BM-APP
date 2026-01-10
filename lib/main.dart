// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/theme_provider.dart';
import 'pages/login_page.dart';
import 'pages/navigation_page.dart';
import 'services/notification_service.dart';

// --dart-define gelirse onu kullanır; gelmezse defaults çalışır.
const _kUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://tlwqekucboufnjvzmydb.supabase.co',
);
const _kAnon = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRsd3Fla3VjYm91Zm5qdnpteWRiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAxNTQ4NDEsImV4cCI6MjA2NTczMDg0MX0.UJ_9Rn5gCpDU7GdesVRMgBl5tkLw9k2l28j84Ij_prk',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();

  await Supabase.initialize(
    url: _kUrl.trim(),
    anonKey: _kAnon.trim(),
    debug: true,
  );

  // Hızlı teşhis: hangi URL ile açtık
  debugPrint('Supabase URL => ${Uri.tryParse(_kUrl)?.host}');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ThemeProvider())],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('tr'), Locale('en')],
        locale: const Locale('tr'),

        // --- KARANLIK MODU GEÇİCİ OLARAK KAPAT ---
        // Uygulamanın sistem ayarından bağımsız olarak her zaman AÇIK (light) temada açılması için:
        themeMode: ThemeMode.light,
        theme: ThemeData.light(),
        // darkTheme: ThemeData.dark(), // (İSTENİRSE) Şimdilik tamamen devre dışı bıraktık.
        // -----------------------------------------

        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  Future<bool> _isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    final hasId = p.getInt('user_id');
    final flag = p.getBool('is_logged_in') ?? false;
    return hasId != null && flag;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isLoggedIn(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return snap.data! ? const RoleRouter() : const LoginPage();
      },
    );
  }
}

class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  Future<String> _loadRole() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString('role') ?? 'student').toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _loadRole(),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return const NavigationPage();
      },
    );
  }
}
