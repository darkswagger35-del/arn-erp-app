import 'dart:async';

import 'package:flutter/material.dart';

/// Web-safe compatibility layer for the Windows-only webview package.
///
/// MOTUS keeps the full embedded Yandex planner on Windows. On Flutter Web the
/// screen falls back to the existing "Yandex'te Aç" flow, so the rest of the
/// technician/dispatch UI can compile and run in a browser without importing
/// `webview_windows`.
class WebviewController {
  final StreamController<String> _urlController =
      StreamController<String>.broadcast();
  final StreamController<dynamic> _messageController =
      StreamController<dynamic>.broadcast();

  Stream<String> get url => _urlController.stream;
  Stream<dynamic> get webMessage => _messageController.stream;

  Future<void> initialize() async {}

  Future<void> loadUrl(String url) async {
    if (!_urlController.isClosed) _urlController.add(url);
  }

  Future<void> loadStringContent(String content) async {}

  Future<dynamic> executeScript(String script) async => null;

  void dispose() {
    if (!_urlController.isClosed) _urlController.close();
    if (!_messageController.isClosed) _messageController.close();
  }
}

class Webview extends StatelessWidget {
  const Webview(this.controller, {super.key});

  final WebviewController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFF0B1721),
      padding: const EdgeInsets.all(24),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 46, color: Color(0xFF91A4B7)),
          SizedBox(height: 12),
          Text(
            'Gömülü Yandex haritası Windows masaüstü sürümünde kullanılır. '
            'Web sürümünde Yandex\'te Aç düğmesiyle rota açılır.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF91A4B7), height: 1.45),
          ),
        ],
      ),
    );
  }
}
