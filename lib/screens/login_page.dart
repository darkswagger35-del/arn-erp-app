import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ARN ERP brand palette — aligned with the app theme in main.dart.
abstract final class _ArnBrand {
  static const primary = Color(0xFF176B87);
  static const primaryDark = Color(0xFF153448);
  static const surface = Color(0xFFF4F7F9);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.onLoginSuccess});

  /// Called after basic validation passes. Wire navigation in the parent.
  final VoidCallback? onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    _phoneFocus.unfocus();
    _passwordFocus.unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Placeholder for future auth — keeps UX responsive.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (widget.onLoginSuccess != null) {
      widget.onLoginSuccess!();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Giriş başarılı'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: _ArnBrand.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 32,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 40, 32, 36),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BrandHeader(colorScheme: colorScheme),
                        const SizedBox(height: 36),
                        TextFormField(
                          controller: _phoneController,
                          focusNode: _phoneFocus,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Telefon numarası',
                            hintText: '05XX XXX XX XX',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (value) {
                            final phone = value?.trim() ?? '';
                            if (phone.isEmpty) {
                              return 'Telefon numarası gerekli';
                            }
                            if (phone.length < 10) {
                              return 'Geçerli bir telefon numarası girin';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) {
                            FocusScope.of(context).requestFocus(_passwordFocus);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Şifre',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Şifreyi göster'
                                  : 'Şifreyi gizle',
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').isEmpty) {
                              return 'Şifre gerekli';
                            }
                            if (value!.length < 4) {
                              return 'Şifre en az 4 karakter olmalı';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _handleLogin(),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: FilledButton.styleFrom(
                              backgroundColor: _ArnBrand.primary,
                              disabledBackgroundColor: _ArnBrand.primary
                                  .withValues(alpha: 0.5),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'GİRİŞ YAP',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'İlk deneme sürümü',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _ArnBrand.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _ArnBrand.primary.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.water_drop_rounded,
            color: Colors.white,
            size: 42,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'MOTUS',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: _ArnBrand.primaryDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Su Arıtma Servis Yönetim Sistemi',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: colorScheme.onSurface.withValues(alpha: 0.55),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
