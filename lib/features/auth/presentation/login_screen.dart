import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _rememberMe = true;

  static const _rememberKey = 'auth_remember_me';
  static const _identifierKey = 'auth_saved_identifier';

  @override
  void initState() {
    super.initState();
    _loadRememberedLogin();
  }

  Future<void> _loadRememberedLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rememberMe = prefs.getBool(_rememberKey) ?? true;
      if (_rememberMe) {
        _emailController.text = prefs.getString(_identifierKey) ?? '';
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final identifier = _emailController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, _rememberMe);
    if (_rememberMe) {
      await prefs.setString(_identifierKey, identifier);
    } else {
      await prefs.remove(_identifierKey);
    }

    await ref.read(authControllerProvider.notifier).signIn(
      identifier: identifier,
      password: _passwordController.text,
    );

    if (!mounted) {
      return;
    }

    final authState = ref.read(authControllerProvider);
    if (authState.isAuthenticated) {
      switch (authState.role) {
        case AppRole.admin:
        case AppRole.manager:
          context.go('/admin-dashboard');
          break;
        case AppRole.secretary:
          context.go('/secretary-dashboard');
          break;
        case AppRole.technician:
          context.go('/technician-dashboard');
          break;
        default:
          break;
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFF061421),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/branding/motus_login_bg.png', fit: BoxFit.cover),
          Container(color: const Color(0xA8061421)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Row(
                    children: [
                      if (wide)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 72),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Image.asset('assets/branding/motus_logo_dark.png', width: 440),
                                const SizedBox(height: 18),
                                const Text('Servis süreçlerinizi kolaylaştırın,\nişinizi büyütün.', style: TextStyle(color: Colors.white,fontSize:28,fontWeight:FontWeight.w800,height:1.25)),
                                const SizedBox(height: 28),
                                const Wrap(spacing:12,runSpacing:12,children:[
                                  _FeatureChip(Icons.people_alt_outlined,'Müşteri'),
                                  _FeatureChip(Icons.home_repair_service_outlined,'Servis'),
                                  _FeatureChip(Icons.inventory_2_outlined,'Stok'),
                                  _FeatureChip(Icons.bar_chart_outlined,'Raporlar'),
                                ]),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(
                        width: wide ? 430 : MediaQuery.sizeOf(context).width.clamp(300, 430).toDouble(),
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FCFD),borderRadius:BorderRadius.circular(28),
                            border:Border.all(color:const Color(0x3300B8C9)),
                            boxShadow:const [BoxShadow(color:Color(0x55000000),blurRadius:45,offset:Offset(0,18))],
                          ),
                          child: Form(
                            key:_formKey,
                            child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                              if (!wide) ...[
                                Image.asset('assets/branding/motus_logo_light.png', height:120),
                                const SizedBox(height:12),
                              ],
                              const Text('Hesabınıza giriş yapın',textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:Color(0xFF0B2438))),
                              const SizedBox(height:24),
                              TextFormField(
                                controller:_emailController,textInputAction:TextInputAction.next,
                                decoration:const InputDecoration(labelText:'E-posta veya kullanıcı adı',prefixIcon:Icon(Icons.person_outline)),
                                validator:(v)=>v==null||v.trim().isEmpty?'Kullanıcı adı veya e-posta girin.':null,
                              ),
                              const SizedBox(height:16),
                              TextFormField(
                                controller:_passwordController,obscureText:_obscurePassword,textInputAction:TextInputAction.done,onFieldSubmitted:(_)=>_submitLogin(),
                                decoration:InputDecoration(labelText:'Şifre',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(icon:Icon(_obscurePassword?Icons.visibility_outlined:Icons.visibility_off_outlined),onPressed:()=>setState(()=>_obscurePassword=!_obscurePassword))),
                                validator:(v)=>v==null||v.isEmpty?'Şifrenizi girin.':null,
                              ),
                              const SizedBox(height:8),
                              CheckboxListTile(value:_rememberMe,onChanged:authState.isLoading?null:(v)=>setState(()=>_rememberMe=v??true),contentPadding:EdgeInsets.zero,controlAffinity:ListTileControlAffinity.leading,dense:true,title:const Text('Beni hatırla')),
                              const SizedBox(height:8),
                              SizedBox(height:52,child:FilledButton(onPressed:authState.isLoading?null:_submitLogin,child:authState.isLoading?const SizedBox(height:22,width:22,child:CircularProgressIndicator(strokeWidth:2)):const Text('GİRİŞ YAP'))),
                              if(authState.errorMessage!=null)...[
                                const SizedBox(height:14),
                                Text(authState.errorMessage!,textAlign:TextAlign.center,style:const TextStyle(color:Colors.redAccent,fontWeight:FontWeight.w600)),
                              ],
                              const SizedBox(height:20),
                              const Text('MOTUS • Service Management Platform',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF6B7D89),fontSize:12)),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),
    decoration:BoxDecoration(color:const Color(0x1A00B8C9),borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0x6600B8C9))),
    child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,color:const Color(0xFF22D3EE),size:20),const SizedBox(width:8),Text(label,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700))]),
  );
}
