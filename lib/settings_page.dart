import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final db = Supabase.instance.client;
  final businessName = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final warehouseName = TextEditingController();
  final warehouseCode = TextEditingController();
  final warehouseAddress = TextEditingController();
  final inviteEmail = TextEditingController();
  List<Map<String, dynamic>> warehouses = [];
  String currencyCode = 'EGP';
  String currencySymbol = 'ج.م';
  String? defaultWarehouseId;
  bool loading = true, savingBusiness = false, savingWarehouse = false, sendingInvite = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    businessName.dispose();
    phone.dispose();
    address.dispose();
    warehouseName.dispose();
    warehouseCode.dispose();
    warehouseAddress.dispose();
    inviteEmail.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        db.from('business_settings').select('business_name,phone,address,currency_code,currency_symbol,default_warehouse_id').maybeSingle(),
        db.from('warehouses').select('id,name,code,address,is_default,is_active').order('created_at'),
      ]);
      if (!mounted) return;
      final settings = results[0] as Map<String, dynamic>?;
      final rows = List<Map<String, dynamic>>.from(results[1] as List);
      setState(() {
        if (settings != null) {
          businessName.text = settings['business_name']?.toString() ?? 'محلي';
          phone.text = settings['phone']?.toString() ?? '';
          address.text = settings['address']?.toString() ?? '';
          currencyCode = settings['currency_code']?.toString() ?? 'EGP';
          currencySymbol = settings['currency_symbol']?.toString() ?? 'ج.م';
          defaultWarehouseId = settings['default_warehouse_id']?.toString();
        } else {
          businessName.text = 'محلي';
        }
        warehouses = rows;
        defaultWarehouseId ??= rows.where((w) => w['is_default'] == true).map((w) => w['id'].toString()).firstOrNull;
      });
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل الإعدادات: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> saveBusiness() async {
    if (businessName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسم النشاط أولاً')));
      return;
    }
    setState(() => savingBusiness = true);
    try {
      await db.from('business_settings').upsert({
        'business_name': businessName.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'currency_code': currencyCode,
        'currency_symbol': currencySymbol,
        'default_warehouse_id': defaultWarehouseId,
      }, onConflict: 'owner_id');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ بيانات النشاط')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الإعدادات: $e')));
    } finally {
      if (mounted) setState(() => savingBusiness = false);
    }
  }

  Future<void> addWarehouse() async {
    if (warehouseName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسم المخزن')));
      return;
    }
    setState(() => savingWarehouse = true);
    try {
      final result = await db.from('warehouses').insert({
        'name': warehouseName.text.trim(),
        'code': warehouseCode.text.trim().isEmpty ? null : warehouseCode.text.trim(),
        'address': warehouseAddress.text.trim().isEmpty ? null : warehouseAddress.text.trim(),
        'is_default': warehouses.isEmpty,
        'is_active': true,
      }).select('id').single();
      final id = result['id'].toString();
      if (warehouses.isEmpty) {
        defaultWarehouseId = id;
        await db.from('business_settings').upsert({
          'business_name': businessName.text.trim().isEmpty ? 'محلي' : businessName.text.trim(),
          'currency_code': currencyCode,
          'currency_symbol': currencySymbol,
          'default_warehouse_id': id,
        }, onConflict: 'owner_id');
      }
      warehouseName.clear();
      warehouseCode.clear();
      warehouseAddress.clear();
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المخزن')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إضافة المخزن: $e')));
    } finally {
      if (mounted) setState(() => savingWarehouse = false);
    }
  }

  Future<void> sendInvite() async {
    final email = inviteEmail.text.trim().toLowerCase();
    if (!RegExp(r'^[^\\s@]+@[^\\s@]+\\.[^\\s@]+
    try {
      await db.from('warehouses').update({'is_default': false}).neq('id', id);
      await db.from('warehouses').update({'is_default': true}).eq('id', id);
      await db.from('business_settings').upsert({
        'business_name': businessName.text.trim().isEmpty ? 'محلي' : businessName.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'currency_code': currencyCode,
        'currency_symbol': currencySymbol,
        'default_warehouse_id': id,
      }, onConflict: 'owner_id');
      if (mounted) setState(() => defaultWarehouseId = id);
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تغيير المخزن الافتراضي: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إدارة المستخدمين', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text(
                'ادعُ شريكًا جديدًا بالبريد الإلكتروني. كل المستخدمين المدعوين '
                'لديهم نفس صلاحياتك على بيانات النشاط، ويمكنهم دعوة مستخدمين آخرين.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: inviteEmail,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني للمستخدم الجديد',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: sendingInvite ? null : sendInvite,
                icon: sendingInvite
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_outlined),
                label: Text(sendingInvite ? 'جارٍ إرسال الدعوة...' : 'إرسال دعوة'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('بيانات النشاط', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: businessName, decoration: const InputDecoration(labelText: 'اسم المحل أو النشاط *')),
            const SizedBox(height: 10),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
            const SizedBox(height: 10),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: currencyCode,
              decoration: const InputDecoration(labelText: 'العملة'),
              items: const [
                DropdownMenuItem(value: 'EGP', child: Text('الجنيه المصري (EGP)')),
                DropdownMenuItem(value: 'SAR', child: Text('الريال السعودي (SAR)')),
                DropdownMenuItem(value: 'AED', child: Text('الدرهم الإماراتي (AED)')),
                DropdownMenuItem(value: 'USD', child: Text('الدولار الأمريكي (USD)')),
              ],
              onChanged: (v) => setState(() {
                currencyCode = v ?? 'EGP';
                currencySymbol = {'EGP':'ج.م','SAR':'ر.س','AED':'د.إ','USD':r'$'}[currencyCode]!;
              }),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: savingBusiness ? null : saveBusiness,
              icon: const Icon(Icons.save_outlined),
              label: Text(savingBusiness ? 'جارٍ الحفظ...' : 'حفظ بيانات النشاط'),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('المخازن', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('أنشئ مخزنًا واحدًا على الأقل قبل تسجيل فواتير المشتريات.'),
            const SizedBox(height: 12),
            TextField(controller: warehouseName, decoration: const InputDecoration(labelText: 'اسم المخزن *')),
            const SizedBox(height: 10),
            TextField(controller: warehouseCode, decoration: const InputDecoration(labelText: 'كود المخزن (اختياري)')),
            const SizedBox(height: 10),
            TextField(controller: warehouseAddress, decoration: const InputDecoration(labelText: 'عنوان المخزن (اختياري)')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: savingWarehouse ? null : addWarehouse,
              icon: const Icon(Icons.add_business_outlined),
              label: Text(savingWarehouse ? 'جارٍ الإضافة...' : 'إضافة مخزن'),
            ),
            const Divider(height: 28),
            if (warehouses.isEmpty && !loading)
              const Text('لم يتم إنشاء مخازن بعد.')
            else
              ...warehouses.map((w) {
                final id = w['id'].toString();
                final isDefault = id == defaultWarehouseId || w['is_default'] == true;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(isDefault ? Icons.warehouse : Icons.store_outlined),
                  title: Text(w['name']?.toString() ?? ''),
                  subtitle: Text('${w['code'] ?? 'بدون كود'} • ${w['is_active'] == true ? 'نشط' : 'غير نشط'}'),
                  trailing: isDefault
                      ? const Chip(label: Text('افتراضي'))
                      : TextButton(onPressed: () => setDefaultWarehouse(id), child: const Text('جعله افتراضيًا')),
                );
              }),
          ]),
        ),
      ),
    ],
  );
}
).hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب بريدًا إلكترونيًا صحيحًا')),
      );
      return;
    }
    setState(() => sendingInvite = true);
    try {
      await db.functions.invoke('send-invite', body: {'email': email});
      inviteEmail.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال دعوة إلى $email')),
        );
      }
    } on FunctionException catch (e) {
      final message = e.details is Map
          ? (e.details as Map)['error']?.toString()
          : null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message ?? 'تعذر إرسال الدعوة: ${e.reasonPhrase ?? e.toString()}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الدعوة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => sendingInvite = false);
    }
  }

  Future<void> setDefaultWarehouse(String id) async {
    try {
      await db.from('warehouses').update({'is_default': false}).neq('id', id);
      await db.from('warehouses').update({'is_default': true}).eq('id', id);
      await db.from('business_settings').upsert({
        'business_name': businessName.text.trim().isEmpty ? 'محلي' : businessName.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'currency_code': currencyCode,
        'currency_symbol': currencySymbol,
        'default_warehouse_id': id,
      }, onConflict: 'owner_id');
      if (mounted) setState(() => defaultWarehouseId = id);
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تغيير المخزن الافتراضي: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('بيانات النشاط', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: businessName, decoration: const InputDecoration(labelText: 'اسم المحل أو النشاط *')),
            const SizedBox(height: 10),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
            const SizedBox(height: 10),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: currencyCode,
              decoration: const InputDecoration(labelText: 'العملة'),
              items: const [
                DropdownMenuItem(value: 'EGP', child: Text('الجنيه المصري (EGP)')),
                DropdownMenuItem(value: 'SAR', child: Text('الريال السعودي (SAR)')),
                DropdownMenuItem(value: 'AED', child: Text('الدرهم الإماراتي (AED)')),
                DropdownMenuItem(value: 'USD', child: Text('الدولار الأمريكي (USD)')),
              ],
              onChanged: (v) => setState(() {
                currencyCode = v ?? 'EGP';
                currencySymbol = {'EGP':'ج.م','SAR':'ر.س','AED':'د.إ','USD':r'$'}[currencyCode]!;
              }),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: savingBusiness ? null : saveBusiness,
              icon: const Icon(Icons.save_outlined),
              label: Text(savingBusiness ? 'جارٍ الحفظ...' : 'حفظ بيانات النشاط'),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('المخازن', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('أنشئ مخزنًا واحدًا على الأقل قبل تسجيل فواتير المشتريات.'),
            const SizedBox(height: 12),
            TextField(controller: warehouseName, decoration: const InputDecoration(labelText: 'اسم المخزن *')),
            const SizedBox(height: 10),
            TextField(controller: warehouseCode, decoration: const InputDecoration(labelText: 'كود المخزن (اختياري)')),
            const SizedBox(height: 10),
            TextField(controller: warehouseAddress, decoration: const InputDecoration(labelText: 'عنوان المخزن (اختياري)')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: savingWarehouse ? null : addWarehouse,
              icon: const Icon(Icons.add_business_outlined),
              label: Text(savingWarehouse ? 'جارٍ الإضافة...' : 'إضافة مخزن'),
            ),
            const Divider(height: 28),
            if (warehouses.isEmpty && !loading)
              const Text('لم يتم إنشاء مخازن بعد.')
            else
              ...warehouses.map((w) {
                final id = w['id'].toString();
                final isDefault = id == defaultWarehouseId || w['is_default'] == true;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(isDefault ? Icons.warehouse : Icons.store_outlined),
                  title: Text(w['name']?.toString() ?? ''),
                  subtitle: Text('${w['code'] ?? 'بدون كود'} • ${w['is_active'] == true ? 'نشط' : 'غير نشط'}'),
                  trailing: isDefault
                      ? const Chip(label: Text('افتراضي'))
                      : TextButton(onPressed: () => setDefaultWarehouse(id), child: const Text('جعله افتراضيًا')),
                );
              }),
          ]),
        ),
      ),
    ],
  );
}
