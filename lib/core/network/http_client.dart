import "dart:async";
import "dart:io";

import "package:flutter/foundation.dart" show kIsWeb;
import "package:http/http.dart" as http;

/// CORS-прокси для веб-сборки (`--dart-define=WEB_PROXY=https://…/api/proxy`).
/// Пусто — в вебе ходим только напрямую (GitHub Pages отдаёт CORS сам).
const _webProxy = String.fromEnvironment("WEB_PROXY");

class HttpResponseData {
  const HttpResponseData({
    required this.requestedUrl,
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });

  final String requestedUrl;
  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;
}

class HttpClientService {
  HttpClientService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 15);
  static const _maxRetries = 3;

  /// Хосты, отказавшие по CORS: дальше сразу идём через прокси, без лишнего круга.
  static final _corsBlockedHosts = <String>{};

  Future<HttpResponseData> getBytes(String url) async {
    Exception? lastError;
    var viaProxy = kIsWeb &&
        _webProxy.isNotEmpty &&
        _corsBlockedHosts.contains(Uri.tryParse(url)?.host);

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final uri = viaProxy
            ? Uri.parse(_webProxy).replace(queryParameters: {"url": url})
            : Uri.parse(url);
        final response = await _client
            .get(uri,
                // В браузере User-Agent — запрещённый заголовок.
                headers: kIsWeb
                    ? null
                    : const {
                        "User-Agent":
                            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                      })
            .timeout(_timeout);

        if (_isRetryableStatus(response.statusCode) && attempt < _maxRetries) {
          await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
          continue;
        }

        return HttpResponseData(
          requestedUrl: url,
          statusCode: response.statusCode,
          headers:
              response.headers.map((k, v) => MapEntry(k.toLowerCase(), v)),
          bodyBytes: response.bodyBytes,
        );
      } on TimeoutException {
        lastError = TimeoutException("Превышено время ожидания ($url)");
      } on SocketException catch (e) {
        lastError = SocketException("Нет подключения к сети: ${e.message}");
      } on http.ClientException catch (e) {
        // В вебе CORS-отказ выглядит как ClientException — повторяем через прокси.
        if (kIsWeb && !viaProxy && _webProxy.isNotEmpty) {
          viaProxy = true;
          _corsBlockedHosts.add(Uri.parse(url).host);
          continue;
        }
        lastError = http.ClientException("Ошибка сети: ${e.message}");
      } catch (e) {
        lastError = Exception("Неизвестная ошибка: $e");
      }

      if (attempt < _maxRetries) {
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }

    throw lastError ?? Exception("Не удалось загрузить данные.");
  }

  void dispose() => _client.close();

  bool _isRetryableStatus(int statusCode) =>
      statusCode >= 500 || statusCode == 429 || statusCode == 408;
}
