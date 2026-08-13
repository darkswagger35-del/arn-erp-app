import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key,required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context){
    return StreamBuilder<List<ConnectivityResult>>(
      stream:Connectivity().onConnectivityChanged,
      builder:(context,snapshot){
        final offline=(snapshot.data??const <ConnectivityResult>[]).contains(ConnectivityResult.none);
        return Column(children:[
          if(offline)Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:6,horizontal:12),color:Theme.of(context).colorScheme.errorContainer,child:const Text('İnternet bağlantısı yok. Görüntülenen bilgiler eski olabilir; yeni işlemler bağlantı gelince tekrar denenmelidir.',textAlign:TextAlign.center)),
          Expanded(child:child),
        ]);
      },
    );
  }
}
