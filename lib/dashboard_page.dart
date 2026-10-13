import 'package:flutter/material.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final db = Supabase.instance.client;
  bool loading = true;
  String? error;
  double salesToday = 0, profitToday = 0, expensesToday = 0, receivables = 0, payables = 0, stockValue = 0;
  int productCount = 0, lowStockCount = 0;
  List<Map<String, dynamic>> recentSales = [];

  String money(num value) => '${formatMoney(value)} ج.م';

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
      final end = DateTime(now.year, now.month, now.day + 1).toUtc().toIso8601String();
      final results = await Future.wait([
        db.from('sales_invoices').select('id,invoice_number,invoice_date,total,paid_total,payment_status').eq('status','posted').gte('invoice_date',start).lt('invoice_date',end).order('invoice_date',ascending:false),
        db.from('sales_invoices').select('id,total,paid_total').eq('status','posted'),
        db.from('purchase_invoices').select('id,total,paid_total').eq('status','posted'),
        db.from('expenses').select('amount').gte('expense_date',now.toIso8601String().substring(0,10)).lt('expense_date',now.add(const Duration(days:1)).toIso8601String().substring(0,10)),
        db.from('stock_balances').select('product_id,quantity_on_hand,is_low_stock,track_stock'),
        db.from('products').select('id,cost_price,is_active').eq('is_active',true),
      ]);
      final todayInvoices = List<Map<String,dynamic>>.from(results[0] as List);
      final allSales = List<Map<String,dynamic>>.from(results[1] as List);
      final allPurchases = List<Map<String,dynamic>>.from(results[2] as List);
      final expenseRows = List<Map<String,dynamic>>.from(results[3] as List);
      final stockRows = List<Map<String,dynamic>>.from(results[4] as List);
      final products = List<Map<String,dynamic>>.from(results[5] as List);

      final todayIds = todayInvoices.map((i) => i['id'].toString()).toList();
      double profit = 0;
      if (todayIds.isNotEmpty) {
        final items = await db.from('sales_invoice_items').select('invoice_id,quantity,unit_price,unit_cost,discount_amount,tax_amount').inFilter('invoice_id',todayIds);
        for (final raw in items as List) {
          final item = Map<String,dynamic>.from(raw);
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final price = (item['unit_price'] as num?)?.toDouble() ?? 0;
          final cost = (item['unit_cost'] as num?)?.toDouble() ?? 0;
          final discount = (item['discount_amount'] as num?)?.toDouble() ?? 0;
          profit += (qty * price) - discount - (qty * cost);
        }
      }
      final costByProduct = <String,double>{
        for (final p in products) p['id'].toString(): ((p['cost_price'] as num?)?.toDouble() ?? 0)
      };
      double inventory = 0;
      int low = 0;
      for (final row in stockRows) {
        final s = Map<String,dynamic>.from(row);
        if (s['is_low_stock'] == true) low++;
        if (s['track_stock'] == true) {
          inventory += ((s['quantity_on_hand'] as num?)?.toDouble() ?? 0) * (costByProduct[s['product_id'].toString()] ?? 0);
        }
      }
      double outstanding(List<Map<String,dynamic>> rows) => rows.fold<double>(0,(sum,row) {
        final total = (row['total'] as num?)?.toDouble() ?? 0;
        final paid = (row['paid_total'] as num?)?.toDouble() ?? 0;
        return sum + (total - paid).clamp(0, double.infinity);
      });
      if (!mounted) return;
      setState(() {
        salesToday = todayInvoices.fold<double>(0,(s,i)=>s+((i['total'] as num?)?.toDouble() ?? 0));
        profitToday = profit;
        expensesToday = expenseRows.fold<double>(0,(s,e)=>s+((e['amount'] as num?)?.toDouble() ?? 0));
        receivables = outstanding(allSales);
        payables = outstanding(allPurchases);
        stockValue = inventory;
        productCount = products.length;
        lowStockCount = low;
        recentSales = todayInvoices.take(6).toList();
      });
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل مؤشرات لوحة التحكم: $e');
    } finally { if (mounted) setState(() => loading = false); }
  }

  Widget metric(String title, double value, String subtitle, IconData icon, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: .10),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            money(value),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1250 ? 4 : width >= 750 ? 2 : 1;
    final metrics = [
      metric('مبيعات اليوم', salesToday, 'إجمالي الفواتير المرحلة', Icons.point_of_sale_outlined, const Color(0xFF176B55)),
      metric('مجمل ربح اليوم', profitToday, 'قبل الضريبة وبعد الخصومات وتكلفة الأصناف', Icons.trending_up, const Color(0xFF2477C8)),
      metric('مصروفات اليوم', expensesToday, 'المصروفات المسجلة اليوم', Icons.receipt_long_outlined, const Color(0xFFC15B36)),
      metric('قيمة المخزون', stockValue, '‏$productCount صنف نشط', Icons.inventory_2_outlined, const Color(0xFF7C56B3)),
      metric('مديونية العملاء', receivables, 'المتبقي من فواتير البيع', Icons.people_outline, const Color(0xFFB17B18)),
      metric('مستحقات الموردين', payables, 'المتبقي من فواتير الشراء', Icons.local_shipping_outlined, const Color(0xFF6B7280)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Align(alignment: AlignmentDirectional.centerStart, child: OutlinedButton.icon(onPressed: loading ? null : load, icon: const Icon(Icons.refresh), label: const Text('تحديث البيانات'))),
      const SizedBox(height: 12),
      GridView.count(crossAxisCount: columns, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: columns == 1 ? 1.9 : 1.45, children: metrics),
      const SizedBox(height: 18),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text('أحدث فواتير اليوم', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))), Text('مخزون منخفض: $lowStockCount', style: TextStyle(color: lowStockCount > 0 ? Colors.deepOrange : Colors.green, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 12),
        if (recentSales.isEmpty && !loading) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد فواتير مبيعات مرحلة اليوم.')),
        ...recentSales.map((i) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
          title: Text('فاتورة بيع #${i['invoice_number'] ?? ''}'),
          subtitle: Text('${i['invoice_date'] ?? ''} • ${i['payment_status'] ?? ''}'),
          trailing: Text(money((i['total'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
        )),
      ]))),
      const SizedBox(height: 8),
      Text('الأرقام تُحسب من الفواتير والحركات المسجلة. مجمل الربح تقديري وفق تكلفة الصنف المحفوظة في فاتورة البيع.', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
