import 'package:flutter/material.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _client = Supabase.instance.client;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  bool _hasNextPage = false;
  int _page = 0;
  static const int _pageSize = 50;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() {
      if (!mounted) return;
      setState(() => _page = 0);
      _load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final term = _search.text.trim().replaceAll(',', ' ').replaceAll('(', '').replaceAll(')', '');
      var query = _client
          .from('products')
          .select('id,name,internal_code,description,cost_price,sale_price,minimum_stock,track_stock,is_active,created_at');
      if (term.isNotEmpty) {
        query = query.or('name.ilike.%$term%,internal_code.ilike.%$term%');
      }
      final result = await query
          .order('created_at', ascending: false)
          .range(_page * _pageSize, _page * _pageSize + _pageSize);
      if (!mounted) return;
      final pageRows = List<Map<String, dynamic>>.from(result);
      final hasNext = pageRows.length > _pageSize;
      if (hasNext) pageRows.removeLast();
      setState(() {
        _products = pageRows;
        _hasNextPage = hasNext;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تحميل الأصناف. تأكد من اتصال الإنترنت وصلاحيات قاعدة البيانات.\n$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered => _products;

  Future<void> _edit([Map<String, dynamic>? product]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductDialog(product: product),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الصنف'),
        content: Text('هل تريد حذف «${product['name']}»؟ إذا كان مرتبطًا بفواتير أو حركات مخزون، ستمنع قاعدة البيانات الحذف حفاظًا على السجلات.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _client.from('products').delete().eq('id', product['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الصنف')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لم يمكن حذف الصنف. قد يكون مرتبطًا بفواتير أو حركات مخزون.\n$e')),
      );
    }
  }

  String _money(dynamic value) {
    final n = double.tryParse(value?.toString() ?? '') ?? 0;
    return '${formatMoney(n)} ج.م';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'ابحث بالاسم أو كود الصنف',
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة صنف'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _SummaryCard(title: 'أصناف الصفحة', value: '${_products.length}', icon: Icons.inventory_2_outlined)),
          const SizedBox(width: 10),
          Expanded(child: _SummaryCard(title: 'الأصناف النشطة', value: '${_products.where((p) => p['is_active'] == true).length}', icon: Icons.check_circle_outline)),
        ]),
        const SizedBox(height: 12),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: Center(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 42),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ]),
          )))
        else if (rows.isEmpty)
          const Expanded(child: Center(child: Text('لا توجد أصناف بعد. اضغط «إضافة صنف» للبدء.')))
        else
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final p = rows[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(Icons.inventory_2_outlined, color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            if ((p['internal_code']?.toString() ?? '').isNotEmpty)
                              Text('الكود: ${p['internal_code']}', style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 5),
                            Wrap(spacing: 14, runSpacing: 4, children: [
                              Text('بيع: ${_money(p['sale_price'])}'),
                              Text('تكلفة: ${_money(p['cost_price'])}'),
                              Text('حد التنبيه: ${p['minimum_stock']}'),
                            ]),
                            if (p['is_active'] != true)
                              const Text('غير نشط', style: TextStyle(color: Colors.deepOrange)),
                          ],
                        )),
                        PopupMenuButton<String>(
                          tooltip: 'إجراءات الصنف',
                          onSelected: (v) {
                            if (v == 'edit') _edit(p);
                            if (v == 'delete') _delete(p);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('تعديل')),
                            PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _page == 0 || _loading ? null : () { setState(() => _page--); _load(); },
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('السابق'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('صفحة ${_page + 1}'),
                ),
                OutlinedButton.icon(
                  onPressed: !_hasNextPage || _loading ? null : () { setState(() => _page++); _load(); },
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ])),
      ]),
    ),
  );
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({this.product});
  final Map<String, dynamic>? product;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _description;
  late final TextEditingController _cost;
  late final TextEditingController _sale;
  late final TextEditingController _minimum;
  bool _trackStock = true;
  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?['name']?.toString() ?? '');
    _code = TextEditingController(text: p?['internal_code']?.toString() ?? '');
    _description = TextEditingController(text: p?['description']?.toString() ?? '');
    _cost = TextEditingController(text: p?['cost_price']?.toString() ?? '0');
    _sale = TextEditingController(text: p?['sale_price']?.toString() ?? '0');
    _minimum = TextEditingController(text: p?['minimum_stock']?.toString() ?? '0');
    _trackStock = p?['track_stock'] as bool? ?? true;
    _active = p?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose(); _code.dispose(); _description.dispose();
    _cost.dispose(); _sale.dispose(); _minimum.dispose();
    super.dispose();
  }

  String? _required(String? v) => (v?.trim().isNotEmpty ?? false) ? null : 'الحقل مطلوب';
  String? _nonNegative(String? v) {
    final n = double.tryParse((v ?? '').trim());
    return n != null && n >= 0 ? null : 'اكتب رقمًا صحيحًا أكبر من أو يساوي صفر';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'internal_code': _code.text.trim().isEmpty ? null : _code.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'cost_price': double.parse(_cost.text.trim()),
      'sale_price': double.parse(_sale.text.trim()),
      'minimum_stock': double.parse(_minimum.text.trim()),
      'track_stock': _trackStock,
      'is_active': _active,
    };
    try {
      final client = Supabase.instance.client;
      if (widget.product == null) {
        await client.from('products').insert(data);
      } else {
        await client.from('products').update(data).eq('id', widget.product!['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر حفظ الصنف. تحقق من الاتصال والصلاحيات.\n$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: Text(widget.product == null ? 'إضافة صنف جديد' : 'تعديل الصنف'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الصنف *'), validator: _required, autofocus: true),
              const SizedBox(height: 10),
              TextFormField(controller: _code, decoration: const InputDecoration(labelText: 'كود داخلي (اختياري)')),
              const SizedBox(height: 10),
              TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'الوصف (اختياري)'), maxLines: 2),
              const SizedBox(height: 10),
              TextFormField(controller: _cost, decoration: const InputDecoration(labelText: 'سعر التكلفة بالجنيه *'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _nonNegative),
              const SizedBox(height: 10),
              TextFormField(controller: _sale, decoration: const InputDecoration(labelText: 'سعر البيع بالجنيه *'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _nonNegative),
              const SizedBox(height: 10),
              TextFormField(controller: _minimum, decoration: const InputDecoration(labelText: 'حد التنبيه للمخزون'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _nonNegative),
              SwitchListTile(title: const Text('تتبع المخزون'), value: _trackStock, onChanged: (v) => setState(() => _trackStock = v), contentPadding: EdgeInsets.zero),
              SwitchListTile(title: const Text('الصنف نشط'), value: _active, onChanged: (v) => setState(() => _active = v), contentPadding: EdgeInsets.zero),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ')),
      ],
    ),
  );
}
