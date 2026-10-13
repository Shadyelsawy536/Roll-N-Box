import 'package:flutter/material.dart';
import 'money_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReturnsPage extends StatefulWidget {
  const ReturnsPage({super.key});
  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  final db = Supabase.instance.client;
  final qty = <String, double>{};
  final amount = TextEditingController(text: '0');
  final notes = TextEditingController();
  bool sales = true, loading = true, busy = false;
  String? invoiceId, cashboxId, error;
  String method = 'cash';
  List<Map<String,dynamic>> salesInvoices = [], purchaseInvoices = [], cashboxes = [], items = [], salesReturns = [], purchaseReturns = [];

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { amount.dispose(); notes.dispose(); super.dispose(); }
  String money(num value) => '${formatMoney(value)} ج.م';
  double get total => items.fold(0, (s, i) {
    final q = qty[i['id'].toString()] ?? 0;
    return s + q * ((i['line_total'] as num).toDouble() / (i['quantity'] as num).toDouble());
  });

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final r = await Future.wait([
        db.from('sales_invoices').select('id,invoice_number,total,customers(name)').eq('status','posted').order('invoice_date',ascending:false).limit(100),
        db.from('purchase_invoices').select('id,invoice_number,total,suppliers(name)').eq('status','posted').order('invoice_date',ascending:false).limit(100),
        db.from('cashboxes').select('id,name,is_default').eq('is_active',true).order('is_default',ascending:false),
        db.from('sales_returns').select('id,return_number,total,refund_amount,sales_invoices(invoice_number,customers(name))').order('return_date',ascending:false).limit(20),
        db.from('purchase_returns').select('id,return_number,total,received_amount,purchase_invoices(invoice_number,suppliers(name))').order('return_date',ascending:false).limit(20),
      ]);
      if (!mounted) return;
      setState(() {
        salesInvoices = List<Map<String,dynamic>>.from(r[0]);
        purchaseInvoices = List<Map<String,dynamic>>.from(r[1]);
        cashboxes = List<Map<String,dynamic>>.from(r[2]);
        salesReturns = List<Map<String,dynamic>>.from(r[3]);
        purchaseReturns = List<Map<String,dynamic>>.from(r[4]);
        cashboxId ??= cashboxes.isEmpty ? null : cashboxes.first['id'].toString();
      });
    } catch(e) { if(mounted) setState(()=>error='تعذر تحميل البيانات: $e'); }
    finally { if(mounted) setState(()=>loading=false); }
  }

  Future<void> chooseInvoice(String? id) async {
    setState(() { invoiceId=id; items=[]; qty.clear(); amount.text='0'; error=null; });
    if(id==null) return;
    try {
      final raw = sales
        ? await db.from('sales_invoice_items').select('id,product_id,quantity,unit_price,unit_cost,line_total,products(name)').eq('invoice_id',id)
        : await db.from('purchase_invoice_items').select('id,product_id,quantity,unit_cost,line_total,products(name)').eq('invoice_id',id);
      final returned = sales
        ? await db.from('sales_return_items').select('sales_invoice_item_id,quantity,sales_returns!inner(sales_invoice_id)').eq('sales_returns.sales_invoice_id',id)
        : await db.from('purchase_return_items').select('purchase_invoice_item_id,quantity,purchase_returns!inner(purchase_invoice_id)').eq('purchase_returns.purchase_invoice_id',id);
      final done = <String,double>{};
      for(final x in List<Map<String,dynamic>>.from(returned)) {
        final k=(sales?x['sales_invoice_item_id']:x['purchase_invoice_item_id']).toString();
        done[k]=(done[k]??0)+(x['quantity'] as num).toDouble();
      }
      if(!mounted)return;
      setState(()=>items=List<Map<String,dynamic>>.from(raw).map((x){
        final original=(x['quantity'] as num).toDouble(), returnedQty=done[x['id'].toString()]??0;
        return {...x,'remaining':(original-returnedQty).clamp(0,original),'returned':returnedQty};
      }).toList());
    } catch(e) { if(mounted)setState(()=>error='تعذر تحميل أصناف الفاتورة: $e'); }
  }

  Future<void> save() async {
    final chosen=items.where((x)=>(qty[x['id'].toString()]??0)>0).toList();
    final cash=double.tryParse(amount.text.trim());
    if(invoiceId==null || chosen.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اختار الفاتورة وأدخل كمية مرتجعة على الأقل'))); return; }
    if(chosen.any((x)=>(qty[x['id'].toString()]??0)>(x['remaining'] as num).toDouble())) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('فيه كمية أكبر من المتاح للمرتجع'))); return; }
    if(cash==null||cash<0||cash>total) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('مبلغ التسوية النقدية غير صحيح'))); return; }
    if(cash>0&&cashboxId==null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اختار خزينة أولًا'))); return; }
    setState(()=>busy=true);
    try {
      final params={
        (sales?'p_sales_invoice_id':'p_purchase_invoice_id'):invoiceId,
        'p_return_date':DateTime.now().toUtc().toIso8601String(),
        'p_items':chosen.map((x)=>{(sales?'sales_invoice_item_id':'purchase_invoice_item_id'):x['id'],'quantity':qty[x['id'].toString()]}).toList(),
        (sales?'p_refund_amount':'p_received_amount'):cash,
        'p_cashbox_id':cash>0?cashboxId:null,'p_payment_method':method,
        'p_notes':notes.text.trim().isEmpty?null:notes.text.trim(),
      };
      final res=await db.rpc(sales?'post_sales_return':'post_purchase_return',params:params);
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تم ترحيل المرتجع رقم ${res['return_number']} بإجمالي ${money(res['total'] as num)}')));
      setState((){invoiceId=null;items=[];qty.clear();amount.text='0';notes.clear();});
      await load();
    } catch(e) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشل ترحيل المرتجع: $e'))); }
    finally { if(mounted)setState(()=>busy=false); }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    if(loading) const LinearProgressIndicator(),
    if(error!=null) Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('تسجيل مرتجع',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:12),
      SegmentedButton<bool>(segments:const [ButtonSegment(value:true,label:Text('مرتجع مبيعات')),ButtonSegment(value:false,label:Text('مرتجع مشتريات'))],selected:{sales},onSelectionChanged:(v){setState((){sales=v.first;invoiceId=null;items=[];qty.clear();amount.text='0';});}),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(key:ValueKey('inv-$sales-$invoiceId'),value:invoiceId,isExpanded:true,decoration:InputDecoration(labelText:sales?'فاتورة المبيعات الأصلية':'فاتورة المشتريات الأصلية'),items:(sales?salesInvoices:purchaseInvoices).map((x)=>DropdownMenuItem(value:x['id'].toString(),child:Text('#${x['invoice_number']} • ${((sales?x['customers']:x['suppliers']) as Map?)?['name']??'بدون اسم'} • ${money(x['total'] as num)}',overflow:TextOverflow.ellipsis))).toList(),onChanged:busy?null:chooseInvoice),
      if(items.isNotEmpty) ...[
        const SizedBox(height:12),
        ...items.map((x){final id=x['id'].toString();final original=(x['quantity'] as num).toDouble();final remaining=(x['remaining'] as num).toDouble();final name=(x['products'] as Map?)?['name']??'صنف';return ListTile(key:ValueKey(id),title:Text(name.toString()),subtitle:Text('المتبقي: $remaining من أصل $original • سبق إرجاعه: ${x['returned']}'),trailing:SizedBox(width:95,child:TextFormField(key:ValueKey('q-$id-$invoiceId'),initialValue:'0',enabled:remaining>0,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الكمية'),onChanged:(v)=>setState(()=>qty[id]=double.tryParse(v)??0))));}),
        const Divider(),
        Text('إجمالي المرتجع: ${money(total)}',style:Theme.of(context).textTheme.titleLarge),
        TextField(controller:amount,onChanged:(_)=>setState((){}),keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:sales?'المبلغ النقدي المرتد للعميل':'المبلغ النقدي المسترد من المورد',helperText:'اكتب صفرًا للتسوية على الحساب')),
        if((double.tryParse(amount.text)??0)>0) ...[
          const SizedBox(height:8),
          DropdownButtonFormField<String>(value:cashboxId,isExpanded:true,decoration:const InputDecoration(labelText:'الخزينة'),items:cashboxes.map((x)=>DropdownMenuItem(value:x['id'].toString(),child:Text(x['name'].toString()))).toList(),onChanged:(v)=>setState(()=>cashboxId=v)),
          DropdownButtonFormField<String>(value:method,decoration:const InputDecoration(labelText:'طريقة الدفع'),items:const [DropdownMenuItem(value:'cash',child:Text('كاش')),DropdownMenuItem(value:'card',child:Text('فيزا')),DropdownMenuItem(value:'instapay',child:Text('إنستا باي')),DropdownMenuItem(value:'wallet',child:Text('محفظة'))],onChanged:(v)=>setState(()=>method=v??'cash')),
        ],
        TextField(controller:notes,decoration:const InputDecoration(labelText:'ملاحظات')),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:busy?null:save,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.check_circle_outline),label:Text(busy?'جارٍ الترحيل...':'حفظ وترحيل المرتجع')),
        const Text('يتم تسجيل حركة المخزون وحركة الخزينة داخل معاملة واحدة. الفاتورة الأصلية لا تتغير.',style:TextStyle(fontSize:12)),
      ],
    ]))),
    const SizedBox(height:16),
    Text('آخر مرتجعات المبيعات',style:Theme.of(context).textTheme.titleLarge),
    ...salesReturns.map((x)=>Card(child:ListTile(title:Text('مرتجع #${x['return_number']} • فاتورة #${(x['sales_invoices'] as Map?)?['invoice_number']??'—'}'),subtitle:Text('استرداد نقدي: ${money((x['refund_amount'] as num?)??0)}'),trailing:Text(money(x['total'] as num))))),
    const SizedBox(height:12),
    Text('آخر مرتجعات المشتريات',style:Theme.of(context).textTheme.titleLarge),
    ...purchaseReturns.map((x)=>Card(child:ListTile(title:Text('مرتجع #${x['return_number']} • فاتورة #${(x['purchase_invoices'] as Map?)?['invoice_number']??'—'}'),subtitle:Text('مبلغ مسترد: ${money((x['received_amount'] as num?)??0)}'),trailing:Text(money(x['total'] as num))))),
  ]);
}
