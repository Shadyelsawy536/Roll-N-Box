import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final db = Supabase.instance.client;
  late DateTime fromDate;
  late DateTime toDate;
  bool loading = false;
  String? error;
  List<Map<String, dynamic>> sales = [];
  List<Map<String, dynamic>> purchases = [];
  List<Map<String, dynamic>> expenses = [];
  List<Map<String, dynamic>> salesReturns = [];
  List<Map<String, dynamic>> purchaseReturns = [];
  List<Map<String, dynamic>> stockMovements = [];
  List<Map<String, dynamic>> cashMovements = [];
  List<Map<String, dynamic>> cashboxes = [];
  List<Map<String, dynamic>> inventoryRows = [];
  double stockCostValue = 0;
  double stockSaleValue = 0;
  int lowStockRows = 0;
  double grossProfit = 0;
  double salesRevenueExTax = 0;
  double costOfGoodsSold = 0;
  double returnedRevenueExTax = 0;
  double returnedCost = 0;
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> suppliers = [];
  String statementType = 'customer';
  String? statementPartyId;
  bool statementLoading = false;
  String? statementError;
  List<Map<String, dynamic>> statementRows = [];
  double statementOpening = 0;
  double statementDebit = 0;
  double statementCredit = 0;
  double statementClosing = 0;
  String statementPartyName = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    fromDate = DateTime(now.year, now.month, 1);
    toDate = DateTime(now.year, now.month, now.day);
    load();
    loadParties();
  }

  String dateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String money(num value) => '${formatMoney(value)} ج.م';
  double number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;


  Future<void> loadParties() async {
    try {
      final result = await Future.wait([
        db.from('customers').select('id,name,opening_balance,opening_balance_date').eq('is_active', true).order('name'),
        db.from('suppliers').select('id,name,opening_balance,opening_balance_date').eq('is_active', true).order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        customers = List<Map<String, dynamic>>.from(result[0]);
        suppliers = List<Map<String, dynamic>>.from(result[1]);
        final parties = statementType == 'customer' ? customers : suppliers;
        if (statementPartyId == null || !parties.any((p) => p['id'].toString() == statementPartyId)) {
          statementPartyId = parties.isEmpty ? null : parties.first['id'].toString();
        }
      });
      await loadStatement();
    } catch (e) {
      if (mounted) setState(() => statementError = 'تعذر تحميل العملاء والموردين: $e');
    }
  }

  Future<void> loadStatement() async {
    final parties = statementType == 'customer' ? customers : suppliers;
    final selectedId = statementPartyId;
    if (selectedId == null || !parties.any((p) => p['id'].toString() == selectedId)) {
      if (mounted) setState(() {
        statementRows = [];
        statementOpening = statementDebit = statementCredit = statementClosing = 0;
        statementPartyName = '';
      });
      return;
    }
    setState(() { statementLoading = true; statementError = null; });
    try {
      final party = parties.firstWhere((p) => p['id'].toString() == selectedId);
      final isCustomer = statementType == 'customer';
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
      final end = DateTime(toDate.year, toDate.month, toDate.day + 1);
      final endIso = end.toUtc().toIso8601String();
      final invoicesQuery = isCustomer
          ? db.from('sales_invoices').select('id,invoice_number,invoice_date,total,paid_total,status').eq('customer_id', selectedId).eq('status', 'posted').lt('invoice_date', endIso).order('invoice_date').limit(5000)
          : db.from('purchase_invoices').select('id,invoice_number,invoice_date,total,paid_total,status').eq('supplier_id', selectedId).eq('status', 'posted').lt('invoice_date', endIso).order('invoice_date').limit(5000);
      final txQuery = db.from('cash_transactions')
          .select('id,transaction_type,amount,transaction_date,notes,reference_id,reference_type')
          .eq(isCustomer ? 'customer_id' : 'supplier_id', selectedId)
          .lt('transaction_date', endIso).order('transaction_date').limit(5000);
      final returnsQuery = isCustomer
          ? db.from('sales_returns').select('id,return_number,return_date,total').eq('customer_id', selectedId).lt('return_date', endIso).order('return_date').limit(5000)
          : db.from('purchase_returns').select('id,return_number,return_date,total').eq('supplier_id', selectedId).lt('return_date', endIso).order('return_date').limit(5000);
      final result = await Future.wait([invoicesQuery, txQuery, returnsQuery]);
      final invoices = List<Map<String, dynamic>>.from(result[0]);
      final transactions = List<Map<String, dynamic>>.from(result[1]);
      final returns = List<Map<String, dynamic>>.from(result[2]);
      double opening = number(party['opening_balance']);
      final openingDate = party['opening_balance_date'] == null
          ? null
          : DateTime.tryParse(party['opening_balance_date'].toString());
      if (openingDate != null && !openingDate.isBefore(start)) opening = 0;
      final entries = <Map<String, dynamic>>[];
      if (openingDate != null && !openingDate.isBefore(start) && openingDate.isBefore(end) && number(party['opening_balance']) != 0) {
        final openingAmount = number(party['opening_balance']);
        entries.add({
          'date': openingDate,
          'title': 'رصيد افتتاحي',
          'debit': isCustomer ? openingAmount : 0.0,
          'credit': isCustomer ? 0.0 : openingAmount,
          'amount': openingAmount,
        });
      }
      for (final invoice in invoices) {
        final date = DateTime.tryParse(invoice['invoice_date'].toString());
        if (date == null) continue;
        final amount = number(invoice['total']);
        final isBefore = date.isBefore(start);
        final sign = isCustomer ? 1.0 : 1.0;
        if (isBefore) {
          opening += sign * amount;
        } else {
          entries.add({
            'date': date,
            'title': isCustomer ? 'فاتورة بيع #${invoice['invoice_number']}' : 'فاتورة شراء #${invoice['invoice_number']}',
            'debit': isCustomer ? amount : 0.0,
            'credit': isCustomer ? 0.0 : amount,
            'amount': amount,
          });
        }
      }
      for (final tx in transactions) {
        final type = (tx['transaction_type'] ?? '').toString();
        final date = DateTime.tryParse(tx['transaction_date'].toString());
        if (date == null) continue;
        final amount = number(tx['amount']);
        final isPartyReceipt = isCustomer && type == 'customer_receipt';
        final isPartyPayment = !isCustomer && type == 'supplier_payment';
        if (!isPartyReceipt && !isPartyPayment) continue;
        if (date.isBefore(start)) {
          opening -= amount;
        } else {
          entries.add({
            'date': date,
            'title': isCustomer ? 'تحصيل من العميل' : 'سداد للمورد',
            'debit': isCustomer ? 0.0 : amount,
            'credit': isCustomer ? amount : 0.0,
            'amount': amount,
          });
        }
      }
      for (final ret in returns) {
        final date = DateTime.tryParse(ret['return_date'].toString());
        if (date == null) continue;
        final value = number(ret['total']);
        if (date.isBefore(start)) {
          opening += isCustomer ? -value : -value;
        } else {
          entries.add({
            'date': date,
            'title': isCustomer ? 'مرتجع مبيعات #${ret['return_number']}' : 'مرتجع مشتريات #${ret['return_number']}',
            'debit': isCustomer ? 0.0 : value,
            'credit': isCustomer ? value : 0.0,
            'amount': value,
          });
        }
      }
      entries.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
      double debit = 0, credit = 0, running = opening;
      for (final entry in entries) {
        debit += number(entry['debit']);
        credit += number(entry['credit']);
        running += isCustomer ? number(entry['debit']) - number(entry['credit']) : number(entry['credit']) - number(entry['debit']);
        entry['balance'] = running;
      }
      if (!mounted) return;
      setState(() {
        statementPartyName = (party['name'] ?? '').toString();
        statementOpening = opening;
        statementRows = entries;
        statementDebit = debit;
        statementCredit = credit;
        statementClosing = running;
      });
    } catch (e) {
      if (mounted) setState(() => statementError = 'تعذر تحميل كشف الحساب: $e');
    } finally {
      if (mounted) setState(() => statementLoading = false);
    }
  }

  Future<void> pickDate({required bool start}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: start ? fromDate : toDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: start ? 'اختر بداية الفترة' : 'اختر نهاية الفترة',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        fromDate = selected;
        if (toDate.isBefore(fromDate)) toDate = fromDate;
      } else {
        toDate = selected;
        if (fromDate.isAfter(toDate)) fromDate = toDate;
      }
    });
    await load();
    await loadStatement();
  }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
      final end = DateTime(toDate.year, toDate.month, toDate.day + 1);
      final startIso = start.toUtc().toIso8601String();
      final endIso = end.toUtc().toIso8601String();
      final results = await Future.wait([
        db.from('sales_invoices')
            .select('id,invoice_number,invoice_date,total,paid_total,payment_status,customer_id')
            .eq('status', 'posted')
            .gte('invoice_date', startIso).lt('invoice_date', endIso)
            .order('invoice_date', ascending: false).limit(1000),
        db.from('purchase_invoices')
            .select('id,invoice_number,invoice_date,total,paid_total,payment_status,supplier_id')
            .eq('status', 'posted')
            .gte('invoice_date', startIso).lt('invoice_date', endIso)
            .order('invoice_date', ascending: false).limit(1000),
        db.from('expenses')
            .select('id,category,description,amount,expense_date,payment_method')
            .gte('expense_date', dateText(start))
            .lte('expense_date', dateText(DateTime(toDate.year, toDate.month, toDate.day)))
            .order('expense_date', ascending: false).limit(1000),
        db.from('stock_balances').select('product_id,product_name,internal_code,minimum_stock,track_stock,warehouse_id,warehouse_name,quantity_on_hand,is_low_stock').order('product_name'),
        db.from('products').select('id,name,cost_price,sale_price,is_active').eq('is_active', true),
        db.from('sales_returns').select('id,return_number,return_date,total,refund_amount').eq('status', 'posted').gte('return_date', startIso).lt('return_date', endIso).order('return_date', ascending: false).limit(1000),
        db.from('purchase_returns').select('id,return_number,return_date,total,received_amount').eq('status', 'posted').gte('return_date', startIso).lt('return_date', endIso).order('return_date', ascending: false).limit(1000),
        db.from('stock_movements').select('id,product_id,warehouse_id,movement_type,quantity_delta,unit_cost,reference_type,occurred_at,notes').gte('occurred_at', startIso).lt('occurred_at', endIso).order('occurred_at', ascending: false).limit(2000),
        db.from('cash_transactions').select('id,cashbox_id,transaction_type,amount,payment_method,transaction_date,notes,reference_type').gte('transaction_date', startIso).lt('transaction_date', endIso).order('transaction_date', ascending: false).limit(2000),
        db.from('cashboxes').select('id,name,opening_balance,is_active').eq('is_active', true).order('name'),
      ]);
      final salesRows = List<Map<String, dynamic>>.from(results[0]);
      final purchaseRows = List<Map<String, dynamic>>.from(results[1]);
      final expenseRows = List<Map<String, dynamic>>.from(results[2]);
      final balances = List<Map<String, dynamic>>.from(results[3]);
      final productRows = List<Map<String, dynamic>>.from(results[4]);
      final salesReturnRows = List<Map<String, dynamic>>.from(results[5]);
      final purchaseReturnRows = List<Map<String, dynamic>>.from(results[6]);
      final stockMovementRows = List<Map<String, dynamic>>.from(results[7]);
      final cashMovementRows = List<Map<String, dynamic>>.from(results[8]);
      final cashboxRows = List<Map<String, dynamic>>.from(results[9]);
      final prices = <String, Map<String, dynamic>>{
        for (final product in productRows) product['id'].toString(): product,
      };
      final stockRows = balances.map((balance) {
        final price = prices[balance['product_id'].toString()] ?? const <String, dynamic>{};
        return <String, dynamic>{
          ...balance,
          'cost_price': price['cost_price'] ?? 0,
          'sale_price': price['sale_price'] ?? 0,
        };
      }).toList();
      double costValue = 0;
      double saleValue = 0;
      for (final row in stockRows) {
        final quantity = number(row['quantity_on_hand']);
        if (row['track_stock'] == true) {
          costValue += quantity * number(row['cost_price']);
          saleValue += quantity * number(row['sale_price']);
        }
      }
      final lowRows = stockRows.where((row) => row['is_low_stock'] == true).length;
      double profit = 0;
      double revenueExTax = 0;
      double cogs = 0;
      double returnedRevenue = 0;
      double cogsReturned = 0;
      final ids = salesRows.map((row) => row['id'].toString()).toList();
      if (ids.isNotEmpty) {
        final itemRows = await db.from('sales_invoice_items')
            .select('id,invoice_id,quantity,unit_price,unit_cost,discount_amount,tax_amount')
            .inFilter('invoice_id', ids);
        for (final raw in itemRows as List) {
          final item = Map<String, dynamic>.from(raw);
          final quantity = number(item['quantity']);
          final lineRevenue = quantity * number(item['unit_price']) - number(item['discount_amount']);
          final lineCost = quantity * number(item['unit_cost']);
          revenueExTax += lineRevenue;
          cogs += lineCost;
          profit += lineRevenue - lineCost;
        }
      }
      final returnIds = salesReturnRows.map((row) => row['id'].toString()).toList();
      if (returnIds.isNotEmpty) {
        final returnItems = await db.from('sales_return_items')
            .select('return_id,sales_invoice_item_id,quantity,unit_price,unit_cost,line_total')
            .inFilter('return_id', returnIds);
        final sourceItemIds = returnItems
            .map((raw) => (raw as Map)['sales_invoice_item_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
        final sourceItemsById = <String, Map<String, dynamic>>{};
        if (sourceItemIds.isNotEmpty) {
          final sourceItems = await db.from('sales_invoice_items')
              .select('id,quantity,unit_price,unit_cost,discount_amount,tax_amount')
              .inFilter('id', sourceItemIds);
          for (final raw in sourceItems as List) {
            final item = Map<String, dynamic>.from(raw);
            sourceItemsById[item['id'].toString()] = item;
          }
        }
        for (final raw in returnItems as List) {
          final item = Map<String, dynamic>.from(raw);
          final quantity = number(item['quantity']);
          final source = sourceItemsById[item['sales_invoice_item_id']?.toString()];
          final originalQuantity = source == null ? 0.0 : number(source['quantity']);
          final originalDiscount = source == null ? 0.0 : number(source['discount_amount']);
          final discountReturned = originalQuantity > 0
              ? originalDiscount * quantity / originalQuantity
              : 0.0;
          final returnedLineRevenue = quantity * number(item['unit_price']) - discountReturned;
          final returnedLineCost = quantity * number(item['unit_cost']);
          returnedRevenue += returnedLineRevenue;
          cogsReturned += returnedLineCost;
          profit -= returnedLineRevenue - returnedLineCost;
        }
      }
      final productNames = <String, String>{
        for (final p in productRows) p['id'].toString(): (p['name'] ?? 'صنف').toString(),
      };
      final cashboxNames = <String, String>{
        for (final box in cashboxRows) box['id'].toString(): (box['name'] ?? 'خزنة').toString(),
      };
      final enrichedStockMovements = stockMovementRows.map((row) => <String, dynamic>{
        ...row,
        'product_name': productNames[row['product_id']?.toString()] ?? 'صنف غير معروف',
      }).toList();
      final enrichedCashMovements = cashMovementRows.map((row) => <String, dynamic>{
        ...row,
        'cashbox_name': cashboxNames[row['cashbox_id']?.toString()] ?? 'خزنة غير معروفة',
      }).toList();
      if (!mounted) return;
      setState(() {
        sales = salesRows;
        purchases = purchaseRows;
        expenses = expenseRows;
        salesReturns = salesReturnRows;
        purchaseReturns = purchaseReturnRows;
        stockMovements = enrichedStockMovements;
        cashMovements = enrichedCashMovements;
        cashboxes = cashboxRows;
        inventoryRows = stockRows;
        stockCostValue = costValue;
        stockSaleValue = saleValue;
        lowStockRows = lowRows;
        grossProfit = profit;
        salesRevenueExTax = revenueExTax;
        costOfGoodsSold = cogs;
        returnedRevenueExTax = returnedRevenue;
        returnedCost = cogsReturned;
      });
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل التقرير. راجع الاتصال والصلاحيات ثم حاول مجددًا.\n$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  double sum(List<Map<String, dynamic>> rows, String key) =>
      rows.fold<double>(0, (total, row) => total + number(row[key]));

  Widget summary(String title, double amount, IconData icon, Color color, {String? note}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: color.withValues(alpha: .12),
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
              const SizedBox(height: 10),
              Text(
                money(amount),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (note != null) ...[
                const SizedBox(height: 5),
                Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      );

  Widget invoiceList(String title, List<Map<String, dynamic>> rows, {required bool salesInvoices}) =>
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد بيانات في الفترة المحددة.')),
          ...rows.take(12).map((row) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Icon(salesInvoices ? Icons.point_of_sale_outlined : Icons.shopping_bag_outlined)),
            title: Text('${salesInvoices ? 'فاتورة بيع' : 'فاتورة شراء'} #${row['invoice_number'] ?? '—'}'),
            subtitle: Text('${row['invoice_date'] ?? ''} • ${row['payment_status'] ?? ''}'),
            trailing: Text(money(number(row['total'])), style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          if (rows.length > 12) Text('يتم عرض أحدث 12 فاتورة من أصل ${rows.length}.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ));

  CellValue _excelCell(dynamic value) {
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue(value?.toString() ?? '');
  }

  Future<void> exportExcel() async {
    try {
      final workbook = Excel.createExcel();
      final summary = workbook['Summary'];
      final revenue = sum(sales, 'total');
      final expensesTotal = sum(expenses, 'amount');
      final net = grossProfit - expensesTotal;
      final summaryRows = <List<dynamic>>[
        ['Report', 'Value'],
        ['Period from', dateText(fromDate)],
        ['Period to', dateText(toDate)],
        ['Sales total', revenue],
        ['Sales excluding tax', salesRevenueExTax],
        ['Purchases total', sum(purchases, 'total')],
        ['Sales returns', sum(salesReturns, 'total')],
        ['Purchase returns', sum(purchaseReturns, 'total')],
        ['Expenses', expensesTotal],
        ['Gross profit after sales returns', grossProfit],
        ['Net after expenses (before taxes/withdrawals)', net],
        ['Inventory cost value', stockCostValue],
        ['Inventory sale value', stockSaleValue],
        ['Low-stock rows', lowStockRows],
      ];
      for (final row in summaryRows) {
        summary.appendRow(row.map(_excelCell).toList());
      }
      final salesSheet = workbook['Sales'];
      salesSheet.appendRow(['Invoice number', 'Date', 'Total', 'Paid', 'Outstanding', 'Status'].map(_excelCell).toList());
      for (final row in sales) {
        salesSheet.appendRow([
          row['invoice_number'], row['invoice_date'], number(row['total']),
          number(row['paid_total']), number(row['total']) - number(row['paid_total']),
          row['payment_status'],
        ].map(_excelCell).toList());
      }
      final purchaseSheet = workbook['Purchases'];
      purchaseSheet.appendRow(['Invoice number', 'Date', 'Total', 'Paid', 'Outstanding', 'Status'].map(_excelCell).toList());
      for (final row in purchases) {
        purchaseSheet.appendRow([
          row['invoice_number'], row['invoice_date'], number(row['total']),
          number(row['paid_total']), number(row['total']) - number(row['paid_total']),
          row['payment_status'],
        ].map(_excelCell).toList());
      }
      final expenseSheet = workbook['Expenses'];
      expenseSheet.appendRow(['Date', 'Category', 'Description', 'Amount', 'Payment method'].map(_excelCell).toList());
      for (final row in expenses) {
        expenseSheet.appendRow([
          row['expense_date'], row['category'], row['description'],
          number(row['amount']), row['payment_method'],
        ].map(_excelCell).toList());
      }
      final returnsSheet = workbook['Returns'];
      returnsSheet.appendRow(['Type', 'Return number', 'Date', 'Total', 'Cash amount'].map(_excelCell).toList());
      for (final row in salesReturns) {
        returnsSheet.appendRow(['Sales', row['return_number'], row['return_date'], number(row['total']), number(row['refund_amount'])].map(_excelCell).toList());
      }
      for (final row in purchaseReturns) {
        returnsSheet.appendRow(['Purchase', row['return_number'], row['return_date'], number(row['total']), number(row['received_amount'])].map(_excelCell).toList());
      }
      final stockSheet = workbook['Inventory'];
      stockSheet.appendRow(['Product', 'Code', 'Warehouse', 'Quantity', 'Cost price', 'Sale price', 'Low stock'].map(_excelCell).toList());
      for (final row in inventoryRows) {
        stockSheet.appendRow([
          row['product_name'], row['internal_code'], row['warehouse_name'],
          number(row['quantity_on_hand']), number(row['cost_price']),
          number(row['sale_price']), row['is_low_stock'] == true ? 'Yes' : 'No',
        ].map(_excelCell).toList());
      }
      final bytes = workbook.encode();
      if (bytes == null) throw Exception('Could not generate Excel file');
      await FileSaver.instance.saveFile(
        name: 'inventory-report-${dateText(fromDate)}-${dateText(toDate)}',
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصدير تقرير Excel بنجاح')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تصدير Excel: $e')));
    }
  }

  Future<void> exportPdf() async {
    try {
      final expensesTotal = sum(expenses, 'amount');
      final document = pw.Document();
      document.addPage(pw.MultiPage(
        build: (_) => [
          pw.Text('Inventory Management Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Period: ${dateText(fromDate)} to ${dateText(toDate)}'),
          pw.SizedBox(height: 16),
          pw.Table.fromTextArray(data: [
            ['Metric', 'Value (EGP)'],
            ['Sales total', formatMoney(sum(sales, 'total'))],
            ['Sales excluding tax', formatMoney(salesRevenueExTax)],
            ['Purchases total', formatMoney(sum(purchases, 'total'))],
            ['Sales returns', formatMoney(sum(salesReturns, 'total'))],
            ['Purchase returns', formatMoney(sum(purchaseReturns, 'total'))],
            ['Expenses', formatMoney(expensesTotal)],
            ['Gross profit after sales returns', formatMoney(grossProfit)],
            ['Net after expenses (before taxes/withdrawals)', formatMoney(grossProfit - expensesTotal)],
            ['Inventory cost value', formatMoney(stockCostValue)],
            ['Inventory sale value', formatMoney(stockSaleValue)],
            ['Low-stock rows', '$lowStockRows'],
          ]),
          pw.SizedBox(height: 16),
          pw.Text('Sales invoices: ${sales.length}'),
          pw.Text('Purchase invoices: ${purchases.length}'),
          pw.Text('Expenses: ${expenses.length}'),
          pw.Text('Sales returns: ${salesReturns.length}'),
          pw.Text('Purchase returns: ${purchaseReturns.length}'),
          pw.SizedBox(height: 8),
          pw.Text('This summary is based on records loaded for the selected period. Net result is before taxes and unrecorded withdrawals.'),
        ],
      ));
      await Printing.layoutPdf(
        name: 'inventory-report-${dateText(fromDate)}-${dateText(toDate)}.pdf',
        onLayout: (_) async => document.save(),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تصدير PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1200 ? 4 : width >= 760 ? 2 : 1;
    final revenue = sum(sales, 'total');
    final costPurchases = sum(purchases, 'total');
    final expensesTotal = sum(expenses, 'amount');
    final salesReturnsTotal = sum(salesReturns, 'total');
    final purchaseReturnsTotal = sum(purchaseReturns, 'total');
    final netAfterExpenses = grossProfit - expensesTotal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 12, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الفترة الزمنية', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${dateText(fromDate)} إلى ${dateText(toDate)}'),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: loading ? null : () => pickDate(start: true), icon: const Icon(Icons.calendar_month), label: Text('من: ${dateText(fromDate)}')),
            OutlinedButton.icon(onPressed: loading ? null : () => pickDate(start: false), icon: const Icon(Icons.event), label: Text('إلى: ${dateText(toDate)}')),
            FilledButton.icon(onPressed: loading ? null : load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
            OutlinedButton.icon(onPressed: loading ? null : exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('تصدير PDF')),
            OutlinedButton.icon(onPressed: loading ? null : exportExcel, icon: const Icon(Icons.table_view_outlined), label: const Text('تصدير Excel')),
          ]),
        ]),
      )),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('صافي الربح للفترة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(money(netAfterExpenses), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: netAfterExpenses >= 0 ? const Color(0xFF176B55) : Colors.red)), const SizedBox(height: 6), const Text('مجمل الربح بعد تكلفة البضاعة والمرتجعات ناقص مصروفات الفترة.'), Text('قبل الضرائب وأي مسحوبات أو توزيعات شركاء غير مسجلة كمصروفات.', style: Theme.of(context).textTheme.bodySmall)]))),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: columns, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12, crossAxisSpacing: 12,
        childAspectRatio: columns == 1 ? 1.9 : 1.55,
        children: [
          summary('إجمالي المبيعات', revenue, Icons.trending_up, const Color(0xFF176B55), note: '${sales.length} فاتورة مرحلة، شامل الضريبة'),
          summary('المبيعات بدون الضريبة', salesRevenueExTax, Icons.receipt_long_outlined, const Color(0xFF2477C8), note: 'بعد خصم خصومات الفواتير'),
          summary('تكلفة البضاعة المباعة', costOfGoodsSold, Icons.inventory_2_outlined, const Color(0xFF7C56B3), note: 'تكلفة الأصناف وقت البيع'),
          summary('مرتجعات المبيعات', salesReturnsTotal, Icons.assignment_return_outlined, const Color(0xFFC15B36), note: '${salesReturns.length} مرتجع في الفترة، شامل الضريبة'),
          summary('قيمة المبيعات المرتجعة بدون الضريبة', returnedRevenueExTax, Icons.keyboard_return_outlined, const Color(0xFFC15B36), note: 'بعد توزيع الخصم الأصلي على الكمية المرتجعة'),
          summary('تكلفة البضاعة المرتجعة', returnedCost, Icons.inventory_2_outlined, const Color(0xFF7C56B3), note: 'تُضاف مرة أخرى لمجمل الربح'),
          summary('مرتجعات المشتريات', purchaseReturnsTotal, Icons.keyboard_return_outlined, const Color(0xFF7C56B3), note: '${purchaseReturns.length} مرتجع في الفترة'),
          summary('مجمل الربح بعد مرتجعات البيع', grossProfit, Icons.insights_outlined, const Color(0xFF2477C8), note: 'بعد تكلفة البضاعة وتكلفة المرتجعات'),
          summary('المشتريات', costPurchases, Icons.shopping_bag_outlined, const Color(0xFF7C56B3), note: '${purchases.length} فاتورة مرحلة'),
          summary('المصروفات', expensesTotal, Icons.receipt_long_outlined, const Color(0xFFC15B36), note: '${expenses.length} حركة مصروف'),
          summary('الربح بعد المصروفات', netAfterExpenses, Icons.account_balance_wallet_outlined, netAfterExpenses >= 0 ? const Color(0xFF176B55) : Colors.red, note: 'مجمل الربح ناقص المصروفات'),
          summary('المتبقي من المبيعات', sales.fold<double>(0, (v, row) => v + (number(row['total']) - number(row['paid_total'])).clamp(0, double.infinity)), Icons.people_outline, const Color(0xFFB17B18)),
          summary('المتبقي للموردين', purchases.fold<double>(0, (v, row) => v + (number(row['total']) - number(row['paid_total'])).clamp(0, double.infinity)), Icons.local_shipping_outlined, const Color(0xFF6B7280)),
          summary('صافي حركة المبيعات', revenue - costPurchases - expensesTotal, Icons.calculate_outlined, const Color(0xFF405B78), note: 'مبيعات − مشتريات − مصروفات؛ ليس صافي ربح محاسبي'),
        ],
      ),
      const SizedBox(height: 18),
      Text('تقرير حركة المخزون خلال الفترة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('إجمالي الحركات: ${stockMovements.length}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (stockMovements.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد حركات مخزون في الفترة المحددة.')),
          ...stockMovements.take(30).map((row) {
            final qty = number(row['quantity_delta']);
            final value = qty.abs() * number(row['unit_cost']);
            final date = DateTime.tryParse((row['occurred_at'] ?? '').toString());
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(qty >= 0 ? Icons.south_west : Icons.north_east, color: qty >= 0 ? Colors.green : Colors.deepOrange)),
              title: Text((row['product_name'] ?? 'صنف').toString()),
              subtitle: Text('${date == null ? '' : dateText(date.toLocal())} • ${row['movement_type'] ?? 'حركة'} • ${row['reference_type'] ?? ''}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${qty >= 0 ? '+' : ''}${qty.toStringAsFixed(3)} وحدة', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(money(value), style: Theme.of(context).textTheme.bodySmall),
              ]),
            );
          }),
          if (stockMovements.length > 30) Text('يتم عرض أحدث 30 حركة من أصل ${stockMovements.length}.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      )),
      const SizedBox(height: 18),
      Text('تقرير المخزون الحالي', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: columns, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12, crossAxisSpacing: 12,
        childAspectRatio: columns == 1 ? 1.9 : 1.55,
        children: [
          summary('قيمة المخزون بالتكلفة', stockCostValue, Icons.inventory_2_outlined, const Color(0xFF176B55), note: 'الأصناف التي تتبع المخزون'),
          summary('القيمة بسعر البيع', stockSaleValue, Icons.sell_outlined, const Color(0xFF2477C8), note: 'قيمة تقديرية قبل البيع'),
          summary('أرصدة منخفضة', lowStockRows.toDouble(), Icons.warning_amber_outlined, const Color(0xFFC15B36), note: 'صنف/مخزن عند الحد الأدنى أو أقل'),
        ],
      ),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('الأرصدة حسب المخزن', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (inventoryRows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد أرصدة لعرضها. تأكد من إضافة مخزن نشط وتسجيل حركات مخزون.')),
          ...inventoryRows.take(100).map((row) {
            final low = row['is_low_stock'] == true;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(low ? Icons.warning_amber_outlined : Icons.inventory_2_outlined, color: low ? Colors.deepOrange : null)),
              title: Text((row['product_name'] ?? 'صنف').toString()),
              subtitle: Text('${row['warehouse_name'] ?? 'مخزن'} • ${row['internal_code'] ?? 'بدون كود'} • حد التنبيه: ${row['minimum_stock'] ?? 0}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${number(row['quantity_on_hand']).toStringAsFixed(3)} وحدة', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (low) const Text('مخزون منخفض', style: TextStyle(color: Colors.deepOrange, fontSize: 11)),
              ]),
            );
          }),
          if (inventoryRows.length > 100) Text('يتم عرض أول 100 رصيد من أصل ${inventoryRows.length}.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      )),
      const SizedBox(height: 18),
      invoiceList('فواتير المبيعات في الفترة', sales, salesInvoices: true),
      const SizedBox(height: 12),
      invoiceList('فواتير المشتريات في الفترة', purchases, salesInvoices: false),
      const SizedBox(height: 12),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('تفاصيل المصروفات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (expenses.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد مصروفات في الفترة المحددة.')),
          ...expenses.take(20).map((row) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
            title: Text((row['description'] ?? row['category'] ?? 'مصروف').toString()),
            subtitle: Text('${row['expense_date'] ?? ''} • ${row['category'] ?? ''}'),
            trailing: Text(money(number(row['amount'])), style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          if (expenses.length > 20) Text('يتم عرض أحدث 20 مصروفًا من أصل ${expenses.length}.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      )),

      const SizedBox(height: 22),
      Text('حركة الخزائن والتسويات اليومية', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      GridView.count(
        crossAxisCount: columns, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12, crossAxisSpacing: 12,
        childAspectRatio: columns == 1 ? 1.9 : 1.55,
        children: [
          summary('إجمالي المقبوضات', cashMovements.where((r) => const ['customer_receipt','other_receipt','cash_transfer_in'].contains(r['transaction_type'])).fold<double>(0, (s,r) => s + number(r['amount'])), Icons.call_received, const Color(0xFF176B55)),
          summary('إجمالي المدفوعات', cashMovements.where((r) => const ['supplier_payment','expense','other_payment','cash_transfer_out'].contains(r['transaction_type'])).fold<double>(0, (s,r) => s + number(r['amount'])), Icons.call_made, const Color(0xFFC15B36)),
          summary('صافي حركة الخزائن', cashMovements.fold<double>(0, (s,r) { final type = (r['transaction_type'] ?? '').toString(); final amount = number(r['amount']); if (const ['customer_receipt','other_receipt','cash_transfer_in'].contains(type)) return s + amount; if (const ['supplier_payment','expense','other_payment','cash_transfer_out'].contains(type)) return s - amount; return s; }), Icons.account_balance_wallet_outlined, const Color(0xFF2477C8)),
        ],
      ),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('تفاصيل حركة الخزائن', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (cashMovements.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد حركات خزينة في الفترة المحددة.')),
          ...cashMovements.take(30).map((row) {
            final type = (row['transaction_type'] ?? '').toString();
            final incoming = const ['customer_receipt','other_receipt','cash_transfer_in'].contains(type);
            final date = DateTime.tryParse((row['transaction_date'] ?? '').toString());
            final label = switch (type) {
              'customer_receipt' => 'تحصيل من عميل',
              'supplier_payment' => 'سداد لمورد',
              'expense' => 'مصروف',
              'other_receipt' => 'مقبوضات أخرى',
              'other_payment' => 'مدفوعات أخرى',
              'cash_transfer_in' => 'تحويل وارد',
              'cash_transfer_out' => 'تحويل صادر',
              _ => type,
            };
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(incoming ? Icons.south_west : Icons.north_east, color: incoming ? Colors.green : Colors.deepOrange)),
              title: Text(label),
              subtitle: Text('${row['cashbox_name'] ?? 'خزنة'} • ${date == null ? '' : dateText(date.toLocal())} • ${row['payment_method'] ?? ''}'),
              trailing: Text('${incoming ? '+' : '-'}${money(number(row['amount']))}', style: TextStyle(fontWeight: FontWeight.bold, color: incoming ? Colors.green : Colors.deepOrange)),
            );
          }),
          if (cashMovements.length > 30) Text('يتم عرض أحدث 30 حركة من أصل ${cashMovements.length}.', style: Theme.of(context).textTheme.bodySmall),
          const Divider(),
          Text('الخزائن النشطة: ${cashboxes.length}', style: Theme.of(context).textTheme.bodySmall),
        ]),
      )),
      const SizedBox(height: 22),
      Text('كشوف حساب العملاء والموردين', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: width >= 700 ? 220 : double.infinity, child: DropdownButtonFormField<String>(
              value: statementType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'نوع الحساب'),
              items: const [
                DropdownMenuItem(value: 'customer', child: Text('كشف حساب عميل')),
                DropdownMenuItem(value: 'supplier', child: Text('كشف حساب مورد')),
              ],
              onChanged: statementLoading ? null : (value) async {
                if (value == null) return;
                setState(() {
                  statementType = value;
                  final parties = value == 'customer' ? customers : suppliers;
                  statementPartyId = parties.isEmpty ? null : parties.first['id'].toString();
                });
                await loadStatement();
              },
            )),
            SizedBox(width: width >= 700 ? 320 : double.infinity, child: DropdownButtonFormField<String>(
              value: statementPartyId,
              isExpanded: true,
              decoration: InputDecoration(labelText: statementType == 'customer' ? 'اختر العميل' : 'اختر المورد'),
              items: (statementType == 'customer' ? customers : suppliers).map((p) => DropdownMenuItem<String>(
                value: p['id'].toString(), child: Text(p['name'].toString(), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: statementLoading ? null : (value) async {
                setState(() => statementPartyId = value);
                await loadStatement();
              },
            )),
            OutlinedButton.icon(
              onPressed: statementLoading ? null : loadStatement,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث الكشف'),
            ),
          ]),
          const SizedBox(height: 8),
          Text('الفترة: ${dateText(fromDate)} إلى ${dateText(toDate)}', style: Theme.of(context).textTheme.bodySmall),
          if (statementLoading) const LinearProgressIndicator(),
          if (statementError != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(statementError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          if ((statementType == 'customer' ? customers : suppliers).isEmpty && !statementLoading)
            const Padding(padding: EdgeInsets.all(8), child: Text('أضف عميلًا أو موردًا أولًا لعرض كشف الحساب.')),
          if (statementPartyId != null) ...[
            const SizedBox(height: 12),
            Text(statementPartyName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            GridView.count(
              crossAxisCount: width >= 1000 ? 4 : width >= 650 ? 2 : 1,
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8, crossAxisSpacing: 8,
              childAspectRatio: width < 650 ? 3.8 : 2.3,
              children: [
                summary('رصيد أول الفترة', statementOpening, Icons.account_balance_outlined, const Color(0xFF6B7280)),
                summary(statementType == 'customer' ? 'إجمالي الفواتير' : 'إجمالي المشتريات', statementDebit + (statementType == 'supplier' ? statementCredit : 0), Icons.receipt_long_outlined, const Color(0xFF2477C8)),
                summary(statementType == 'customer' ? 'إجمالي التحصيلات' : 'إجمالي السداد', statementType == 'customer' ? statementCredit : statementDebit, Icons.payments_outlined, const Color(0xFF176B55)),
                summary(statementType == 'customer' ? 'الرصيد المستحق لنا' : 'الرصيد المستحق للمورد', statementClosing, Icons.account_balance_wallet_outlined, statementClosing >= 0 ? const Color(0xFFB17B18) : Colors.red, note: statementClosing < 0 ? 'رصيد دائن/مدفوع مقدمًا' : 'الرصيد بعد حركات الفترة'),
              ],
            ),
            const SizedBox(height: 8),
            if (statementRows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد حركات في الفترة المحددة.')),
            ...statementRows.map((entry) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(number(entry['debit']) > 0 ? Icons.receipt_long_outlined : Icons.payments_outlined)),
              title: Text(entry['title'].toString()),
              subtitle: Text(dateText(entry['date'] as DateTime)),
              trailing: SizedBox(width: 170, child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(number(entry['debit']) > 0 ? 'مدين: ${money(number(entry['debit']))}' : 'دائن: ${money(number(entry['credit']))}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('الرصيد: ${money(number(entry['balance']))}', style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
            )),
            const Divider(),
            Text('إجمالي المدين: ${money(statementDebit)}    •    إجمالي الدائن: ${money(statementCredit)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 6),
          Text('الكشف يعتمد على الفواتير المرحلة وحركات التحصيل/السداد المسجلة على الحساب. أي سداد غير مربوط بالعميل أو المورد لن يظهر هنا.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      )),
      const SizedBox(height: 8),
      Text('تنبيه: مجمل الربح تقديري ويعتمد على تكلفة الصنف المحفوظة في بنود فاتورة البيع. تقرير الفترة يعرض حتى 1000 فاتورة بيع وشراء و1000 مصروف.', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
