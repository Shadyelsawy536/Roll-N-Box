import 'package:flutter/material.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PurchasePage extends StatefulWidget {
  const PurchasePage({super.key});
  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> products = [], suppliers = [], warehouses = [], invoices = [], cashboxes = [];
  final items = <Map<String, dynamic>>[];
  String? warehouseId, supplierId, cashboxId;
  String paymentMethod = 'cash';
  static const paymentMethods = <String, String>{'cash': 'كاش', 'card': 'فيزا', 'instapay': 'إنستا باي', 'wallet': 'محفظة', 'credit': 'أجل'};
  bool loading = true, saving = false;
  String? error;
  final supplierInvoice = TextEditingController(), notes = TextEditingController();

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { supplierInvoice.dispose(); notes.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await Future.wait([
        db.from('products').select('id,name,cost_price,internal_code').eq('is_active', true).order('name'),
        db.from('suppliers').select('id,name').eq('is_active', true).order('name'),
        db.from('warehouses').select('id,name,is_default').eq('is_active', true).order('name'),
        db.from('purchase_invoices').select('id,invoice_number,invoice_date,total,status,payment_status,payment_method,paid_total,supplier_invoice_number,suppliers(name),warehouses(name)').order('created_at', ascending: false).limit(30),
        db.from('cashboxes').select('id,name,is_default').eq('is_active', true).order('is_default', ascending: false).order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        products = List<Map<String,dynamic>>.from(result[0]);
        suppliers = List<Map<String,dynamic>>.from(result[1]);
        warehouses = List<Map<String,dynamic>>.from(result[2]);
        invoices = List<Map<String,dynamic>>.from(result[3]);
        cashboxes = List<Map<String,dynamic>>.from(result[4]);
        cashboxId ??= cashboxes.isEmpty ? null : cashboxes.first['id'].toString();
        warehouseId ??= warehouses.where((w) => w['is_default'] == true).map((w) => w['id'].toString()).firstOrNull ?? (warehouses.isNotEmpty ? warehouses.first['id'].toString() : null);
      });
    } catch (e) { if (mounted) setState(() => error = 'تعذر تحميل بيانات الفواتير: $e'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  double get total => items.fold(0, (sum, item) => sum + (item['quantity'] as double) * (item['unit_cost'] as double) - (item['discount_amount'] as double) + (item['tax_amount'] as double));
  String money(num value) => '${formatMoney(value)} ج.م';

  Future<void> addItem() async {
    if (products.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفًا أولاً من شاشة الأصناف'))); return; }
    String? productId = products.first['id'].toString();
    final qty = TextEditingController(text: '1');
    final cost = TextEditingController(text: products.first['cost_price']?.toString() ?? '0');
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String,dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: const Text('إضافة صنف للفاتورة'),
      content: SizedBox(width: 420, child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: productId, isExpanded: true, decoration: const InputDecoration(labelText: 'الصنف'), items: products.map((p) => DropdownMenuItem(value: p['id'].toString(), child: Text(p['name'].toString(), overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) { setDialog(() { productId = v; final p = products.firstWhere((p) => p['id'].toString() == v); cost.text = p['cost_price']?.toString() ?? '0'; }); }),
        const SizedBox(height: 10),
        TextFormField(controller: qty, decoration: const InputDecoration(labelText: 'الكمية'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n != null && n > 0 ? null : 'أدخل كمية أكبر من صفر'; }),
        const SizedBox(height: 10),
        TextFormField(controller: cost, decoration: const InputDecoration(labelText: 'تكلفة الوحدة'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n != null && n >= 0 ? null : 'تكلفة غير صحيحة'; }),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () { if (!form.currentState!.validate() || productId == null) return; final p = products.firstWhere((p) => p['id'].toString() == productId); Navigator.pop(ctx, {'product_id': productId, 'name': p['name'].toString(), 'quantity': double.parse(qty.text), 'unit_cost': double.parse(cost.text), 'discount_amount': 0.0, 'tax_amount': 0.0}); }, child: const Text('إضافة'))],
    ))));
    qty.dispose(); cost.dispose();
    if (result != null && mounted) setState(() => items.add(result));
  }

  Future<void> save() async {
    if (warehouseId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنشئ مخزنًا أولاً'))); return; }
    if (items.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفًا واحدًا على الأقل'))); return; }
    if (paymentMethod == 'credit' && supplierId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختار المورد عند تسجيل الفاتورة آجل'))); return; }
    if (paymentMethod != 'credit' && (cashboxId == null || cashboxes.isEmpty)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنشئ خزينة واختارها لتسجيل الفاتورة المدفوعة'))); return; }
    setState(() => saving = true);
    try {
      final response = await db.rpc('post_purchase_invoice', params: {
        'p_warehouse_id': warehouseId,
        'p_supplier_id': supplierId,
        'p_supplier_invoice_number': supplierInvoice.text.trim().isEmpty ? null : supplierInvoice.text.trim(),
        'p_invoice_date': DateTime.now().toUtc().toIso8601String(),
        'p_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'p_items': items.map((i) => {'product_id': i['product_id'], 'quantity': i['quantity'], 'unit_cost': i['unit_cost'], 'discount_amount': i['discount_amount'], 'tax_amount': i['tax_amount']}).toList(),
        'p_payment_method': paymentMethod,
        'p_cashbox_id': paymentMethod == 'credit' ? null : cashboxId,
        'p_due_date': null,
      });
      if (!mounted) return;
      setState(() { items.clear(); supplierInvoice.clear(); notes.clear(); paymentMethod = 'cash'; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ترحيل فاتورة رقم ${response['invoice_number']} بإجمالي ${money((response['total'] as num))}')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ الفاتورة: $e')));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (loading) const LinearProgressIndicator(),
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('فاتورة مشتريات جديدة', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: warehouseId, isExpanded: true, decoration: const InputDecoration(labelText: 'المخزن *'), items: warehouses.map((w) => DropdownMenuItem(value: w['id'].toString(), child: Text(w['name'].toString()))).toList(), onChanged: (v) => setState(() => warehouseId = v)),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(value: supplierId, isExpanded: true, decoration: const InputDecoration(labelText: 'المورد (اختياري)'), items: [const DropdownMenuItem<String>(value: null, child: Text('بدون تحديد مورد')), ...suppliers.map((s) => DropdownMenuItem(value: s['id'].toString(), child: Text(s['name'].toString())))], onChanged: (v) => setState(() => supplierId = v)),
      const SizedBox(height: 10),
      TextField(controller: supplierInvoice, decoration: const InputDecoration(labelText: 'رقم فاتورة المورد (اختياري)')),
      const SizedBox(height: 10),
      TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(value: paymentMethod, isExpanded: true, decoration: const InputDecoration(labelText: 'طريقة دفع الفاتورة *'), items: paymentMethods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) => setState(() => paymentMethod = v ?? 'cash')),
      if (paymentMethod != 'credit') ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: cashboxId, isExpanded: true, decoration: const InputDecoration(labelText: 'الخزينة التي تم الدفع منها *'), items: cashboxes.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'].toString()))).toList(), onChanged: (v) => setState(() => cashboxId = v)),
      ] else ...[
        const SizedBox(height: 8),
        const Text('الفاتورة الآجلة ستُضاف لمستحقات المورد ولن تخصم من الخزينة الآن.', style: TextStyle(fontSize: 12)),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: addItem, icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
      if (items.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...items.asMap().entries.map((entry) { final i = entry.key; final item = entry.value; return ListTile(title: Text(item['name'].toString()), subtitle: Text('${item['quantity']} × ${money(item['unit_cost'])}'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(money((item['quantity'] as double) * (item['unit_cost'] as double))), IconButton(onPressed: () => setState(() => items.removeAt(i)), icon: const Icon(Icons.delete_outline))])); }),
        const Divider(),
        Align(alignment: Alignment.centerLeft, child: Text('الإجمالي: ${money(total)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
      ],
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: saving ? null : save, icon: saving ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline), label: const Text('حفظ وترحيل الفاتورة')),
      const SizedBox(height: 6),
      const Text('ترحيل الفاتورة يضيف الكميات للمخزون تلقائيًا، ولا يمكن ترحيل فاتورة فارغة.', style: TextStyle(fontSize: 12)),
    ]))),
    const SizedBox(height: 16),
    Text('آخر فواتير المشتريات', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    if (invoices.isEmpty && !loading) const Text('لا توجد فواتير مشتريات حتى الآن.')
    else ...invoices.map((i) => Card(child: ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text('فاتورة رقم ${i['invoice_number']}'), subtitle: Text('${(i['suppliers'] as Map?)?['name'] ?? 'بدون مورد'} • ${(i['warehouses'] as Map?)?['name'] ?? ''}'), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(money((i['total'] as num?) ?? 0)), Text(paymentMethods[i['payment_method']?.toString()] ?? 'غير محدد', style: const TextStyle(fontSize: 12)), Text(i['payment_status'] == 'paid' ? 'مدفوعة' : i['payment_status'] == 'partial' ? 'مدفوعة جزئيًا' : 'مستحقات', style: TextStyle(fontSize: 12, color: i['payment_status'] == 'paid' ? Colors.green : Colors.orange))])))),
  ]));
}
