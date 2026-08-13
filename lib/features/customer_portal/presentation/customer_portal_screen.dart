import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/supabase_client_provider.dart';

class CustomerPortalScreen extends ConsumerWidget {
  const CustomerPortalScreen({super.key,required this.token});
  final String token;

  @override
  Widget build(BuildContext context,WidgetRef ref){
    return Scaffold(
      appBar:AppBar(title:const Text('Müşteri Servis Portalı')),
      body:FutureBuilder<dynamic>(
        future:ref.read(supabaseClientProvider).rpc('get_customer_portal',params:{'p_token':token}),
        builder:(context,snapshot){
          if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
          if(snapshot.hasError)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('Portal bilgileri açılamadı. Bağlantı süresi dolmuş veya geçersiz olabilir.\n\n${snapshot.error}',textAlign:TextAlign.center)));
          final data=Map<String,dynamic>.from(snapshot.data as Map? ?? const {});
          if(data.isEmpty)return const Center(child:Text('Müşteri bilgisi bulunamadı.'));
          final services=List<Map<String,dynamic>>.from(data['services'] as List? ?? const []);
          final payments=List<Map<String,dynamic>>.from(data['payments'] as List? ?? const []);
          return ListView(padding:const EdgeInsets.all(16),children:[
            Text(data['company_name']?.toString()??'MOTUS',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),
            const SizedBox(height:16),
            Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.person)),title:Text(data['customer_name']?.toString()??''),subtitle:Text('Bakiye: ${NumberFormat.currency(locale:'tr_TR',symbol:'₺').format((data['balance'] as num?)??0)}'))),
            const SizedBox(height:16),Text('Servis Geçmişi',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
            ...services.map((e)=>Card(child:ListTile(title:Text(e['service_type_label']?.toString()??'Servis'),subtitle:Text('${e['status_label']??''}\n${e['planned_date']??e['created_at']??''}'),trailing:Text(NumberFormat.currency(locale:'tr_TR',symbol:'₺').format((e['price'] as num?)??0))))),
            const SizedBox(height:16),Text('Tahsilatlar',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
            ...payments.map((e)=>Card(child:ListTile(title:Text(e['payment_method']?.toString()??'Ödeme'),subtitle:Text(e['payment_date']?.toString()??''),trailing:Text(NumberFormat.currency(locale:'tr_TR',symbol:'₺').format((e['amount'] as num?)??0))))),
          ]);
        },
      ),
    );
  }
}
