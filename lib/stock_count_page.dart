import 'package:flutter/material.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StockCountPage extends StatefulWidget {
  const StockCountPage({super.key});

  @override
  State<StockCountPage> createState() => _StockCountPageState();
}

class _StockCountPageState extends State<StockCountPage> {
  final db = Supabase.instance.client;
  final notes = TextEditingController();
  List<Map<String, dynamic>> warehouses = [];
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> history = [];
  final Map<String, TextEditingController> countedControllers = {};
  String? warehouseId;
  DateTime countDate = DateTime.now();
  bool loading = true, loadingRows = false, saving = false;
  String? error;

  String money(num value) => '${formatMoney(value)} ج.م';
  double number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  String dateText(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    notes.dispose();
    for (final controller in countedControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void clearCountControllers() {
    for (final controller in countedControllers.values) {
      controller.dispose();
    }
    countedControllers.clear();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await Future.wait([
        db.from('warehouses').select('id,name,is_default').eq('is_active', true).order('is_default', ascending: false).order('name'),
        db.from('stock_counts').select('id,count_number,count_date,status,notes,warehouses(name)').order('count_date', ascending: false).limit(15),
      ]);
      if (!mounted) return;
      final loadedWarehouses = List<Map<String, dynamic>>.from(result[0]);
      setState(() {
        warehouses = loadedWarehouses;
        history = List<Map<String, dynamic>>.from(result[1]);
        if (warehouseId == null || !warehouses.any((w) => w['id'].toString() == warehouseId)) {
          warehouseId = warehouses.isEmpty ? null : warehouses.first['id'].toString();
        }
      });
      if (warehouseId != null) {
        await loadRows();
      } else {
        clearCountControllers();
        if (mounted) setState(() => rows = []);
      }
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل الجرد: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadRows() async {
    final selectedWarehouse = warehouseId;
    if (selectedWarehouse == null) return;
    setState(() { loadingRows = true; error = null; });
    try {
      final result = await db.from('stock_balances')
          .select('product_id,product_name,internal_code,warehouse_id,warehouse_name,quantity_on_hand,track_stock,is_low_stock')
          .eq('warehouse_id', selectedWarehouse)
          .eq('track_stock', true)
          .order('product_name');
      if (!mounted || warehouseId != selectedWarehouse) return;
      clearCountControllers();
      final loaded = List<Map<String, dynamic>>.from(result);
      for (final row in loaded) {
        countedControllers[row['product_id'].toString()] =
            TextEditingController(text: number(row['quantity_on_hand']).toStringAsFixed(3).replaceFirst(RegExp(r'\\.?0+$'), ''));
      }
      setState(() => rows = loaded);
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل أرصدة المخزن: $e');
    } finally {
      if (mounted) setState(() => loadingRows = false);
    }
  }

  Future<void> pickCountDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: countDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'تاريخ الجرد',
    );
    if (selected != null && mounted) setState(() => countDate = selected);
  }

  Future<void> postCount() async {
    if (warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف مخزنًا أولًا من الإعدادات')));
      return;
    }
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد أصناف تتبع المخزون في هذا المخزن')));
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = row['product_id'].toString();
      final textValue = countedControllers[id]?.text.trim() ?? '';
      final value = double.tryParse(textValue);
      if (value == null || !value.isFinite || value < 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('راجع الكمية الفعلية للصنف: ${row['product_name']}')));
        return;
      }
      items.add({'product_id': id, 'counted_quantity': value});
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد ترحيل الجرد'),
          content: Text('سيتم اعتماد الكميات الفعلية لـ ${items.length} صنفًا، وإنشاء حركات تسوية للفروق فقط. لا يمكن التراجع عن الجرد المرحّل من هذه الشاشة.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('مراجعة لاحقًا')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ترحيل الجرد')),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => saving = true);
    try {
      final result = await db.rpc('post_stock_count', params: {
        'p_warehouse_id': warehouseId,
        'p_count_date': DateTime(countDate.year, countDate.month, countDate.day, 12).toUtc().toIso8601String(),
        'p_notes': notes.text.trim(),
        'p_items': items,
      });
      if (!mounted) return;
      final data = Map<String, dynamic>.from(result as Map);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم ترحيل الجرد رقم ${data['count_number']} • تمت تسوية ${data['adjusted_items_count']} صنف'),
      ));
      notes.clear();
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل ترحيل الجرد: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 800;
    final differenceCount = rows.where((row) {
      final actual = double.tryParse(countedControllers[row['product_id'].toString()]?.text ?? '');
      return actual != null && (actual - number(row['quantity_on_hand'])).abs() > 0.0005;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading || loadingRows) const LinearProgressIndicator(),
        if (error != null) Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('جرد فعلي وتسوية المخزون', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('اكتب الكمية التي تم عدّها فعليًا. عند الترحيل سيُسجّل النظام الفرق في سجل حركة المخزون بدل تعديل الأرصدة مباشرة.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: warehouseId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'المخزن'),
                items: warehouses.map((w) => DropdownMenuItem(value: w['id'].toString(), child: Text(w['name'].toString()))).toList(),
                onChanged: saving ? null : (v) { if (v == null) return; setState(() => warehouseId = v); loadRows(); },
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(onPressed: saving ? null : pickCountDate, icon: const Icon(Icons.calendar_month), label: Text('تاريخ الجرد: ${dateText(countDate)}')),
                OutlinedButton.icon(onPressed: saving || loadingRows ? null : loadRows, icon: const Icon(Icons.refresh), label: const Text('تحديث أرصدة النظام')),
              ]),
              const SizedBox(height: 12),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات الجرد (اختياري)'), maxLines: 2),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 8, children: [
                Chip(avatar: const Icon(Icons.inventory_2_outlined, size: 18), label: Text('أصناف الجرد: ${rows.length}')),
                Chip(avatar: const Icon(Icons.compare_arrows, size: 18), label: Text('أصناف بها فرق: $differenceCount')),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty && !loadingRows)
          const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد أصناف مخزنية لهذا المخزن. تأكد من تفعيل تتبع المخزون في بيانات الصنف.')))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('الكميات الفعلية', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (wide)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('الصنف')),
                        DataColumn(label: Text('كود الصنف')),
                        DataColumn(label: Text('رصيد النظام')),
                        DataColumn(label: Text('الكمية الفعلية')),
                        DataColumn(label: Text('الفرق')),
                      ],
                      rows: rows.map((row) {
                        final id = row['product_id'].toString();
                        final actual = double.tryParse(countedControllers[id]?.text ?? '') ?? number(row['quantity_on_hand']);
                        final difference = actual - number(row['quantity_on_hand']);
                        return DataRow(cells: [
                          DataCell(Text(row['product_name'].toString())),
                          DataCell(Text((row['internal_code'] ?? '—').toString())),
                          DataCell(Text(number(row['quantity_on_hand']).toStringAsFixed(3))),
                          DataCell(SizedBox(width: 125, child: TextField(
                            controller: countedControllers[id],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            enabled: !saving,
                            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                            onChanged: (_) => setState(() {}),
                          ))),
                          DataCell(Text(difference.toStringAsFixed(3), style: TextStyle(fontWeight: FontWeight.w600, color: difference < 0 ? Colors.red : difference > 0 ? Colors.green : null))),
                        ]);
                      }).toList(),
                    ),
                  )
                else
                  ...rows.map((row) {
                    final id = row['product_id'].toString();
                    final actual = double.tryParse(countedControllers[id]?.text ?? '') ?? number(row['quantity_on_hand']);
                    final difference = actual - number(row['quantity_on_hand']);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .5)), borderRadius: BorderRadius.circular(12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(row['product_name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                          if ((row['internal_code'] ?? '').toString().isNotEmpty) Text('كود: ${row['internal_code']}'),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: Text('رصيد النظام: ${number(row['quantity_on_hand']).toStringAsFixed(3)}')),
                            Text('الفرق: ${difference.toStringAsFixed(3)}', style: TextStyle(color: difference < 0 ? Colors.red : difference > 0 ? Colors.green : null, fontWeight: FontWeight.w600)),
                          ]),
                          const SizedBox(height: 8),
                          TextField(
                            controller: countedControllers[id],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            enabled: !saving,
                            decoration: const InputDecoration(labelText: 'الكمية الفعلية', isDense: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ]),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: saving || loadingRows || rows.isEmpty ? null : postCount,
                  icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.fact_check_outlined),
                  label: Text(saving ? 'جارٍ ترحيل الجرد...' : 'اعتماد وترحيل الجرد'),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 18),
        Text('آخر عمليات الجرد', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد عمليات جرد سابقة.')))
        else
          Card(child: Column(children: history.map((item) {
            final warehouse = item['warehouses'];
            final warehouseName = warehouse is Map ? warehouse['name']?.toString() ?? 'مخزن' : 'مخزن';
            final date = DateTime.tryParse((item['count_date'] ?? '').toString());
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.fact_check_outlined)),
              title: Text('جرد رقم #${item['count_number']}'),
              subtitle: Text('$warehouseName • ${date == null ? '' : dateText(date.toLocal())}${(item['notes'] ?? '').toString().isEmpty ? '' : ' • ${item['notes']}'}'),
              trailing: Chip(label: Text(item['status'] == 'posted' ? 'مُرحّل' : item['status'].toString())),
            );
          }).toList())),
      ],
    );
  }
}
