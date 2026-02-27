import "dart:async";
import "dart:io";

import "package:http/http.dart" as http;

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

  Future<HttpResponseData> getBytes(String url) async {
    Exception? lastError;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final uri = Uri.parse(url);
        final response = await _client
            .get(uri, headers: const {
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
