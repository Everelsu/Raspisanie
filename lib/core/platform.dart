import "dart:io" show Platform;

import "package:flutter/foundation.dart" show kIsWeb;

// Platform.isX бросает исключение в вебе, поэтому платформу проверяем через эти геттеры.
bool get isAndroid => !kIsWeb && Platform.isAndroid;
bool get isIOS => !kIsWeb && Platform.isIOS;
