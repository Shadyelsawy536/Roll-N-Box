import 'package:flutter/material.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CashboxPage extends StatefulWidget {
  const CashboxPage({super.key});
  @override
  State<CashboxPage> createState() => _CashboxPageState();
}

class _CashboxPageState extends State<CashboxPage> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> cashboxes = [], expenses = [], transactions = [], suppliers = [], unpaidPurchaseInvoices = [], customers = [], unpaidSalesInvoices = [];
  bool loading = true, saving = false;
  String? error;

  String money(num value) => '${formatMoney(value)} ج.م';
  static const methods = <String, String>{
    'cash': 'كاش', 'card': 'فيزا', 'instapay': 'إنستا باي', 'wallet': 'محفظة',
  };

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        db.from('cashbox_balances').select().eq('is_active', true).order('is_default', ascending: false).order('name'),
        db.from('expenses').select('id,category,description,amount,expense_date,payment_method,cashbox_id').order('created_at', ascending: false).limit(25),
        db.from('cash_transactions').select('id,transaction_type,amount,payment_method,transaction_date,notes,cashbox_id').order('transaction_date', ascending: false).limit(30),
        db.from('suppliers').select('id,name').order('name'),
        db.from('purchase_invoices').select('id,invoice_number,total,paid_total,supplier_id,payment_status').eq('status', 'posted').neq('payment_status', 'paid').order('invoice_date'),
        db.from('customers').select('id,name').order('name'),
        db.from('sales_invoices').select('id,invoice_number,total,paid_total,customer_id,payment_status,customers(name)').eq('status', 'posted').neq('payment_status', 'paid').order('invoice_date'),
      ]);
      if (!mounted) return;
      setState(() {
        cashboxes = List<Map<String, dynamic>>.from(results[0]);
        expenses = List<Map<String, dynamic>>.from(results[1]);
        transactions = List<Map<String, dynamic>>.from(results[2]);
        suppliers = List<Map<String, dynamic>>.from(results[3]);
        unpaidPurchaseInvoices = List<Map<String, dynamic>>.from(results[4]).where((i) => i['supplier_id'] != null && ((i['total'] as num?)?.toDouble() ?? 0) > ((i['paid_total'] as num?)?.toDouble() ?? 0)).toList();
        customers = List<Map<String, dynamic>>.from(results[5]);
        unpaidSalesInvoices = List<Map<String, dynamic>>.from(results[6]).where((i) => i['customer_id'] != null && ((i['total'] as num?)?.toDouble() ?? 0) > ((i['paid_total'] as num?)?.toDouble() ?? 0)).toList();
      });
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل بيانات الخزينة: $e');
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> createCashbox() async {
    final name = TextEditingController();
    final opening = TextEditingController(text: '0');
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('إضافة خزينة'),
        content: SizedBox(width: 420, child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم الخزينة *'), validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب اسم الخزينة' : null),
          const SizedBox(height: 12),
          TextFormField(controller: opening, decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n != null && n >= 0 ? null : 'أدخل رصيدًا صحيحًا'; }),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, {'name': name.text.trim(), 'opening_balance': double.parse(opening.text), 'is_default': cashboxes.isEmpty, 'is_active': true}); }, child: const Text('حفظ')),
        ],
      ),
    ));
    name.dispose(); opening.dispose();
    if (result == null || !mounted) return;
    try {
      await db.from('cashboxes').insert(result);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء الخزينة')));
      await load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء الخزينة: $e'))); }
  }

  Future<void> addExpense() async {
    if (cashboxes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنشئ خزينة أولًا لتسجيل المصروف وربطه بحركة نقدية.')));
      return;
    }
    final category = TextEditingController();
    final description = TextEditingController();
    final amount = TextEditingController();
    String? cashboxId = cashboxes.first['cashbox_id'].toString();
    String method = 'cash';
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تسجيل مصروف'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: category, decoration: const InputDecoration(labelText: 'بند المصروف *'), validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب بند المصروف' : null),
          const SizedBox(height: 10),
          TextFormField(controller: description, decoration: const InputDecoration(labelText: 'الوصف / التفاصيل')),
          const SizedBox(height: 10),
          TextFormField(controller: amount, decoration: const InputDecoration(labelText: 'المبلغ *'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n != null && n > 0 ? null : 'المبلغ يجب أن يكون أكبر من صفر'; }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: cashboxId, isExpanded: true, decoration: const InputDecoration(labelText: 'الخزينة'), items: cashboxes.map((c) => DropdownMenuItem(value: c['cashbox_id'].toString(), child: Text(c['name'].toString()))).toList(), onChanged: (v) => setDialog(() => cashboxId = v)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'طريقة الدفع'), items: methods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) { if (v != null) setDialog(() => method = v); }),
        ])))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, {'cashbox_id': cashboxId, 'category': category.text.trim(), 'description': description.text.trim(), 'amount': double.parse(amount.text), 'payment_method': method}); }, child: const Text('تسجيل المصروف')),
        ],
      ),
    )));
    category.dispose(); description.dispose(); amount.dispose();
    if (result == null || !mounted) return;
    setState(() => saving = true);
    try {
      await db.rpc('post_expense', params: {
        'p_cashbox_id': result['cashbox_id'], 'p_category': result['category'],
        'p_description': result['description'], 'p_amount': result['amount'],
        'p_expense_date': DateTime.now().toIso8601String().substring(0, 10),
        'p_payment_method': result['payment_method'],
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل المصروف وخصمه من رصيد الخزينة')));
      await load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تسجيل المصروف: $e'))); }
    finally { if (mounted) setState(() => saving = false); }
  }

  Future<void> addMovement() async {
    if (cashboxes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنشئ خزينة أولًا')));
      return;
    }
    final amount = TextEditingController();
    final notes = TextEditingController();
    String? cashboxId = cashboxes.first['cashbox_id'].toString();
    String direction = 'receipt', method = 'cash';
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('حركة نقدية جديدة'),
        content: SizedBox(width: 460, child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(value: direction, decoration: const InputDecoration(labelText: 'نوع الحركة'), items: const [DropdownMenuItem(value: 'receipt', child: Text('قبض / إضافة رصيد')), DropdownMenuItem(value: 'payment', child: Text('صرف / خصم رصيد'))], onChanged: (v) { if (v != null) setDialog(() => direction = v); }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: cashboxId, isExpanded: true, decoration: const InputDecoration(labelText: 'الخزينة'), items: cashboxes.map((c) => DropdownMenuItem(value: c['cashbox_id'].toString(), child: Text(c['name'].toString()))).toList(), onChanged: (v) => setDialog(() => cashboxId = v)),
          const SizedBox(height: 10),
          TextFormField(controller: amount, decoration: const InputDecoration(labelText: 'المبلغ *'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n != null && n > 0 ? null : 'المبلغ يجب أن يكون أكبر من صفر'; }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'طريقة الدفع'), items: methods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) { if (v != null) setDialog(() => method = v); }),
          const SizedBox(height: 10),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'البيان / ملاحظات')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, {'cashbox_id': cashboxId, 'direction': direction, 'amount': double.parse(amount.text), 'payment_method': method, 'notes': notes.text.trim()}); }, child: const Text('حفظ الحركة')),
        ],
      ),
    )));
    amount.dispose(); notes.dispose();
    if (result == null || !mounted) return;
    setState(() => saving = true);
    try {
      await db.rpc('post_cash_movement', params: {
        'p_cashbox_id': result['cashbox_id'], 'p_direction': result['direction'],
        'p_amount': result['amount'], 'p_payment_method': result['payment_method'],
        'p_transaction_date': DateTime.now().toUtc().toIso8601String(), 'p_notes': result['notes'],
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الحركة النقدية')));
      await load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تسجيل الحركة: $e'))); }
    finally { if (mounted) setState(() => saving = false); }
  }


  Future<void> addCustomerReceipt() async {
    if (cashboxes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنشئ خزينة أولًا لتسجيل تحصيل العميل')));
      return;
    }
    if (unpaidSalesInvoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد فواتير مبيعات آجلة أو مستحقات غير محصلة مرتبطة بعميل')));
      return;
    }
    String customerId = unpaidSalesInvoices.first['customer_id'].toString();
    List<Map<String, dynamic>> customerInvoices() => unpaidSalesInvoices.where((i) => i['customer_id'].toString() == customerId).toList();
    String? invoiceId = customerInvoices().isEmpty ? null : customerInvoices().first['id'].toString();
    double remaining(Map<String, dynamic> invoice) => (((invoice['total'] as num?)?.toDouble() ?? 0) - ((invoice['paid_total'] as num?)?.toDouble() ?? 0)).clamp(0, double.infinity).toDouble();
    final amount = TextEditingController(text: invoiceId == null ? '' : remaining(customerInvoices().first).toStringAsFixed(2));
    final notes = TextEditingController();
    String cashboxId = cashboxes.first['cashbox_id'].toString();
    String method = 'cash';
    DateTime transactionDate = DateTime.now();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تحصيل مستحقات عميل'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: customerId, isExpanded: true, decoration: const InputDecoration(labelText: 'العميل *'),
            items: customers.where((c) => unpaidSalesInvoices.any((i) => i['customer_id'].toString() == c['id'].toString())).map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'].toString()))).toList(),
            onChanged: (v) { if (v == null) return; setDialog(() { customerId = v; final available = customerInvoices(); invoiceId = available.isEmpty ? null : available.first['id'].toString(); amount.text = available.isEmpty ? '' : remaining(available.first).toStringAsFixed(2); }); },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: invoiceId, isExpanded: true, decoration: const InputDecoration(labelText: 'الفاتورة المستحقة *'),
            items: customerInvoices().map((i) => DropdownMenuItem(value: i['id'].toString(), child: Text('فاتورة #${i['invoice_number']} • متبقي ${remaining(i).toStringAsFixed(2)} ج.م', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { setDialog(() { invoiceId = v; final found = customerInvoices().where((i) => i['id'].toString() == v); amount.text = found.isEmpty ? '' : remaining(found.first).toStringAsFixed(2); }); },
          ),
          const SizedBox(height: 10),
          TextFormField(controller: amount, decoration: const InputDecoration(labelText: 'مبلغ التحصيل *'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); if (n == null || n <= 0) return 'أدخل مبلغًا أكبر من صفر'; final found = customerInvoices().where((i) => i['id'].toString() == invoiceId); if (found.isEmpty) return 'اختار فاتورة مستحقة'; if (n > remaining(found.first)) return 'المبلغ أكبر من المتبقي على الفاتورة'; return null; }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: cashboxId, isExpanded: true, decoration: const InputDecoration(labelText: 'الخزينة المستقبلة *'), items: cashboxes.map((c) => DropdownMenuItem(value: c['cashbox_id'].toString(), child: Text(c['name'].toString()))).toList(), onChanged: (v) { if (v != null) setDialog(() => cashboxId = v); }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'طريقة التحصيل'), items: const [
            DropdownMenuItem(value: 'cash', child: Text('كاش')),
            DropdownMenuItem(value: 'card', child: Text('فيزا')),
            DropdownMenuItem(value: 'instapay', child: Text('إنستا باي')),
            DropdownMenuItem(value: 'wallet', child: Text('محفظة إلكترونية')),
          ], onChanged: (v) { if (v != null) setDialog(() => method = v); }),
          const SizedBox(height: 10),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(context: ctx, initialDate: transactionDate, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)), helpText: 'تاريخ التحصيل');
              if (picked != null) setDialog(() => transactionDate = picked);
            },
            icon: const Icon(Icons.calendar_month),
            label: Text('تاريخ التحصيل: ${transactionDate.year}-${transactionDate.month.toString().padLeft(2, '0')}-${transactionDate.day.toString().padLeft(2, '0')}'),
          )),
        ])))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate() && invoiceId != null) Navigator.pop(ctx, {'customer_id': customerId, 'invoice_id': invoiceId, 'cashbox_id': cashboxId, 'amount': double.parse(amount.text), 'payment_method': method, 'notes': notes.text.trim(), 'transaction_date': DateTime(transactionDate.year, transactionDate.month, transactionDate.day).toUtc().toIso8601String()}); }, child: const Text('تأكيد التحصيل')),
        ],
      ),
    )));
    amount.dispose(); notes.dispose();
    if (result == null || !mounted) return;
    setState(() => saving = true);
    try {
      await db.rpc('post_customer_receipt', params: {
        'p_customer_id': result['customer_id'],
        'p_sales_invoice_id': result['invoice_id'],
        'p_cashbox_id': result['cashbox_id'],
        'p_amount': result['amount'],
        'p_payment_method': result['payment_method'],
        'p_transaction_date': result['transaction_date'],
        'p_notes': result['notes'],
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل التحصيل وتحديث الفاتورة ورصيد الخزينة وكشف العميل')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحصيل العميل: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> addSupplierPayment() async {
    if (cashboxes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنشئ خزينة أولًا لتسجيل سداد المورد')));
      return;
    }
    if (unpaidPurchaseInvoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد فواتير آجلة أو مستحقات غير مسددة مرتبطة بمورد')));
      return;
    }
    String supplierId = unpaidPurchaseInvoices.first['supplier_id'].toString();
    List<Map<String, dynamic>> supplierInvoices() => unpaidPurchaseInvoices.where((i) => i['supplier_id'].toString() == supplierId).toList();
    String? invoiceId = supplierInvoices().isEmpty ? null : supplierInvoices().first['id'].toString();
    double remaining(Map<String, dynamic> invoice) => (((invoice['total'] as num?)?.toDouble() ?? 0) - ((invoice['paid_total'] as num?)?.toDouble() ?? 0)).clamp(0, double.infinity).toDouble();
    final amount = TextEditingController(text: invoiceId == null ? '' : remaining(supplierInvoices().first).toStringAsFixed(2));
    final notes = TextEditingController();
    String cashboxId = cashboxes.first['cashbox_id'].toString();
    String method = 'cash';
    DateTime transactionDate = DateTime.now();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('سداد مستحقات مورد'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: supplierId, isExpanded: true, decoration: const InputDecoration(labelText: 'المورد *'),
            items: suppliers.where((s) => unpaidPurchaseInvoices.any((i) => i['supplier_id'].toString() == s['id'].toString())).map((s) => DropdownMenuItem(value: s['id'].toString(), child: Text(s['name'].toString()))).toList(),
            onChanged: (v) { if (v == null) return; setDialog(() { supplierId = v; final available = supplierInvoices(); invoiceId = available.isEmpty ? null : available.first['id'].toString(); amount.text = available.isEmpty ? '' : remaining(available.first).toStringAsFixed(2); }); },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: invoiceId, isExpanded: true, decoration: const InputDecoration(labelText: 'الفاتورة المستحقة *'),
            items: supplierInvoices().map((i) => DropdownMenuItem(value: i['id'].toString(), child: Text('فاتورة #${i['invoice_number']} • متبقي ${remaining(i).toStringAsFixed(2)} ج.م', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { setDialog(() { invoiceId = v; final found = supplierInvoices().where((i) => i['id'].toString() == v); amount.text = found.isEmpty ? '' : remaining(found.first).toStringAsFixed(2); }); },
          ),
          const SizedBox(height: 10),
          TextFormField(controller: amount, decoration: const InputDecoration(labelText: 'مبلغ السداد *'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); if (n == null || n <= 0) return 'أدخل مبلغًا أكبر من صفر'; final found = supplierInvoices().where((i) => i['id'].toString() == invoiceId); if (found.isEmpty) return 'اختار فاتورة مستحقة'; if (n > remaining(found.first)) return 'المبلغ أكبر من المتبقي على الفاتورة'; return null; }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: cashboxId, isExpanded: true, decoration: const InputDecoration(labelText: 'الخزينة *'), items: cashboxes.map((c) => DropdownMenuItem(value: c['cashbox_id'].toString(), child: Text(c['name'].toString()))).toList(), onChanged: (v) { if (v != null) setDialog(() => cashboxId = v); }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'طريقة الدفع'), items: const [
            DropdownMenuItem(value: 'cash', child: Text('كاش')),
            DropdownMenuItem(value: 'card', child: Text('فيزا')),
            DropdownMenuItem(value: 'instapay', child: Text('إنستا باي')),
            DropdownMenuItem(value: 'wallet', child: Text('محفظة إلكترونية')),
          ], onChanged: (v) { if (v != null) setDialog(() => method = v); }),
          const SizedBox(height: 10),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(context: ctx, initialDate: transactionDate, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)), helpText: 'تاريخ السداد');
              if (picked != null) setDialog(() => transactionDate = picked);
            },
            icon: const Icon(Icons.calendar_month),
            label: Text('تاريخ السداد: ${transactionDate.year}-${transactionDate.month.toString().padLeft(2, '0')}-${transactionDate.day.toString().padLeft(2, '0')}'),
          )),
        ])))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate() && invoiceId != null) Navigator.pop(ctx, {'supplier_id': supplierId, 'invoice_id': invoiceId, 'cashbox_id': cashboxId, 'amount': double.parse(amount.text), 'payment_method': method, 'notes': notes.text.trim(), 'transaction_date': DateTime(transactionDate.year, transactionDate.month, transactionDate.day).toUtc().toIso8601String()}); }, child: const Text('تأكيد السداد')),
        ],
      ),
    )));
    amount.dispose(); notes.dispose();
    if (result == null || !mounted) return;
    setState(() => saving = true);
    try {
      await db.rpc('post_supplier_payment', params: {
        'p_supplier_id': result['supplier_id'],
        'p_purchase_invoice_id': result['invoice_id'],
        'p_cashbox_id': result['cashbox_id'],
        'p_amount': result['amount'],
        'p_payment_method': result['payment_method'],
        'p_transaction_date': result['transaction_date'],
        'p_notes': result['notes'],
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل السداد وتحديث الفاتورة ورصيد الخزينة وكشف المورد')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل سداد المورد: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String transactionLabel(String type) => switch (type) {
    'customer_receipt' => 'تحصيل من عميل',
    'supplier_payment' => 'دفع لمورد',
    'expense' => 'مصروف',
    'other_receipt' => 'قبض آخر',
    'other_payment' => 'صرف آخر',
    'cash_transfer_in' => 'تحويل وارد',
    'cash_transfer_out' => 'تحويل صادر',
    _ => type,
  };
  bool isInflow(String type) => const ['customer_receipt','other_receipt','cash_transfer_in'].contains(type);
  String cashboxName(dynamic id) {
    final found = cashboxes.where((c) => c['cashbox_id'].toString() == id?.toString());
    return found.isEmpty ? 'خزينة غير محددة' : found.first['name'].toString();
  }

  @override
  Widget build(BuildContext context) {
    final totalBalance = cashboxes.fold<double>(0, (sum, c) => sum + ((c['balance'] as num?)?.toDouble() ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('إجمالي أرصدة الخزائن', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(money(totalBalance), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: saving ? null : createCashbox, icon: const Icon(Icons.add_business_outlined), label: const Text('إضافة خزينة')),
          FilledButton.icon(onPressed: saving ? null : addMovement, icon: const Icon(Icons.swap_vert), label: const Text('قبض / صرف')),
          FilledButton.icon(onPressed: saving ? null : addCustomerReceipt, icon: const Icon(Icons.point_of_sale_outlined), label: const Text('تحصيل عميل')),
          FilledButton.icon(onPressed: saving ? null : addSupplierPayment, icon: const Icon(Icons.payments_outlined), label: const Text('سداد مورد')),
          OutlinedButton.icon(onPressed: saving ? null : addExpense, icon: const Icon(Icons.receipt_long_outlined), label: const Text('تسجيل مصروف')),
          IconButton(tooltip: 'تحديث', onPressed: loading ? null : load, icon: const Icon(Icons.refresh)),
        ]),
      ]))),
      const SizedBox(height: 16),
      Text('الخزائن والأرصدة', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (cashboxes.isEmpty && !loading) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد خزائن بعد. أنشئ أول خزينة لتسجيل التحصيل والمصروفات.'))),
      ...cashboxes.map((c) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet_outlined)),
        title: Text('${c['name']}${c['is_default'] == true ? ' • افتراضية' : ''}'),
        subtitle: Text('رصيد افتتاحي: ${money((c['opening_balance'] as num?) ?? 0)}'),
        trailing: Text(money((c['balance'] as num?) ?? 0), style: TextStyle(fontWeight: FontWeight.bold, color: ((c['balance'] as num?) ?? 0) < 0 ? Colors.red : Theme.of(context).colorScheme.primary)),
      ))),
      const SizedBox(height: 16),
      Text('آخر الحركات النقدية', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (transactions.isEmpty && !loading) const Text('لا توجد حركات نقدية حتى الآن.'),
      ...transactions.map((t) {
        final incoming = isInflow(t['transaction_type'].toString());
        return Card(child: ListTile(
          leading: Icon(incoming ? Icons.south_west : Icons.north_east, color: incoming ? Colors.green : Colors.red),
          title: Text(transactionLabel(t['transaction_type'].toString())),
          subtitle: Text('${cashboxName(t['cashbox_id'])} • ${t['notes'] ?? methods[t['payment_method']] ?? ''}'),
          trailing: Text('${incoming ? '+' : '−'}${money((t['amount'] as num?) ?? 0)}', style: TextStyle(fontWeight: FontWeight.bold, color: incoming ? Colors.green : Colors.red)),
        ));
      }),
      const SizedBox(height: 16),
      Text('آخر المصروفات', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (expenses.isEmpty && !loading) const Text('لا توجد مصروفات مسجلة حتى الآن.'),
      ...expenses.map((e) => Card(child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(e['category'].toString()),
        subtitle: Text('${e['description'] ?? 'بدون تفاصيل'} • ${cashboxName(e['cashbox_id'])}'),
        trailing: Text(money((e['amount'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
      ))),
    ]);
  }
}
