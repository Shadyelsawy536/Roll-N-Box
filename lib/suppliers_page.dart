import 'package:flutter/material.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
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
    load();
    search.addListener(() {
      if (!mounted) return;
      setState(() => page = 0);
      load();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final term = search.text.trim().replaceAll(',', ' ').replaceAll('(', '').replaceAll(')', '');
      var query = db
          .from('suppliers')
          .select('id,name,phone,email,address,tax_number,notes,opening_balance,is_active,created_at');
      if (term.isNotEmpty) {
        query = query.or('name.ilike.%$term%,phone.ilike.%$term%,email.ilike.%$term%,tax_number.ilike.%$term%');
      }
      final data = await query.order('created_at', ascending: false)
          .range(page * pageSize, page * pageSize + pageSize);
      if (mounted) {
        final result = List<Map<String, dynamic>>.from(data);
        final more = result.length > pageSize;
        if (more) result.removeLast();
        setState(() { rows = result; hasNextPage = more; });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل الموردين: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> editSupplier({Map<String, dynamic>? supplier}) async {
    final name = TextEditingController(text: supplier?['name']?.toString() ?? '');
    final phone = TextEditingController(text: supplier?['phone']?.toString() ?? '');
    final email = TextEditingController(text: supplier?['email']?.toString() ?? '');
    final address = TextEditingController(text: supplier?['address']?.toString() ?? '');
    final taxNumber = TextEditingController(text: supplier?['tax_number']?.toString() ?? '');
    final balance = TextEditingController(text: supplier?['opening_balance']?.toString() ?? '0');
    final notes = TextEditingController(text: supplier?['notes']?.toString() ?? '');
    final form = GlobalKey<FormState>();
    var active = supplier?['is_active'] as bool? ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(supplier == null ? 'إضافة مورد' : 'تعديل المورد'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'اسم المورد *'),
                      validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'الاسم مطلوب',
                    ),
                    const SizedBox(height: 10),
                    TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                    const SizedBox(height: 10),
                    TextFormField(controller: email, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
                    const SizedBox(height: 10),
                    TextFormField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
                    const SizedBox(height: 10),
                    TextFormField(controller: taxNumber, decoration: const InputDecoration(labelText: 'الرقم الضريبي')),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: balance,
                      decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي (+/-) بالجنيه'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      validator: (v) => double.tryParse((v ?? '').trim()) != null ? null : 'اكتب مبلغًا صحيحًا',
                    ),
                    const SizedBox(height: 10),
                    TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات'), maxLines: 2),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('المورد نشط'),
                      value: active,
                      onChanged: (v) => setDialog(() => active = v),
                    ),
                  ]),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  final data = <String, dynamic>{
                    'name': name.text.trim(),
                    'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                    'email': email.text.trim().isEmpty ? null : email.text.trim(),
                    'address': address.text.trim().isEmpty ? null : address.text.trim(),
                    'tax_number': taxNumber.text.trim().isEmpty ? null : taxNumber.text.trim(),
                    'opening_balance': double.parse(balance.text.trim()),
                    'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
                    'is_active': active,
                  };
                  try {
                    if (supplier == null) {
                      await db.from('suppliers').insert(data);
                    } else {
                      await db.from('suppliers').update(data).eq('id', supplier['id']);
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('تعذر حفظ المورد: $e')),
                      );
                    }
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    name.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
    taxNumber.dispose();
    balance.dispose();
    notes.dispose();
    if (saved == true) await load();
  }

  Future<void> deleteSupplier(Map<String, dynamic> supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المورد'),
          content: Text('هل تريد حذف المورد «${supplier['name']}»؟ إذا كان مرتبطًا بفواتير فلن يسمح النظام بحذفه.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await db.from('suppliers').delete().eq('id', supplier['id']);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حذف المورد؛ قد يكون مرتبطًا بفواتير. $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'بحث بالاسم أو الهاتف أو الرقم الضريبي',
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => editSupplier(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('إضافة مورد'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('نتائج الصفحة: ${filtered.length} • الصفحة ${page + 1}'),
        const SizedBox(height: 8),
        if (loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (error != null)
          Expanded(child: Center(child: Text(error!)))
        else if (filtered.isEmpty)
          const Expanded(child: Center(child: Text('لا يوجد موردون مطابقون. أضف موردًا جديدًا للبدء.')))
        else
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final s = filtered[i];
                final active = s['is_active'] == true;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(active ? Icons.local_shipping_outlined : Icons.pause_circle_outline),
                    ),
                    title: Text(s['name']?.toString() ?? ''),
                    subtitle: Text(
                      '${s['phone'] ?? 'بدون هاتف'} • رصيد افتتاحي: ${formatMoney((s['opening_balance'] as num?) ?? 0)} ج.م'
                      '${active ? '' : ' • غير نشط'}',
                    ),
                    isThreeLine: s['tax_number'] != null || s['email'] != null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') editSupplier(supplier: s);
                        if (v == 'delete') deleteSupplier(s);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('تعديل')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (!loading && error == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: page == 0 ? null : () { setState(() => page--); load(); },
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('السابق'),
                ),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('صفحة ${page + 1}')),
                OutlinedButton.icon(
                  onPressed: !hasNextPage ? null : () { setState(() => page++); load(); },
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('التالي'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
