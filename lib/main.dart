// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Uygulama içi sayfalar
import 'core/services/notification_service.dart';
import 'features/auth/pages/login_page.dart';
import 'navigation/pages/navigation_page.dart';

/// Supabase URL ve KEY
/// Eğer build sırasında --dart-define ile verilirse onlar kullanılır.
/// Verilmezse default değerler devreye girer.
const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://tlwqekucboufnjvzmydb.supabase.co',
);

const String kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRsd3Fla3VjYm91Zm5qdnpteWRiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAxNTQ4NDEsImV4cCI6MjA2NTczMDg0MX0.UJ_9Rn5gCpDU7GdesVRMgBl5tkLw9k2l28j84Ij_prk',  // <-- kendi key'in
);

Future<void> main() async {
  // Flutter engine başlatılır (async işlemler için gerekli)
  WidgetsFlutterBinding.ensureInitialized();

  /// Supabase uygulama başında initialize edilir
  await Supabase.initialize(
    url: kSupabaseUrl.trim(),
    anonKey: kSupabaseAnonKey.trim(),

    /// Debug sadece development ortamında açık olur
    debug: !const bool.fromEnvironment('dart.vm.product'),
  );

  /// Uygulama başlatılır
  runApp(const MyApp());

  /// Notification sistemi UI çizildikten sonra başlatılır
  /// (Bu sayede açılışta kasma azalır)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService().init();
  });
}

/// Ana uygulama widget'ı
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      /// Debug banner kapalı
      debugShowCheckedModeBanner: false,

      /// Çoklu dil desteği
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      /// Desteklenen diller
      supportedLocales: const [
        Locale('tr'),
        Locale('en'),
      ],

      /// Varsayılan dil
      locale: const Locale('tr'),

      /// Tema (şu an sabit açık tema)
      themeMode: ThemeMode.light,
      theme: ThemeData.light(),

      /// İlk açılış yönlendirme
      home: const AuthGate(),
    );
  }
}

/// Kullanıcının giriş yapıp yapmadığını kontrol eder
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Login kontrolü sadece bir kez çalışır
  late final Future<bool> _loginCheckFuture;

  @override
  void initState() {
    super.initState();

    /// SharedPreferences üzerinden login kontrolü başlatılır
    _loginCheckFuture = _checkLoginStatus();
  }

  /// Kullanıcının login durumu kontrol edilir
  Future<bool> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();

    /// Kullanıcı ID
    final userId = prefs.getInt('user_id');

    /// Login flag
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

    /// İkisi de varsa kullanıcı giriş yapmış kabul edilir
    return userId != null && isLoggedIn;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loginCheckFuture,

      builder: (context, snapshot) {
        /// Veri henüz gelmediyse loading göster
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen();
        }

        /// Hata varsa kullanıcıya göster
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('Başlangıç kontrolü sırasında bir hata oluştu.'),
            ),
          );
        }

        /// Login durumu
        final isLoggedIn = snapshot.data ?? false;

        /// Giriş yapılmışsa ana sayfa, değilse login sayfası
        return isLoggedIn
            ? const NavigationPage()
            : const LoginPage();
      },
    );
  }
}

/// Basit loading ekranı
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        /// Dairesel yüklenme animasyonu
        child: CircularProgressIndicator(),
      ),
    );
  }
}