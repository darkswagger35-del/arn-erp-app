import 'package:flutter/foundation.dart';

/// MOTUS platform helpers kept in one web-safe place.
bool get isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool get isWebPlatform => kIsWeb;
