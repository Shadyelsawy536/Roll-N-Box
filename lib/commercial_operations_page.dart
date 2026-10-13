import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'money_format.dart';

class CommercialOperationsPage extends StatefulWidget {
  const CommercialOperationsPage({this.initialTab = 0, super.key});
  final int initialTab;

  @override
  State<CommercialOperationsPage> createState() => _CommercialOperationsPageState();
}

class _CommercialOperationsPageState extends State<CommercialOperationsPage> with SingleTickerProviderStateMixin {
  final db = Supabase.instance.client;
  late final TabController tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> warehouses = [];
  List<Map<String, dynamic>> quotations = [];
  List<Map<String, dynamic>> transfers = [];
  String? customerId, quoteWarehouseId, sourceWarehouseId, destinationWarehouseId;
  final quoteNotes = TextEditingController();
  final transferNotes = TextEditingController();
  final quoteItems = <Map<String, dynamic>>[];
  final transferItems = <Map<String, dynamic>>[];
  bool loading = false, savingQuote = false, savingTransfer = false;
  String? error;
  String? transferRequestKey;

  String money(num value) => '${formatMoney(value)} ج.م';
  double number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
    quoteNotes.dispose();
    transferNotes.dispose();
    super.dispose();
  }

  String newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await Future.wait([
        db.from('products').select('id,name,sale_price,cost_price,track_stock').eq('is_active', true).order('name').limit(2000),
        db.from('customers').select('id,name').eq('is_active', true).order('name').limit(2000),
        db.from('warehouses').select('id,name,is_default').eq('is_active', true).order('name').limit(500),
        db.from('quotations').select('id,quotation_number,quotation_date,valid_until,status,total,warehouse_id,customers(name),warehouses(name)').order('quotation_date', ascending: false).limit(100),
        db.from('stock_transfers').select('id,transfer_number,transfer_date,status,notes,source:warehouses!stock_transfers_source_warehouse_id_fkey(name),destination:warehouses!stock_transfers_destination_warehouse_id_fkey(name)').order('transfer_date', ascending: false).limit(100),
      ]);
      if (!mounted) return;
      setState(() {
        products = List<Map<String, dynamic>>.from(result[0]);
        customers = List<Map<String, dynamic>>.from(result[1]);
        warehouses = List<Map<String, dynamic>>.from(result[2]);
        quotations = List<Map<String, dynamic>>.from(result[3]);
        transfers = List<Map<String, dynamic>>.from(result[4]);
        final activeWarehouses = warehouses;
        quoteWarehouseId ??= activeWarehouses.where((w) => w['is_default'] == true).map((w) => w['id'].toString()).firstOrNull ?? (activeWarehouses.isEmpty ? null : activeWarehouses.first['id'].toString());
        sourceWarehouseId ??= activeWarehouses.where((w) => w['is_default'] == true).map((w) => w['id'].toString()).firstOrNull ?? (activeWarehouses.isEmpty ? null : activeWarehouses.first['id'].toString());
        destinationWarehouseId ??= activeWarehouses.where((w) => w['id'].toString() != sourceWarehouseId).map((w) => w['id'].toString()).firstOrNull;
      });
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل العمليات التجارية: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<Map<String, dynamic>?> chooseItem({required bool stockOnly}) async {
    final candidates = products.where((p) => !stockOnly || p['track_stock'] == true).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(stockOnly ? 'لا توجد أصناف تتبع المخزون' : 'أضف أصنافًا أولًا')));
      return null;
    }
    String? productId = candidates.first['id'].toString();
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController(text: candidates.first['sale_price']?.toString() ?? '0');
    final form = GlobalKey<FormState>();
    final selected = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(stockOnly ? 'إضافة صنف للتحويل' : 'إضافة صنف لعرض السعر'),
        content: SizedBox(width: 420, child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: productId, isExpanded: true, decoration: const InputDecoration(labelText: 'الصنف'),
            items: candidates.map((p) => DropdownMenuItem(value: p['id'].toString(), child: Text(p['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setDialog(() { productId = v; if (!stockOnly && v != null) price.text = candidates.firstWhere((p) => p['id'].toString() == v)['sale_price'].toString(); }),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية'), validator: (v) { final n = double.tryParse(v ?? ''); return n != null && n.isFinite && n > 0 ? null : 'أدخل كمية أكبر من صفر'; }),
          if (!stockOnly) ...[
            const SizedBox(height: 12),
            TextFormField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر الوحدة'), validator: (v) { final n = double.tryParse(v ?? ''); return n != null && n.isFinite && n >= 0 ? null : 'السعر غير صحيح'; }),
          ],
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            if (!form.currentState!.validate() || productId == null) return;
            final product = candidates.firstWhere((p) => p['id'].toString() == productId);
            Navigator.pop(ctx, {'product_id': productId, 'name': product['name'].toString(), 'quantity': double.parse(quantity.text), 'unit_price': stockOnly ? 0.0 : double.parse(price.text), 'unit_cost': number(product['cost_price']), 'discount_amount': 0.0, 'tax_amount': 0.0});
          }, child: const Text('إضافة')),
        ],
      ),
    )));
    quantity.dispose();
    price.dispose();
    return selected;
  }

  double quoteTotal(List<Map<String, dynamic>> items) => items.fold(0.0, (sum, i) => sum + number(i['quantity']) * number(i['unit_price']) - number(i['discount_amount']) + number(i['tax_amount']));

  Future<void> saveQuote() async {
    if (quoteItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفًا واحدًا على الأقل لعرض السعر')));
      return;
    }
    setState(() => savingQuote = true);
    try {
      final result = await db.rpc('save_quotation', params: {
        'p_customer_id': customerId,
        'p_warehouse_id': quoteWarehouseId,
        'p_valid_until': null,
        'p_notes': quoteNotes.text.trim().isEmpty ? null : quoteNotes.text.trim(),
        'p_items': quoteItems.map((i) => {'product_id': i['product_id'], 'quantity': i['quantity'], 'unit_price': i['unit_price'], 'discount_amount': i['discount_amount'], 'tax_amount': i['tax_amount']}).toList(),
      });
      if (!mounted) return;
      setState(() { quoteItems.clear(); quoteNotes.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ عرض السعر رقم ${result['quotation_number']}')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ عرض السعر: $e')));
    } finally {
      if (mounted) setState(() => savingQuote = false);
    }
  }

  Future<void> convertQuote(Map<String, dynamic> quote) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تحويل عرض السعر إلى فاتورة'),
        content: Text('سيتم إنشاء فاتورة بيع آجلة من عرض السعر رقم ${quote['quotation_number']}، دون تسجيل تحصيل أو خصم نقدية. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تحويل وإنشاء الفاتورة')),
        ],
      ),
    ));
    if (ok != true || !mounted) return;
    try {
      final result = await db.rpc('convert_quotation_to_sales_invoice', params: {'p_quotation_id': quote['id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إنشاء فاتورة البيع رقم ${result['invoice_number']} من عرض السعر ${quote['quotation_number']}')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر التحويل: $e')));
    }
  }

  Future<void> postTransfer() async {
    if (sourceWarehouseId == null || destinationWarehouseId == null || sourceWarehouseId == destinationWarehouseId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر مخزنين مختلفين')));
      return;
    }
    if (transferItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفًا واحدًا على الأقل للتحويل')));
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تأكيد تحويل المخزون'),
        content: Text('سيتم خصم وإضافة ${transferItems.length} صنف بين المخزنين في عملية واحدة. إذا لم تتوفر الكمية في مخزن المصدر، سيتم رفض التحويل بالكامل.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('مراجعة')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ترحيل التحويل')),
        ],
      ),
    ));
    if (ok != true || !mounted) return;
    transferRequestKey ??= newUuid();
    setState(() => savingTransfer = true);
    try {
      final result = await db.rpc('post_stock_transfer', params: {
        'p_source_warehouse_id': sourceWarehouseId,
        'p_destination_warehouse_id': destinationWarehouseId,
        'p_transfer_date': DateTime.now().toUtc().toIso8601String(),
        'p_notes': transferNotes.text.trim().isEmpty ? null : transferNotes.text.trim(),
        'p_items': transferItems.map((i) => {'product_id': i['product_id'], 'quantity': i['quantity']}).toList(),
        'p_idempotency_key': transferRequestKey,
      });
      if (!mounted) return;
      setState(() { transferItems.clear(); transferNotes.clear(); transferRequestKey = null; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ترحيل تحويل المخزون رقم ${result['transfer_number']}')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحويل المخزون. يمكنك إعادة المحاولة بنفس الطلب بأمان: $e')));
    } finally {
      if (mounted) setState(() => savingTransfer = false);
    }
  }

  Widget quoteTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('إنشاء عرض سعر', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: customerId, isExpanded: true, decoration: const InputDecoration(labelText: 'العميل (اختياري)'), items: [const DropdownMenuItem<String>(value: null, child: Text('بدون تحديد عميل')), ...customers.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'].toString())))], onChanged: savingQuote ? null : (v) => setState(() => customerId = v)),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(value: quoteWarehouseId, isExpanded: true, decoration: const InputDecoration(labelText: 'المخزن الذي سيصدر منه البيع عند التحويل'), items: warehouses.map((w) => DropdownMenuItem(value: w['id'].toString(), child: Text(w['name'].toString()))).toList(), onChanged: savingQuote ? null : (v) => setState(() => quoteWarehouseId = v)),
      const SizedBox(height: 10),
      TextField(controller: quoteNotes, decoration: const InputDecoration(labelText: 'ملاحظات العرض')),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: savingQuote ? null : () async { final item = await chooseItem(stockOnly: false); if (item != null && mounted) setState(() { final index = quoteItems.indexWhere((i) => i['product_id'] == item['product_id']); if (index >= 0) quoteItems[index]['quantity'] = number(quoteItems[index]['quantity']) + number(item['quantity']); else quoteItems.add(item); }); }, icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
      if (quoteItems.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...quoteItems.asMap().entries.map((entry) => ListTile(contentPadding: EdgeInsets.zero, title: Text(entry.value['name'].toString()), subtitle: Text('${entry.value['quantity']} × ${money(number(entry.value['unit_price']))}'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(money(number(entry.value['quantity']) * number(entry.value['unit_price']) - number(entry.value['discount_amount']) + number(entry.value['tax_amount']))), IconButton(tooltip: 'حذف الصنف', onPressed: savingQuote ? null : () => setState(() => quoteItems.removeAt(entry.key)), icon: const Icon(Icons.delete_outline))]))),
        const Divider(),
        Text('إجمالي العرض: ${money(quoteTotal(quoteItems))}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ],
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: savingQuote ? null : saveQuote, icon: const Icon(Icons.save_outlined), label: Text(savingQuote ? 'جارٍ الحفظ...' : 'حفظ عرض السعر')),
    ]))),
    const SizedBox(height: 12),
    Text('عروض الأسعار السابقة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
    if (quotations.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد عروض أسعار حتى الآن.'))),
    ...quotations.map((q) {
      final status = (q['status'] ?? 'draft').toString();
      final canConvert = const ['draft','sent','accepted'].contains(status) && q['warehouse_id'] != null;
      return Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.request_quote_outlined)),
        title: Text('عرض سعر #${q['quotation_number']} • ${money(number(q['total']))}'),
        subtitle: Text('${(q['customers'] as Map?)?['name'] ?? 'بدون عميل'} • ${(q['warehouses'] as Map?)?['name'] ?? 'بدون مخزن'} • الحالة: ${status == 'converted' ? 'تم التحويل' : status}'),
        trailing: canConvert ? IconButton(tooltip: 'تحويل إلى فاتورة بيع آجلة', onPressed: savingQuote ? null : () => convertQuote(q), icon: const Icon(Icons.transform)) : const Icon(Icons.check_circle_outline),
      ));
    }),
  ]);

  Widget transferTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('تحويل بين المخازن', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('الترحيل يتم كعملية واحدة: خصم من مخزن المصدر وإضافة لمخزن الوجهة. لن يتم ترحيل التحويل إذا كانت الكمية غير متاحة.'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: sourceWarehouseId, isExpanded: true, decoration: const InputDecoration(labelText: 'من مخزن'), items: warehouses.map((w) => DropdownMenuItem(value: w['id'].toString(), child: Text(w['name'].toString()))).toList(), onChanged: savingTransfer ? null : (v) => setState(() { sourceWarehouseId = v; if (destinationWarehouseId == v) destinationWarehouseId = warehouses.where((w) => w['id'].toString() != v).map((w) => w['id'].toString()).firstOrNull; })),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(value: destinationWarehouseId, isExpanded: true, decoration: const InputDecoration(labelText: 'إلى مخزن'), items: warehouses.where((w) => w['id'].toString() != sourceWarehouseId).map((w) => DropdownMenuItem(value: w['id'].toString(), child: Text(w['name'].toString()))).toList(), onChanged: savingTransfer ? null : (v) => setState(() => destinationWarehouseId = v)),
      const SizedBox(height: 10),
      TextField(controller: transferNotes, decoration: const InputDecoration(labelText: 'ملاحظات التحويل')),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: savingTransfer ? null : () async { final item = await chooseItem(stockOnly: true); if (item != null && mounted) setState(() { final index = transferItems.indexWhere((i) => i['product_id'] == item['product_id']); if (index >= 0) transferItems[index]['quantity'] = number(transferItems[index]['quantity']) + number(item['quantity']); else transferItems.add(item); }); }, icon: const Icon(Icons.add), label: const Text('إضافة صنف للتحويل')),
      if (transferItems.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...transferItems.asMap().entries.map((entry) => ListTile(contentPadding: EdgeInsets.zero, title: Text(entry.value['name'].toString()), subtitle: Text('الكمية: ${entry.value['quantity']}'), trailing: IconButton(onPressed: savingTransfer ? null : () => setState(() => transferItems.removeAt(entry.key)), icon: const Icon(Icons.delete_outline)))),
      ],
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: savingTransfer ? null : postTransfer, icon: const Icon(Icons.swap_horiz), label: Text(savingTransfer ? 'جارٍ الترحيل...' : 'ترحيل التحويل')),
    ]))),
    const SizedBox(height: 12),
    Text('سجل التحويلات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
    if (transfers.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد تحويلات مخزون مسجلة.'))),
    ...transfers.map((t) => Card(child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.swap_horiz)),
      title: Text('تحويل #${t['transfer_number']}'),
      subtitle: Text('${(t['source'] as Map?)?['name'] ?? 'مصدر'} ← ${(t['destination'] as Map?)?['name'] ?? 'وجهة'} • ${t['transfer_date'].toString().split('T').first}'),
      trailing: const Icon(Icons.check_circle_outline, color: Colors.green),
    ))),
  ]);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (loading) const LinearProgressIndicator(),
    if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    Card(child: TabBar(controller: tabs, tabs: const [Tab(icon: Icon(Icons.request_quote_outlined), text: 'عروض الأسعار'), Tab(icon: Icon(Icons.swap_horiz), text: 'تحويل المخزون')])),
    const SizedBox(height: 12),
    SizedBox(height: 2400, child: TabBarView(controller: tabs, children: [quoteTab(), transferTab()])),
    Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: loading ? null : load, icon: const Icon(Icons.refresh), label: const Text('تحديث البيانات'))),
  ]);
}
