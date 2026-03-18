import "dart:async";
import "dart:io";

import "package:http/http.dart" as http;

import "../network/http_client.dart";

/// HTTP GET с повторами для GitHub (raw / API): TLS, таймауты, 5xx.
class GitHubHttpClient {
  GitHubHttpClient._();

  static const Duration _timeout = Duration(seconds: 20);
  static const int _maxAttempts = 4;
  static const String userAgent =
      "Raspisanie/2 (Flutter; +https://github.com/Everelsu/Raspisanie)";

  static Future<HttpResponseData> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final client = http.Client();
    try {
      Object? lastError;
      for (var attempt = 0; attempt < _maxAttempts; attempt++) {
        try {
          final response = await client
              .get(
                Uri.parse(url),
                headers: {
                  "User-Agent": userAgent,
                  ...?headers,
                },
              )
              .timeout(_timeout);
          final code = response.statusCode;
          if ((code >= 500 || code == 429 || code == 408) &&
              attempt < _maxAttempts - 1) {
            await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
            continue;
          }
          return HttpResponseData(
            requestedUrl: url,
            statusCode: code,
            headers:
                response.headers.map((k, v) => MapEntry(k.toLowerCase(), v)),
            bodyBytes: response.bodyBytes,
          );
        } on TimeoutException catch (e) {
          lastError = e;
        } on SocketException catch (e) {
          lastError = Exception("Сеть: ${e.message}");
        } on HandshakeException catch (e) {
          lastError = Exception("TLS handshake: ${e.message}");
        } on TlsException catch (e) {
          lastError = Exception("TLS: ${e.message}");
        } on http.ClientException catch (e) {
          lastError = Exception("HTTP: ${e.message}");
        } catch (e) {
          lastError = e is Exception ? e : Exception("$e");
        }
        if (attempt < _maxAttempts - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
      throw lastError is Exception
          ? lastError as Exception
          : Exception("$lastError");
    } finally {
      client.close();
    }
  }
}
