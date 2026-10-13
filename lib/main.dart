import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'products_page.dart';
import 'customers_page.dart';
import 'purchase_page.dart';
import 'sales_page.dart';
import 'suppliers_page.dart';
import 'settings_page.dart';
import 'cashbox_page.dart';
import 'dashboard_page.dart';
import 'reports_page.dart';
import 'stock_count_page.dart';
import 'returns_page.dart';
import 'commercial_operations_page.dart';
import 'financial_obligations_page.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

bool get _configured =>
    _supabaseUrl.startsWith('https://') && _publishableKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_configured) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _publishableKey);
  }
  runApp(const InventoryApp());
}

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'إدارة المخازن',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B55)),
          scaffoldBackgroundColor: const Color(0xFFF6F8F7),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF6F8F7),
            foregroundColor: Color(0xFF172A25),
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE4EBE7)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF7F9F8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        home: !_configured ? const SetupPage() : const AuthGate(),
      );
}

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 44),
                        SizedBox(height: 16),
                        Text(
                          'إدارة المخازن والمبيعات',
                          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'الهيكل الأولي جاهز. أضف رابط Supabase ومفتاح '
                          'Publishable لتفعيل تسجيل الدخول.',
                          style: TextStyle(height: 1.6),
                        ),
                        SizedBox(height: 16),
                        SelectableText(
                          'flutter run -d chrome '
                          '--dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co '
                          '--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_KEY',
                          style: TextStyle(fontSize: 12),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'لا تضع service_role أو أي Secret Key داخل التطبيق.',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<AuthState>? _subscription;
  Session? _session;

  @override
  void initState() {
    super.initState();
    _session = _client.auth.currentSession;
    _subscription = _client.auth.onAuthStateChange.listen((event) {
      if (mounted) setState(() => _session = event.session);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _session == null
      ? const SignInPage()
      : HomePage(onSignOut: () => _client.auth.signOut());
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_register) {
        final result = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (result.session == null && mounted) {
          setState(() => _message = 'راجع بريدك الإلكتروني لتأكيد الحساب إذا طُلب ذلك.');
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'حدث خطأ غير متوقع. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 46, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(
                            'إدارة المخازن والمبيعات',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _register ? 'أنشئ حسابك للبدء' : 'سجّل الدخول إلى حسابك',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'البريد الإلكتروني',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              return email.contains('@') && email.contains('.')
                                  ? null
                                  : 'اكتب بريدًا إلكترونيًا صحيحًا';
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: _hidePassword,
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                                icon: Icon(_hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                              ),
                            ),
                            validator: (value) => (value ?? '').length >= 8
                                ? null
                                : 'استخدم 8 أحرف على الأقل',
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!, style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )),
                          ],
                          if (_message != null) ...[
                            const SizedBox(height: 12),
                            Text(_message!, style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            )),
                          ],
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _loading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(_register ? 'إنشاء حساب' : 'تسجيل الدخول'),
                            ),
                          ),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                      _register = !_register;
                                      _error = null;
                                      _message = null;
                                    }),
                            child: Text(_register
                                ? 'لديك حساب؟ سجّل الدخول'
                                : 'إنشاء حساب جديد'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({required this.onSignOut, super.key});
  final Future<void> Function() onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  static const _modules = <_Module>[
    _Module('لوحة التحكم', 'ملخص النشاط اليومي', Icons.dashboard_outlined),
    _Module('الأصناف والمخزون', 'المنتجات والتصنيفات وأرصدة المخازن', Icons.inventory_2_outlined),
    _Module('فواتير المبيعات', 'البيع النقدي والآجل والمرتجعات', Icons.point_of_sale_outlined),
    _Module('فواتير المشتريات', 'الموردون وفواتير الشراء والمرتجعات', Icons.shopping_bag_outlined),
    _Module('العملاء', 'الأرصدة والمديونيات وكشوف الحساب', Icons.people_outline),
    _Module('الموردون', 'المشتريات والمدفوعات وكشوف الحساب', Icons.local_shipping_outlined),
    _Module('الخزينة والمصروفات', 'القبض والصرف والمصروفات التشغيلية', Icons.account_balance_wallet_outlined),
    _Module('التقارير', 'المبيعات والأرباح وتقييم المخزون', Icons.bar_chart_outlined),
    _Module('الجرد الفعلي', 'عدّ المخزون وتسوية الفروق بأمان', Icons.fact_check_outlined),
    _Module('الإعدادات', 'بيانات النشاط والمخازن وإعدادات النظام', Icons.settings_outlined),
    _Module('المزيد', 'الأقسام الإضافية في البرنامج', Icons.menu),
    _Module('المرتجعات', 'مرتجعات المبيعات والمشتريات وتسوية المخزون', Icons.assignment_return_outlined),
    _Module('عروض الأسعار', 'إنشاء العروض وتحويلها لفواتير بيع', Icons.request_quote_outlined),
    _Module('تحويل المخزون', 'تحويل آمن بين المخازن مع سجل حركة', Icons.swap_horiz),
    _Module('الشيكات والأقساط', 'إدارة الاستحقاقات والتحصيل والسداد', Icons.event_repeat),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final selected = _modules[_index];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة المخازن', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (value) => setState(() => _index = value),
                labelType: NavigationRailLabelType.all,
                destinations: _modules
                    .map((m) => NavigationRailDestination(
                          icon: Icon(m.icon),
                          label: Text(m.title),
                        ))
                    .toList(),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(wide ? 28 : 16),
                children: [
                  Text(selected.title,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
                  const SizedBox(height: 6),
                  Text(selected.description),
                  const SizedBox(height: 22),
                  if (_index == 0)
                    const SizedBox(height: 1500, child: DashboardPage())
                  else if (_index == 1)
                    const SizedBox(height: 560, child: ProductsPage())
                  else if (_index == 2)
                    const SizedBox(height: 1100, child: SalesPage())
                  else if (_index == 3)
                    const SizedBox(height: 900, child: PurchasePage())
                  else if (_index == 4)
                    const SizedBox(height: 560, child: CustomersPage())
                  else if (_index == 5)
                    const SizedBox(height: 560, child: SuppliersPage())
                  else if (_index == 6)
                    const SizedBox(height: 1400, child: CashboxPage())
                  else if (_index == 7)
                    const SizedBox(height: 1800, child: ReportsPage())
                  else if (_index == 8)
                    const SizedBox(height: 3000, child: StockCountPage())
                  else if (_index == 9)
                    const SizedBox(height: 700, child: SettingsPage())
                  else if (_index == 11)
                    const SizedBox(height: 3000, child: ReturnsPage())
                  else if (_index == 12)
                    const SizedBox(height: 2600, child: CommercialOperationsPage(initialTab: 0))
                  else if (_index == 13)
                    const SizedBox(height: 2600, child: CommercialOperationsPage(initialTab: 1))
                  else if (_index == 14)
                    const SizedBox(height: 2800, child: FinancialObligationsPage())
                  else if (_index == 10)
                    Card(
                      child: Column(
                        children: [
                          _MoreMenuTile(icon: Icons.point_of_sale_outlined, title: 'فواتير المبيعات', subtitle: 'إنشاء ومراجعة فواتير البيع', onTap: () => setState(() => _index = 2)),
                          _MoreMenuTile(icon: Icons.local_shipping_outlined, title: 'الموردون', subtitle: 'بيانات الموردين وأرصدتهم', onTap: () => setState(() => _index = 5)),
                          _MoreMenuTile(icon: Icons.account_balance_wallet_outlined, title: 'الخزينة والمصروفات', subtitle: 'حركة النقدية والمصروفات', onTap: () => setState(() => _index = 6)),
                          _MoreMenuTile(icon: Icons.bar_chart_outlined, title: 'التقارير', subtitle: 'تقارير المبيعات والمخزون', onTap: () => setState(() => _index = 7)),
                          _MoreMenuTile(icon: Icons.fact_check_outlined, title: 'الجرد الفعلي', subtitle: 'عدّ المخزون وتسوية الفروق', onTap: () => setState(() => _index = 8)),
                          _MoreMenuTile(icon: Icons.assignment_return_outlined, title: 'المرتجعات', subtitle: 'مرتجعات المبيعات والمشتريات', onTap: () => setState(() => _index = 11)),
                          _MoreMenuTile(icon: Icons.request_quote_outlined, title: 'عروض الأسعار', subtitle: 'إنشاء عرض وتحويله لفاتورة بيع', onTap: () => setState(() => _index = 12)),
                          _MoreMenuTile(icon: Icons.swap_horiz, title: 'تحويل المخزون', subtitle: 'نقل أصناف بين المخازن بأمان', onTap: () => setState(() => _index = 13)),
                          _MoreMenuTile(icon: Icons.event_repeat, title: 'الشيكات والأقساط', subtitle: 'تسجيل الشيكات وجداول الأقساط والسداد', onTap: () => setState(() => _index = 14)),
                          _MoreMenuTile(icon: Icons.settings_outlined, title: 'الإعدادات', subtitle: 'بيانات النشاط والمخازن', onTap: () => setState(() => _index = 9)),
                        ],
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(selected.icon, size: 44,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 12),
                            Text('قسم ${selected.title}',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            const Text(
                              'تم تجهيز مدخل القسم. سيتم تنفيذ الشاشة وربطها '
                              'بقاعدة البيانات في المراحل التالية.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _index == 0 ? 0 : _index == 1 ? 1 : _index == 3 ? 2 : _index == 4 ? 3 : 4,
                onDestinationSelected: (value) => setState(() {
                  _index = const [0, 1, 3, 4, 10][value];
                }),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'الرئيسية'),
                  NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'المخزون'),
                  NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), label: 'المشتريات'),
                  NavigationDestination(icon: Icon(Icons.people_outline), label: 'العملاء'),
                  NavigationDestination(icon: Icon(Icons.menu), label: 'المزيد'),
                ],
              ),
      ),
    );
  }
}

class _MoreMenuTile extends StatelessWidget {
  const _MoreMenuTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      );
}

class _Module {
  const _Module(this.title, this.description, this.icon);
  final String title;
  final String description;
  final IconData icon;
}
