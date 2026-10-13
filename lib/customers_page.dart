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

  Future<void> showCustomerDetails(Map<String, dynamic> customer) async {
    try {
      final customerId = customer['id'].toString();
      final result = await Future.wait([
        db.from('sales_invoices').select('id,invoice_number,invoice_date,total,payment_status').eq('customer_id', customerId).eq('status', 'posted').order('invoice_date', ascending: false),
        db.from('sales_return_items').select('quantity,unit_cost,line_total,sales_returns!inner(customer_id,sales_invoice_id)').eq('sales_returns.customer_id', customerId),
      ]);
      final invoices = List<Map<String, dynamic>>.from(result[0]);
      final returnedRows = List<Map<String, dynamic>>.from(result[1]);
      final ids = invoices.map((x) => x['id'].toString()).toList();
      final allItems = ids.isEmpty ? <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(
        await db.from('sales_invoice_items').select('invoice_id,quantity,unit_price,unit_cost,discount_amount,tax_amount,line_total,products(name)').inFilter('invoice_id', ids));
      double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
      final profitByInvoice = <String, double>{};
      final costByInvoice = <String, double>{};
      for (final line in allItems) {
        final id = line['invoice_id'].toString();
        final qty = n(line['quantity']);
        final cost = qty * n(line['unit_cost']);
        profitByInvoice[id] = (profitByInvoice[id] ?? 0) + n(line['line_total']) - n(line['tax_amount']) - cost;
        costByInvoice[id] = (costByInvoice[id] ?? 0) + cost;
      }
      for (final ret in returnedRows) {
        final nested = ret['sales_returns'] as Map?;
        final id = nested?['sales_invoice_id']?.toString();
        if (id != null) {
          profitByInvoice[id] = (profitByInvoice[id] ?? 0) - n(ret['line_total']) + n(ret['unit_cost']) * n(ret['quantity']);
        }
      }
      final totalSales = invoices.fold<double>(0, (sum, x) => sum + n(x['total']));
      final totalCost = costByInvoice.values.fold<double>(0, (sum, x) => sum + x);
      final totalProfit = profitByInvoice.values.fold<double>(0, (sum, x) => sum + x);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('حساب العميل: ${customer['name']}'),
          content: SizedBox(width: 650, child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                _CustomerMetric(label: 'إجمالي الفواتير', value: formatMoney(totalSales) + ' ج.م'),
                _CustomerMetric(label: 'تكلفة البضاعة', value: formatMoney(totalCost) + ' ج.م'),
                _CustomerMetric(label: 'إجمالي الربح', value: formatMoney(totalProfit) + ' ج.م', highlight: true),
              ]),
              const SizedBox(height: 16),
              Text('فواتير العميل (${invoices.length})', style: Theme.of(ctx).textTheme.titleMedium),
              if (invoices.isEmpty) const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('لا توجد فواتير مبيعات مسجلة لهذا العميل.')),
              ...invoices.map((invoice) {
                final id = invoice['id'].toString();
                final profit = profitByInvoice[id] ?? 0;
                final date = DateTime.tryParse(invoice['invoice_date']?.toString() ?? '');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text('فاتورة #${invoice['invoice_number']}'),
                  subtitle: Text('${date == null ? '' : date.toLocal().toString().split(' ').first} • ${invoice['payment_status'] == 'paid' ? 'مدفوعة' : invoice['payment_status'] == 'partial' ? 'مدفوعة جزئيًا' : 'آجلة'}'),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(formatMoney(n(invoice['total'])) + ' ج.م'),
                    Text('الربح: ${formatMoney(profit)}', style: TextStyle(fontSize: 12, color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade700)),
                  ]),
                );
              }),
              const SizedBox(height: 8),
              const Text('الأرباح إجمالية قبل المصروفات التشغيلية، وتُخصم منها مرتجعات المبيعات المسجلة.',
                style: TextStyle(fontSize: 12)),
            ],
          ))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
        ),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل حساب العميل: $e')));
    }
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
      return Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(c['name']?.toString() ?? ''),
        subtitle: Text('${c['phone'] ?? 'بدون هاتف'} • رصيد افتتاحي: ${formatMoney((c['opening_balance'] as num?) ?? 0)} ج.م'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => showCustomerDetails(c),
      ));
    })),
    if (!loading && error == null)
      Padding(padding: const EdgeInsets.only(top: 8), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        OutlinedButton.icon(onPressed: page == 0 ? null : () { setState(() => page--); load(); }, icon: const Icon(Icons.chevron_right), label: const Text('السابق')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('صفحة ${page + 1}')),
        OutlinedButton.icon(onPressed: !hasNextPage ? null : () { setState(() => page++); load(); }, icon: const Icon(Icons.chevron_left), label: const Text('التالي')),
      ])),
  ]);
}

class _CustomerMetric extends StatelessWidget {
  const _CustomerMetric({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 145),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: highlight ? const Color(0xFFE8F4EE) : const Color(0xFFF5F7F6),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: highlight ? const Color(0xFF176B55) : null)),
    ]),
  );
}
