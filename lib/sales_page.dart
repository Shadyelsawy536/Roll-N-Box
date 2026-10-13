import 'package:flutter/material.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final db = Supabase.instance.client;
  final items = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> products = [], customers = [], warehouses = [], cashboxes = [], invoices = [];
  String? warehouseId, customerId, cashboxId;
  String paymentMethod = 'cash';
  final paid = TextEditingController(text: '0');
  final notes = TextEditingController();
  bool loading = true, saving = false;
  String? error;

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { paid.dispose(); notes.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final r = await Future.wait([
        db.from('products').select('id,name,sale_price,cost_price,track_stock').eq('is_active', true).order('name'),
        db.from('customers').select('id,name').eq('is_active', true).order('name'),
        db.from('warehouses').select('id,name,is_default').eq('is_active', true).order('name'),
        db.from('cashboxes').select('id,name,is_default').eq('is_active', true).order('name'),
        db.from('sales_invoices').select('id,invoice_number,invoice_date,total,paid_total,payment_status,customers(name),warehouses(name)').eq('status', 'posted').order('created_at', ascending: false).limit(30),
      ]);
      if (!mounted) return;
      setState(() {
        products = List<Map<String,dynamic>>.from(r[0]);
        customers = List<Map<String,dynamic>>.from(r[1]);
        warehouses = List<Map<String,dynamic>>.from(r[2]);
        cashboxes = List<Map<String,dynamic>>.from(r[3]);
        invoices = List<Map<String,dynamic>>.from(r[4]);
        warehouseId ??= warehouses.where((x) => x['is_default'] == true).map((x) => x['id'].toString()).firstOrNull ?? (warehouses.isEmpty ? null : warehouses.first['id'].toString());
        cashboxId ??= cashboxes.where((x) => x['is_default'] == true).map((x) => x['id'].toString()).firstOrNull ?? (cashboxes.isEmpty ? null : cashboxes.first['id'].toString());
      });
    } catch (e) { if (mounted) setState(() => error = 'تعذر تحميل بيانات المبيعات: $e'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  double get total => items.fold(0, (s, i) => s + (i['quantity'] as double) * (i['unit_price'] as double) - (i['discount_amount'] as double) + (i['tax_amount'] as double));
  double get paidAmount => double.tryParse(paid.text.trim()) ?? 0;
  String money(num value) => '${formatMoney(value)} ج.م';

  Future<void> addItem() async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفًا أولًا من شاشة الأصناف')));
      return;
    }
    String? productId = products.first['id'].toString();
    final qty = TextEditingController(text: '1');
    final price = TextEditingController(text: products.first['sale_price']?.toString() ?? '0');
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String,dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('إضافة صنف للفاتورة'),
        content: SizedBox(width: 420, child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: productId, isExpanded: true, decoration: const InputDecoration(labelText: 'الصنف'),
            items: products.map((p) => DropdownMenuItem(value: p['id'].toString(), child: Text(p['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { setDialog(() { productId = v; price.text = products.firstWhere((p) => p['id'].toString() == v)['sale_price']?.toString() ?? '0'; }); },
          ),
          const SizedBox(height: 10),
          TextFormField(controller: qty, decoration: const InputDecoration(labelText: 'الكمية'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n != null && n > 0 ? null : 'أدخل كمية أكبر من صفر'; }),
          const SizedBox(height: 10),
          TextFormField(controller: price, decoration: const InputDecoration(labelText: 'سعر بيع الوحدة'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n != null && n >= 0 ? null : 'السعر غير صحيح'; }),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            if (!form.currentState!.validate() || productId == null) return;
            final p = products.firstWhere((p) => p['id'].toString() == productId);
            Navigator.pop(ctx, {'product_id': productId, 'name': p['name'].toString(), 'quantity': double.parse(qty.text), 'unit_price': double.parse(price.text), 'discount_amount': 0.0, 'tax_amount': 0.0});
          }, child: const Text('إضافة')),
        ],
      ),
    )));
    qty.dispose(); price.dispose();
    if (result != null && mounted) setState(() {
      final idx = items.indexWhere((i) => i['product_id'] == result['product_id']);
      if (idx >= 0) {
        items[idx]['quantity'] = (items[idx]['quantity'] as double) + (result['quantity'] as double);
        items[idx]['unit_price'] = result['unit_price'];
      } else { items.add(result); }
      paid.text = total.toStringAsFixed(2);
    });
  }

  Future<void> save() async {
    if (warehouseId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنشئ مخزنًا أولًا من الإعدادات'))); return; }
    if (items.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفًا واحدًا على الأقل'))); return; }
    final amount = paidAmount;
    if (double.tryParse(paid.text.trim()) == null || amount < 0 || amount > total || (paymentMethod == 'credit' && amount > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مبلغ التحصيل يجب أن يكون بين صفر وإجمالي الفاتورة'))); return;
    }
    if (amount > 0 && cashboxId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنشئ خزينة من الإعدادات قبل تسجيل التحصيل'))); return; }
    setState(() => saving = true);
    try {
      final res = await db.rpc('post_sales_invoice', params: {
        'p_warehouse_id': warehouseId, 'p_customer_id': customerId,
        'p_invoice_date': DateTime.now().toUtc().toIso8601String(), 'p_due_date': null,
        'p_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'p_items': items.map((i) => {'product_id': i['product_id'], 'quantity': i['quantity'], 'unit_price': i['unit_price'], 'discount_amount': i['discount_amount'], 'tax_amount': i['tax_amount']}).toList(),
        'p_paid_amount': amount, 'p_cashbox_id': amount > 0 ? cashboxId : null, 'p_payment_method': paymentMethod,
      });
      if (!mounted) return;
      setState(() { items.clear(); notes.clear(); paid.text = '0'; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ترحيل فاتورة رقم ${res['invoice_number']} بإجمالي ${money(res['total'] as num)}')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ الفاتورة: $e')));
    } finally { if (mounted) setState(() => saving = false); }
  }


  Future<void> showInvoiceDetails(Map<String, dynamic> invoice) async {
    try {
      final invoiceId = invoice['id'].toString();
      final result = await Future.wait([
        db.from('sales_invoice_items').select('id,product_id,quantity,unit_price,unit_cost,discount_amount,tax_amount,line_total,products(name)').eq('invoice_id', invoiceId),
        db.from('sales_return_items').select('quantity,unit_cost,line_total,sales_returns!inner(sales_invoice_id)').eq('sales_returns.sales_invoice_id', invoiceId),
      ]);
      final lines = List<Map<String, dynamic>>.from(result[0]);
      final returned = List<Map<String, dynamic>>.from(result[1]);
      double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
      final soldProfit = lines.fold<double>(0, (sum, line) {
        final qty = n(line['quantity']);
        final cost = n(line['unit_cost']) * qty;
        final revenueExTax = n(line['line_total']) - n(line['tax_amount']);
        return sum + revenueExTax - cost;
      });
      final returnedProfit = returned.fold<double>(0, (sum, line) =>
        sum + n(line['line_total']) - (n(line['unit_cost']) * n(line['quantity'])));
      final profit = soldProfit - returnedProfit;
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تفاصيل وربح فاتورة #${invoice['invoice_number']}'),
          content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إجمالي الفاتورة: ${money(n(invoice['total']))}'),
              const SizedBox(height: 6),
              Text('تكلفة البضاعة: ${money(lines.fold<double>(0, (sum, x) => sum + n(x['quantity']) * n(x['unit_cost'])))}'),
              Text('ربح الفاتورة بعد خصم المرتجعات: ${money(profit)}',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade700)),
              const Divider(height: 24),
              const Text('تفاصيل الأصناف', style: TextStyle(fontWeight: FontWeight.bold)),
              ...lines.map((line) {
                final qty = n(line['quantity']);
                final revenue = n(line['line_total']) - n(line['tax_amount']);
                final cost = qty * n(line['unit_cost']);
                final lineProfit = revenue - cost;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(((line['products'] as Map?)?['name'] ?? 'صنف').toString()),
                  subtitle: Text('الكمية: ${formatMoney(qty)} • التكلفة: ${money(cost)}'),
                  trailing: Text(money(lineProfit), style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: lineProfit >= 0 ? Colors.green.shade700 : Colors.red.shade700)),
                );
              }),
              if (returned.isNotEmpty)
                Text('تم احتساب ${returned.length} بند/بنود مرتجعة ضمن صافي الربح.',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              const Text('الربح هنا ربح إجمالي قبل المصروفات التشغيلية، ويُحسب من تكلفة الصنف المسجلة وقت الفاتورة.',
                style: TextStyle(fontSize: 12)),
            ],
          ))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
        ),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حساب ربح الفاتورة: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (loading) const LinearProgressIndicator(),
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('فاتورة مبيعات جديدة', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: warehouseId, isExpanded: true, decoration: const InputDecoration(labelText: 'المخزن *'), items: warehouses.map((w) => DropdownMenuItem(value: w['id'].toString(), child: Text(w['name'].toString()))).toList(), onChanged: (v) => setState(() => warehouseId = v)),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(value: customerId, isExpanded: true, decoration: const InputDecoration(labelText: 'العميل (اختياري)'), items: [const DropdownMenuItem<String>(value: null, child: Text('بيع نقدي بدون تحديد عميل')), ...customers.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'].toString())))], onChanged: (v) => setState(() => customerId = v)),
      const SizedBox(height: 10),
      TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: addItem, icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
      if (items.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...items.asMap().entries.map((e) => ListTile(
          contentPadding: EdgeInsets.zero, title: Text(e.value['name'].toString()),
          subtitle: Text('${e.value['quantity']} × ${money(e.value['unit_price'])}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(money((e.value['quantity'] as double) * (e.value['unit_price'] as double))),
            IconButton(onPressed: () => setState(() { items.removeAt(e.key); if (paidAmount > total) paid.text = total.toStringAsFixed(2); }), icon: const Icon(Icons.delete_outline)),
          ]),
        )),
        const Divider(),
        Align(alignment: Alignment.centerLeft, child: Text('الإجمالي: ${money(total)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
      ],
      const SizedBox(height: 12),
      TextField(controller: paid, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ المحصّل الآن', helperText: 'صفر يعني أن الفاتورة آجلة بالكامل')),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(value: paymentMethod, decoration: const InputDecoration(labelText: 'طريقة التحصيل'), items: const [
        DropdownMenuItem(value: 'cash', child: Text('كاش')), DropdownMenuItem(value: 'card', child: Text('فيزا')),
        DropdownMenuItem(value: 'instapay', child: Text('إنستا باي')), DropdownMenuItem(value: 'wallet', child: Text('محفظة')),
        DropdownMenuItem(value: 'credit', child: Text('أجل')),
      ], onChanged: (v) => setState(() { paymentMethod = v ?? 'cash'; if (paymentMethod == 'credit') paid.text = '0'; else if (paidAmount == 0 && items.isNotEmpty) paid.text = total.toStringAsFixed(2); })),
      if (paidAmount > 0) ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: cashboxId, isExpanded: true, decoration: const InputDecoration(labelText: 'الخزينة المستقبلة *'), items: cashboxes.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'].toString()))).toList(), onChanged: (v) => setState(() => cashboxId = v)),
      ],
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: saving ? null : save, icon: saving ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline), label: Text(saving ? 'جارٍ ترحيل الفاتورة...' : 'حفظ وترحيل فاتورة البيع')),
      const SizedBox(height: 6),
      const Text('عند الترحيل يتم خصم الكمية من المخزن وتسجيل التحصيل بالخزينة تلقائيًا. يمنع النظام بيع كمية أكبر من المتاح.', style: TextStyle(fontSize: 12)),
    ]))),
    const SizedBox(height: 16),
    Text('آخر فواتير المبيعات', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    if (invoices.isEmpty && !loading) const Text('لا توجد فواتير مبيعات حتى الآن.')
    else ...invoices.map((i) => Card(child: ListTile(
      leading: const Icon(Icons.receipt_long_outlined), title: Text('فاتورة رقم ${i['invoice_number']}'),
      subtitle: Text('${(i['customers'] as Map?)?['name'] ?? 'بيع نقدي'} • ${(i['warehouses'] as Map?)?['name'] ?? ''} • ${i['payment_status'] == 'paid' ? 'مدفوعة' : i['payment_status'] == 'partial' ? 'مدفوعة جزئيًا' : 'آجلة'}'),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(money((i['total'] as num?) ?? 0)),
        const Text('عرض الربح', style: TextStyle(fontSize: 11, color: Color(0xFF176B55))),
      ]),
      onTap: () => showInvoiceDetails(i),
    ))),
  ]);
}
