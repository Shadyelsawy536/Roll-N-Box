import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'money_format.dart';

class FinancialObligationsPage extends StatefulWidget {
  const FinancialObligationsPage({super.key});
  @override
  State<FinancialObligationsPage> createState() => _FinancialObligationsPageState();
}

class _FinancialObligationsPageState extends State<FinancialObligationsPage> with SingleTickerProviderStateMixin {
  final db = Supabase.instance.client;
  late final TabController tabs = TabController(length: 2, vsync: this);
  final chequeNumber = TextEditingController();
  final chequeAmount = TextEditingController();
  final chequeNotes = TextEditingController();
  final installmentCount = TextEditingController(text: '3');
  final installmentNotes = TextEditingController();
  List<Map<String,dynamic>> customers=[], suppliers=[], cashboxes=[], salesInvoices=[], purchaseInvoices=[], cheques=[], installments=[];
  String chequePartyType='customer', chequeDirection='received', paymentMethod='cash';
  String installmentPartyType='customer';
  String? chequePartyId, cashboxId, selectedInvoiceId;
  DateTime chequeDueDate=DateTime.now(), firstDueDate=DateTime.now().add(const Duration(days:30));
  bool loading=false, saving=false;
  String? error;
  final Map<String,String> paymentRequestKeys={};

  String money(num v)=>'${formatMoney(v)} ج.م';
  double number(dynamic v)=>v is num?v.toDouble():double.tryParse('$v')??0;
  String dateText(DateTime d)=>'${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  String uuid() {
    final r=Random.secure();
    final b=List<int>.generate(16,(_)=>r.nextInt(256));
    b[6]=(b[6]&15)|64; b[8]=(b[8]&63)|128;
    final h=b.map((x)=>x.toRadixString(16).padLeft(2,'0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }

  @override void initState(){super.initState();load();}
  @override void dispose(){tabs.dispose();chequeNumber.dispose();chequeAmount.dispose();chequeNotes.dispose();installmentCount.dispose();installmentNotes.dispose();super.dispose();}

  Future<void> load() async {
    setState(()=>loading=true); error=null;
    try {
      final r=await Future.wait([
        db.from('customers').select('id,name').eq('is_active',true).order('name').limit(2000),
        db.from('suppliers').select('id,name').eq('is_active',true).order('name').limit(2000),
        db.from('cashboxes').select('id,name,is_default').eq('is_active',true).order('name').limit(500),
        db.from('sales_invoices').select('id,invoice_number,total,paid_total,customer_id,customers(name)').eq('status','posted').order('invoice_date',ascending:false).limit(2000),
        db.from('purchase_invoices').select('id,invoice_number,total,paid_total,supplier_id,suppliers(name)').eq('status','posted').order('invoice_date',ascending:false).limit(2000),
        db.from('cheques').select('*').order('due_date').limit(500),
        db.from('installments').select('*').order('due_date').limit(1000),
      ]);
      if(!mounted)return;
      setState((){
        customers=List<Map<String,dynamic>>.from(r[0]); suppliers=List<Map<String,dynamic>>.from(r[1]); cashboxes=List<Map<String,dynamic>>.from(r[2]);
        salesInvoices=List<Map<String,dynamic>>.from(r[3]); purchaseInvoices=List<Map<String,dynamic>>.from(r[4]);
        cheques=List<Map<String,dynamic>>.from(r[5]); installments=List<Map<String,dynamic>>.from(r[6]);
        cashboxId ??= cashboxes.where((x)=>x['is_default']==true).map((x)=>x['id'].toString()).firstOrNull ?? (cashboxes.isEmpty?null:cashboxes.first['id'].toString());
        final invoices=installmentPartyType=='customer'?salesInvoices:purchaseInvoices;
        if(selectedInvoiceId==null || !invoices.any((x)=>x['id'].toString()==selectedInvoiceId)) selectedInvoiceId=invoices.where((x)=>number(x['total'])>number(x['paid_total'])).map((x)=>x['id'].toString()).firstOrNull;
        final parties=chequePartyType=='customer'?customers:suppliers;
        if(chequePartyType!='other' && (chequePartyId==null || !parties.any((x)=>x['id'].toString()==chequePartyId))) chequePartyId=parties.isEmpty?null:parties.first['id'].toString();
      });
    } catch(e){if(mounted)setState(()=>error='تعذر تحميل الشيكات والأقساط: $e');}
    finally{if(mounted)setState(()=>loading=false);}
  }

  Future<void> pickDate({required bool forCheque}) async {
    final current=forCheque?chequeDueDate:firstDueDate;
    final d=await showDatePicker(context:context,initialDate:current,firstDate:DateTime(2000),lastDate:DateTime.now().add(const Duration(days:3650)));
    if(d!=null&&mounted)setState(()=>forCheque?chequeDueDate=d:firstDueDate=d);
  }

  Future<void> addCheque() async {
    final amount=double.tryParse(chequeAmount.text.trim());
    if(chequeNumber.text.trim().isEmpty || amount==null || !amount.isFinite || amount<=0 || (chequePartyType!='other'&&chequePartyId==null)){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أدخل رقم الشيك ومبلغًا صحيحًا وحدد الطرف')));
      return;
    }
    setState(()=>saving=true);
    try {
      await db.from('cheques').insert({
        'cheque_number':chequeNumber.text.trim(),'party_type':chequePartyType,'party_id':chequePartyType=='other'?null:chequePartyId,
        'direction':chequeDirection,'amount':amount,'cheque_date':dateText(DateTime.now()),'due_date':dateText(chequeDueDate),
        'status':'pending','notes':chequeNotes.text.trim().isEmpty?null:chequeNotes.text.trim(),
      });
      if(!mounted)return;
      setState(() { chequeNumber.clear(); chequeAmount.clear(); chequeNotes.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم تسجيل الشيك')));
      await load();
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشل تسجيل الشيك: $e')));}
    finally{if(mounted)setState(()=>saving=false);}
  }

  Future<void> settleCheque(Map<String,dynamic> cheque) async {
    if(cashboxes.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أنشئ خزنة نشطة أولًا')));return;}
    String? box=cashboxId; String method='cash';
    final form=await showDialog<Map<String,String>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      title:Text('تسوية الشيك #${cheque['cheque_number']}'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(value:box,decoration:const InputDecoration(labelText:'الخزنة'),items:cashboxes.map((x)=>DropdownMenuItem(value:x['id'].toString(),child:Text(x['name'].toString()))).toList(),onChanged:(v)=>setD(()=>box=v)),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(value:method,decoration:const InputDecoration(labelText:'وسيلة التسوية'),items:const [DropdownMenuItem(value:'cash',child:Text('كاش')),DropdownMenuItem(value:'card',child:Text('فيزا')),DropdownMenuItem(value:'instapay',child:Text('إنستا باي')),DropdownMenuItem(value:'wallet',child:Text('محفظة'))],onChanged:(v)=>setD(()=>method=v??'cash')),
        const SizedBox(height:8),Text('سيتم تسجيل الحركة في الخزنة مرة واحدة وتغيير حالة الشيك إلى محصل/مسدد.'),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>box==null?null:Navigator.pop(ctx,{'box':box!,'method':method}),child:const Text('تأكيد التسوية'))],
    ))));
    if(form==null||!mounted)return;
    try {
      final result=await db.rpc('settle_cheque',params:{'p_cheque_id':cheque['id'],'p_cashbox_id':form['box'],'p_payment_method':form['method'],'p_settlement_date':DateTime.now().toUtc().toIso8601String()});
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(result['already_settled']==true?'الشيك تمت تسويته بالفعل':'تمت تسوية الشيك وتسجيل حركة الخزنة')));
      await load();
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشلت تسوية الشيك: $e')));}
  }

  Future<void> createSchedule() async {
    final count=int.tryParse(installmentCount.text.trim());
    final invoices=installmentPartyType=='customer'?salesInvoices:purchaseInvoices;
    final selected=invoices.where((x)=>x['id'].toString()==selectedInvoiceId).firstOrNull;
    if(selected==null||count==null||count<1||count>60){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اختر فاتورة وأدخل عدد أقساط من 1 إلى 60')));return;}
    setState(()=>saving=true);
    try{
      final result=await db.rpc('create_installment_schedule',params:{
        'p_party_type':installmentPartyType,'p_reference_id':selected['id'],'p_first_due_date':dateText(firstDueDate),'p_count':count,
        'p_notes':installmentNotes.text.trim().isEmpty?null:installmentNotes.text.trim(),
      });
      if(!mounted)return;
      setState(()=>installmentNotes.clear());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تم إنشاء ${result['count']} أقساط بإجمالي ${money(number(result['scheduled_amount']))}')));
      await load();
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشل إنشاء جدول الأقساط: $e')));}
    finally{if(mounted)setState(()=>saving=false);}
  }

  Future<void> payInstallment(Map<String,dynamic> installment) async {
    if(cashboxes.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أنشئ خزنة نشطة أولًا')));return;}
    final id=installment['id'].toString();
    final key=paymentRequestKeys.putIfAbsent(id,uuid);
    final amountController=TextEditingController(text:(number(installment['amount'])-number(installment['paid_amount'])).toStringAsFixed(2));
    String? box=cashboxId;String method='cash';
    final form=await showDialog<Map<String,String>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      title:const Text('تسجيل سداد قسط'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('المتبقي: ${money(number(installment['amount'])-number(installment['paid_amount']))}'),
        const SizedBox(height:10),
        TextField(controller:amountController,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المبلغ المسدد')),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(value:box,decoration:const InputDecoration(labelText:'الخزنة'),items:cashboxes.map((x)=>DropdownMenuItem(value:x['id'].toString(),child:Text(x['name'].toString()))).toList(),onChanged:(v)=>setD(()=>box=v)),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(value:method,decoration:const InputDecoration(labelText:'وسيلة الدفع'),items:const [DropdownMenuItem(value:'cash',child:Text('كاش')),DropdownMenuItem(value:'card',child:Text('فيزا')),DropdownMenuItem(value:'instapay',child:Text('إنستا باي')),DropdownMenuItem(value:'wallet',child:Text('محفظة'))],onChanged:(v)=>setD(()=>method=v??'cash')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>box==null?null:Navigator.pop(ctx,{'box':box!,'method':method,'amount':amountController.text.trim()}),child:const Text('تأكيد السداد'))],
    ))));
    if(form==null||!mounted){amountController.dispose();return;}
    final amount=double.tryParse(form['amount']??'');
    if(amount==null||!amount.isFinite||amount<=0){amountController.dispose();ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('المبلغ غير صحيح')));return;}
    setState(()=>saving=true);
    try{
      final result=await db.rpc('post_installment_payment',params:{
        'p_installment_id':id,'p_cashbox_id':form['box'],'p_amount':amount,'p_payment_method':form['method'],
        'p_transaction_date':DateTime.now().toUtc().toIso8601String(),'p_idempotency_key':key,
      });
      paymentRequestKeys.remove(id);
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(result['already_posted']==true?'تم تسجيل هذه الدفعة بالفعل':'تم تسجيل الدفعة وتحديث رصيد الفاتورة والخزنة')));
      await load();
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشل السداد. أعد المحاولة بنفس الطلب لتجنب التكرار: $e')));}
    finally{amountController.dispose();if(mounted)setState(()=>saving=false);}
  }

  Widget chequesTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('تسجيل شيك جديد',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:12),
      TextField(controller:chequeNumber,decoration:const InputDecoration(labelText:'رقم الشيك *')),
      const SizedBox(height:10),
      DropdownButtonFormField<String>(value:chequePartyType,decoration:const InputDecoration(labelText:'نوع الطرف'),items:const [DropdownMenuItem(value:'customer',child:Text('عميل')),DropdownMenuItem(value:'supplier',child:Text('مورد')),DropdownMenuItem(value:'other',child:Text('طرف آخر'))],onChanged:saving?null:(v)=>setState(() { chequePartyType=v??'customer'; chequePartyId=null; })),
      if(chequePartyType!='other')...[
        const SizedBox(height:10),
        DropdownButtonFormField<String>(value:chequePartyId,decoration:InputDecoration(labelText:chequePartyType=='customer'?'العميل':'المورد'),items:(chequePartyType=='customer'?customers:suppliers).map((x)=>DropdownMenuItem(value:x['id'].toString(),child:Text(x['name'].toString()))).toList(),onChanged:(v)=>setState(()=>chequePartyId=v)),
      ],
      const SizedBox(height:10),
      DropdownButtonFormField<String>(value:chequeDirection,decoration:const InputDecoration(labelText:'اتجاه الشيك'),items:const [DropdownMenuItem(value:'received',child:Text('شيك وارد / مستلم')),DropdownMenuItem(value:'issued',child:Text('شيك صادر / مدفوع'))],onChanged:(v)=>setState(()=>chequeDirection=v??'received')),
      const SizedBox(height:10),
      TextField(controller:chequeAmount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'قيمة الشيك *')),
      const SizedBox(height:10),
      OutlinedButton.icon(onPressed:()=>pickDate(forCheque:true),icon:const Icon(Icons.calendar_month),label:Text('تاريخ الاستحقاق: ${dateText(chequeDueDate)}')),
      const SizedBox(height:10),
      TextField(controller:chequeNotes,decoration:const InputDecoration(labelText:'ملاحظات')),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:saving?null:addCheque,icon:const Icon(Icons.save_outlined),label:Text(saving?'جارٍ الحفظ...':'حفظ الشيك')),
    ]))),
    const SizedBox(height:12),Text('سجل الشيكات',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
    if(cheques.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('لا توجد شيكات مسجلة.'))),
    ...cheques.map((c){
      final partyType=c['party_type'];final partyId=c['party_id']?.toString();
      final list=partyType=='customer'?customers:suppliers;
      final party=partyType=='other'?'طرف آخر':list.where((x)=>x['id'].toString()==partyId).map((x)=>x['name'].toString()).firstOrNull??'طرف';
      final status=c['status'].toString();
      return Card(child:ListTile(
        leading:CircleAvatar(child:Icon(c['direction']=='received'?Icons.call_received:Icons.call_made)),
        title:Text('شيك #${c['cheque_number']} • ${money(number(c['amount']))}'),
        subtitle:Text('${c['direction']=='received'?'وارد':'صادر'} • $party • استحقاق ${c['due_date']} • ${status=='pending'?'معلق':status=='deposited'?'تم إيداعه':status=='cleared'?'تمت التسوية':status}'),
        trailing:status=='pending'||status=='deposited'?PopupMenuButton<String>(onSelected:(v)async{
          if(v=='settle')await settleCheque(c);
          if(v=='deposit'){await db.from('cheques').update({'status':'deposited'}).eq('id',c['id']);await load();}
          if(v=='cancel'){await db.from('cheques').update({'status':'cancelled'}).eq('id',c['id']);await load();}
        },itemBuilder:(_)=>[if(status=='pending')const PopupMenuItem(value:'deposit',child:Text('تسجيل الإيداع')),const PopupMenuItem(value:'settle',child:Text('تسوية في الخزنة')),const PopupMenuItem(value:'cancel',child:Text('إلغاء الشيك'))]):const Icon(Icons.check_circle_outline),
      ));
    }),
  ]);

  Widget installmentsTab(){
    final invoices=installmentPartyType=='customer'?salesInvoices:purchaseInvoices;
    final available=invoices.where((x)=>number(x['total'])>number(x['paid_total'])).toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('إنشاء جدول أقساط لفاتورة آجلة',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        SegmentedButton<String>(segments:const [ButtonSegment(value:'customer',label:Text('مستحقات العملاء')),ButtonSegment(value:'supplier',label:Text('مستحقات الموردين'))],selected:{installmentPartyType},onSelectionChanged:saving?null:(s)=>setState(() { installmentPartyType=s.first; selectedInvoiceId=null; })),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(value:selectedInvoiceId, isExpanded:true,decoration:const InputDecoration(labelText:'الفاتورة ذات الرصيد المستحق'),items:available.map((x)=>DropdownMenuItem(value:x['id'].toString(),child:Text('#${x['invoice_number']} • ${(x['customers'] as Map?)?['name']??(x['suppliers'] as Map?)?['name']??'طرف'} • متبقي ${money(number(x['total'])-number(x['paid_total']))}',overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState(()=>selectedInvoiceId=v)),
        const SizedBox(height:10),
        TextField(controller:installmentCount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'عدد الأقساط (1–60)')),
        const SizedBox(height:10),
        OutlinedButton.icon(onPressed:()=>pickDate(forCheque:false),icon:const Icon(Icons.calendar_month),label:Text('أول استحقاق: ${dateText(firstDueDate)}')),
        const SizedBox(height:10),
        TextField(controller:installmentNotes,decoration:const InputDecoration(labelText:'ملاحظات جدول الأقساط')),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:saving?null:createSchedule,icon:const Icon(Icons.event_repeat),label:Text(saving?'جارٍ الإنشاء...':'إنشاء جدول الأقساط')),
      ]))),
      const SizedBox(height:12),Text('الأقساط المسجلة',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
      if(installments.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('لا توجد أقساط مسجلة.'))),
      ...installments.map((i){
        final outstanding=number(i['amount'])-number(i['paid_amount']);
        final status=i['status'].toString();
        return Card(child:ListTile(
          leading:CircleAvatar(child:Icon(status=='paid'?Icons.check_circle_outline:Icons.event_note)),
          title:Text('${i['party_type']=='customer'?'قسط عميل':'قسط مورد'} • ${money(number(i['amount']))}'),
          subtitle:Text('استحقاق ${i['due_date']} • مدفوع ${money(number(i['paid_amount']))} • متبقي ${money(outstanding)} • ${status=='paid'?'مسدد':status=='partial'?'سداد جزئي':status}'),
          trailing:outstanding>0?IconButton(tooltip:'تسجيل سداد',onPressed:saving?null:()=>payInstallment(i),icon:const Icon(Icons.payments_outlined)):const Icon(Icons.check_circle,color:Colors.green),
        ));
      }),
    ]);
  }

  @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    if(loading)const LinearProgressIndicator(),
    if(error!=null)Padding(padding:const EdgeInsets.only(bottom:10),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
    Card(child:TabBar(controller:tabs,tabs:const [Tab(icon:Icon(Icons.account_balance_outlined),text:'الشيكات'),Tab(icon:Icon(Icons.event_repeat),text:'الأقساط')])),
    const SizedBox(height:12),
    SizedBox(height:2600,child:TabBarView(controller:tabs,children:[chequesTab(),installmentsTab()])),
    Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(onPressed:loading?null:load,icon:const Icon(Icons.refresh),label:const Text('تحديث البيانات'))),
  ]);
}
