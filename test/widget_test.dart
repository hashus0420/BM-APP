// test/myapp_shows_login_when_logged_out_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:msret/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Gerçek ağa gitmeyecek; main.dart'taki sağlık testi try/catch içinde.
    await Supabase.initialize(
      url: 'https://dummy.supabase.co',
      anonKey: 'dummy-anon-key',
    );
  });

  testWidgets('MyApp shows LoginPage when no session', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Giriş Yap'), findsOneWidget);
  });
}
