import 'package:flutter/material.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final db = Supabase.instance.client;
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  bool hasNextPage = false;
  int page = 0;
  static const int pageSize = 50;
  String? error;
  @override
  void initState() {
    super.initState();
    search.addListener(() { if (!mounted) return; setState(() => page = 0); load(); });
    load();
  }
  @override
  void dispose() { search.dispose(); super.dispose(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final term = search.text.trim().replaceAll(',', ' ').replaceAll('(', '').replaceAll(')', '');
      var query = db.from('customers').select('id,name,phone,email,opening_balance,is_active,created_at');
      if (term.isNotEmpty) query = query.or('name.ilike.%$term%,phone.ilike.%$term%,email.ilike.%$term%');
      final data = await query.order('created_at', ascending: false).range(page * pageSize, page * pageSize + pageSize);
      if (mounted) {
        final result = List<Map<String, dynamic>>.from(data);
        final more = result.length > pageSize;
        if (more) result.removeLast();
        setState(() { rows = result; hasNextPage = more; });
      }
    } catch (e) { if (mounted) setState(() => error = 'تعذر تحميل العملاء: $e'); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> addCustomer() async {
    final name = TextEditingController(); final phone = TextEditingController();
    final email = TextEditingController(); final balance = TextEditingController(text: '0');
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (ctx) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: const Text('إضافة عميل'),
      content: SizedBox(width: 420, child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم العميل *'), validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'الاسم مطلوب'),
        TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
        TextFormField(controller: email, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
        TextFormField(controller: balance, decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي (+/-)'), keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), validator: (v) => double.tryParse(v ?? '') != null ? null : 'قيمة غير صحيحة'),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () async {
        if (!form.currentState!.validate()) return;
        try {
          await db.from('customers').insert({'name': name.text.trim(), 'phone': phone.text.trim().isEmpty ? null : phone.text.trim(), 'email': email.text.trim().isEmpty ? null : email.text.trim(), 'opening_balance': double.parse(balance.text.trim())});
          if (ctx.mounted) Navigator.pop(ctx, true);
        } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); }
      }, child: const Text('حفظ'))],
    )));
    name.dispose(); phone.dispose(); email.dispose(); balance.dispose();
    if (saved == true) await load();
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.spaceBetween, children: [
      SizedBox(width: 300, child: TextField(controller: search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'بحث بالاسم أو الهاتف أو البريد'))),
      FilledButton.icon(onPressed: addCustomer, icon: const Icon(Icons.person_add_alt_1), label: const Text('إضافة عميل')),
    ]),
    const SizedBox(height: 12), Text('نتائج الصفحة: ${rows.length} • الصفحة ${page + 1}'), const SizedBox(height: 8),
    if (loading) const Expanded(child: Center(child: CircularProgressIndicator()))
    else if (error != null) Expanded(child: Center(child: Text(error!)))
    else if (rows.isEmpty) const Expanded(child: Center(child: Text('لا يوجد عملاء بعد. أضف أول عميل للبدء.')))
    else Expanded(child: ListView.separated(itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (ctx, i) {
      final c = rows[i];
      return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(c['name']?.toString() ?? ''), subtitle: Text('${c['phone'] ?? 'بدون هاتف'} • رصيد افتتاحي: ${formatMoney((c['opening_balance'] as num?) ?? 0)} ج.م')));
    })),
    if (!loading && error == null)
      Padding(padding: const EdgeInsets.only(top: 8), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        OutlinedButton.icon(onPressed: page == 0 ? null : () { setState(() => page--); load(); }, icon: const Icon(Icons.chevron_right), label: const Text('السابق')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('صفحة ${page + 1}')),
        OutlinedButton.icon(onPressed: !hasNextPage ? null : () { setState(() => page++); load(); }, icon: const Icon(Icons.chevron_left), label: const Text('التالي')),
      ])),
  ]);
}
