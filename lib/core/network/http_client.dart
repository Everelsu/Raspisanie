import "dart:async";
import "dart:io";

import "package:flutter/foundation.dart" show kIsWeb;
import "package:http/http.dart" as http;

import "../update/github_urls.dart";

/// CORS-прокси для веб-сборки (`--dart-define=WEB_PROXY=https://…/api/proxy`) —
/// последний шанс, если страницы нет в зеркале. Пусто — без прокси.
const _webProxy = String.fromEnvironment("WEB_PROXY");

/// Веб: откуда брать страницу. Сайты колледжей не отдают CORS, поэтому после
/// отказа «напрямую» идём в зеркало на GitHub, а если там нет файла — в прокси.
enum _WebRoute { direct, mirror, proxy }

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

  /// Хосты, отказавшие по CORS: дальше сразу идём в зеркало, без лишнего круга.
  static final _corsBlockedHosts = <String>{};

  Future<HttpResponseData> getBytes(String url) async {
    Exception? lastError;
    final host = Uri.tryParse(url)?.host ?? "";
    var route = _corsBlockedHosts.contains(host)
        ? _WebRoute.mirror
        : _WebRoute.direct;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final uri = kIsWeb ? _webUri(url, route) : Uri.parse(url);
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

        if (kIsWeb &&
            route == _WebRoute.mirror &&
            response.statusCode == 404 &&
            _webProxy.isNotEmpty) {
          route = _WebRoute.proxy;
          continue;
        }

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
        // В вебе CORS-отказ выглядит как ClientException — идём в зеркало.
        if (kIsWeb && route == _WebRoute.direct) {
          route = _WebRoute.mirror;
          _corsBlockedHosts.add(host);
          continue;
        }
        if (kIsWeb && route == _WebRoute.mirror && _webProxy.isNotEmpty) {
          route = _WebRoute.proxy;
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

  Uri _webUri(String url, _WebRoute route) {
    final uri = Uri.parse(url);
    return switch (route) {
      _WebRoute.direct => uri,
      _WebRoute.mirror =>
        Uri.parse("${GitHubProjectUrls.mirrorRaw}${uri.host}${uri.path}"),
      _WebRoute.proxy =>
        Uri.parse(_webProxy).replace(queryParameters: {"url": url}),
    };
  }

  void dispose() => _client.close();

  bool _isRetryableStatus(int statusCode) =>
      statusCode >= 500 || statusCode == 429 || statusCode == 408;
}
