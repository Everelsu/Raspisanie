import "dart:convert";

class DecodedHtml {
  const DecodedHtml({
    required this.html,
    required this.charset,
  });

  final String html;
  final String charset;
}

class EncodingDecoder {
  static final RegExp _charsetFromMeta = RegExp(
    r'''charset\s*=\s*['"]?\s*([a-zA-Z0-9\-_]+)''',
    caseSensitive: false,
  );

  DecodedHtml decode({
    required List<int> bytes,
    required Map<String, String> headers,
  }) {
    final contentType = headers["content-type"] ?? "";
    final charset = _normalizeCharset(
      _extractCharset(contentType) ??
          _extractCharsetFromHead(bytes) ??
          "utf-8",
    );

    final html = switch (charset) {
      "windows-1251" => _decodeWindows1251(bytes),
      "cp1251" => _decodeWindows1251(bytes),
      "koi8-r" => _decodeKoi8r(bytes),
      "iso-8859-5" => _decodeIso88595(bytes),
      _ => utf8.decode(bytes, allowMalformed: true),
    };

    return DecodedHtml(html: html, charset: charset);
  }

  String? _extractCharset(String raw) {
    final match = _charsetFromMeta.firstMatch(raw);
    return match?.group(1);
  }

  String? _extractCharsetFromHead(List<int> bytes) {
    final sample = latin1.decode(bytes.take(4096).toList(), allowInvalid: true);
    final match = _charsetFromMeta.firstMatch(sample);
    return match?.group(1);
  }

  String _normalizeCharset(String raw) => raw.trim().toLowerCase();

  String _decodeWindows1251(List<int> bytes) {
    const map = <int, int>{
      0x80: 0x0402,
      0x81: 0x0403,
      0x82: 0x201A,
      0x83: 0x0453,
      0x84: 0x201E,
      0x85: 0x2026,
      0x86: 0x2020,
      0x87: 0x2021,
      0x88: 0x20AC,
      0x89: 0x2030,
      0x8A: 0x0409,
      0x8B: 0x2039,
      0x8C: 0x040A,
      0x8D: 0x040C,
      0x8E: 0x040B,
      0x8F: 0x040F,
      0x90: 0x0452,
      0x91: 0x2018,
      0x92: 0x2019,
      0x93: 0x201C,
      0x94: 0x201D,
      0x95: 0x2022,
      0x96: 0x2013,
      0x97: 0x2014,
      0x99: 0x2122,
      0x9A: 0x0459,
      0x9B: 0x203A,
      0x9C: 0x045A,
      0x9D: 0x045C,
      0x9E: 0x045B,
      0x9F: 0x045F,
      0xA0: 0x00A0,
      0xA1: 0x040E,
      0xA2: 0x045E,
      0xA3: 0x0408,
      0xA4: 0x00A4,
      0xA5: 0x0490,
      0xA6: 0x00A6,
      0xA7: 0x00A7,
      0xA8: 0x0401,
      0xA9: 0x00A9,
      0xAA: 0x0404,
      0xAB: 0x00AB,
      0xAC: 0x00AC,
      0xAD: 0x00AD,
      0xAE: 0x00AE,
      0xAF: 0x0407,
      0xB0: 0x00B0,
      0xB1: 0x00B1,
      0xB2: 0x0406,
      0xB3: 0x0456,
      0xB4: 0x0491,
      0xB5: 0x00B5,
      0xB6: 0x00B6,
      0xB7: 0x00B7,
      0xB8: 0x0451,
      0xB9: 0x2116,
      0xBA: 0x0454,
      0xBB: 0x00BB,
      0xBC: 0x0458,
      0xBD: 0x0405,
      0xBE: 0x0455,
      0xBF: 0x0457,
    };
    return _decodeByMap(
      bytes,
      mapper: (byte) {
        if (byte < 0x80) return byte;
        if (byte >= 0xC0) return 0x0410 + (byte - 0xC0);
        return map[byte] ?? 0xFFFD;
      },
    );
  }

  String _decodeIso88595(List<int> bytes) {
    return _decodeByMap(
      bytes,
      mapper: (byte) {
        if (byte < 0x80) return byte;
        if (byte == 0xA0) return 0x00A0;
        if (byte >= 0xB0 && byte <= 0xCF) return 0x0410 + (byte - 0xB0);
        if (byte >= 0xD0 && byte <= 0xEF) return 0x0430 + (byte - 0xD0);
        if (byte == 0xF0) return 0x2116;
        if (byte >= 0xA1 && byte <= 0xAF) return 0x0401 + (byte - 0xA1);
        if (byte >= 0xF1 && byte <= 0xFF) return 0x0451 + (byte - 0xF1);
        return 0xFFFD;
      },
    );
  }

  String _decodeKoi8r(List<int> bytes) {
    const order = <String>[
      "ю",
      "а",
      "б",
      "ц",
      "д",
      "е",
      "ф",
      "г",
      "х",
      "и",
      "й",
      "к",
      "л",
      "м",
      "н",
      "о",
      "п",
      "я",
      "р",
      "с",
      "т",
      "у",
      "ж",
      "в",
      "ь",
      "ы",
      "з",
      "ш",
      "э",
      "щ",
      "ч",
      "ъ",
    ];

    return _decodeByMap(
      bytes,
      mapper: (byte) {
        if (byte < 0x80) return byte;
        if (byte >= 0xE0 && byte <= 0xFF) {
          return order[byte - 0xE0].codeUnitAt(0);
        }
        if (byte >= 0xC0 && byte <= 0xDF) {
          return order[byte - 0xC0].toUpperCase().codeUnitAt(0);
        }
        if (byte == 0xA3) return 0x0401;
        if (byte == 0xB3) return 0x0451;
        return 0xFFFD;
      },
    );
  }

  String _decodeByMap(
    List<int> bytes, {
    required int Function(int byte) mapper,
  }) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.writeCharCode(mapper(byte));
    }
    return buffer.toString();
  }
}
