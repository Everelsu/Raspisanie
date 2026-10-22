/// Поиск групп и преподавателей «по смыслу», а не по точной подстроке.
///
/// Не важны регистр, пробелы, дефисы и точки; латинские двойники кириллицы
/// (C, A, P, X…) и ё/е считаются одной буквой; русский запрос, набранный в
/// английской раскладке («cbc 23»), тоже находится. Сокращения — по
/// буквам подряд: «исп21» → «ИСиП-21».
///
/// «сис 23» → «СиС-23», «иванов и» → «Иванов И.И.».
abstract final class GroupSearch {
  /// Релевантность [name] для [query]: меньше — лучше, `null` — не подходит.
  static int? score(String query, String name) {
    final q = query.trim();
    if (q.isEmpty) return 0;
    final target = _compact(_fold(name));
    var best = _scoreFolded(_fold(q), target);
    // Набрано в английской раскладке — пробуем как русскую.
    if (RegExp(r'[a-z\[\];,.]').hasMatch(q.toLowerCase())) {
      final alt = _scoreFolded(_fold(_fromQwerty(q)), target);
      if (alt != null && (best == null || alt < best)) best = alt;
    }
    return best;
  }

  /// [items] в порядке релевантности для [query] (неподходящие отброшены).
  static List<T> filter<T>(
      Iterable<T> items, String query, String Function(T) nameOf) {
    if (query.trim().isEmpty) return items.toList();
    final scored = <(T, int)>[];
    for (final item in items) {
      final s = score(query, nameOf(item));
      if (s != null) scored.add((item, s));
    }
    scored.sort((a, b) {
      final c = a.$2.compareTo(b.$2);
      if (c != 0) return c;
      return nameOf(a.$1).length.compareTo(nameOf(b.$1).length);
    });
    return [for (final (item, _) in scored) item];
  }

  static int? _scoreFolded(String folded, String target) {
    final compactQuery = _compact(folded);
    if (compactQuery.isEmpty) return null;
    if (target.startsWith(compactQuery)) return 0;
    final tokens = folded
        .split(RegExp(r'[^0-9a-zа-я]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (_inOrder(tokens, target)) return 1;
    if (target.contains(compactQuery)) return 2;
    if (tokens.every(target.contains)) return 3;
    if (_isSubsequence(compactQuery, target)) return 4;
    return null;
  }

  static bool _inOrder(List<String> tokens, String target) {
    var from = 0;
    for (final t in tokens) {
      final i = target.indexOf(t, from);
      if (i < 0) return false;
      from = i + t.length;
    }
    return true;
  }

  static bool _isSubsequence(String q, String target) {
    var i = 0;
    for (var j = 0; j < target.length && i < q.length; j++) {
      if (q.codeUnitAt(i) == target.codeUnitAt(j)) i++;
    }
    return i == q.length;
  }

  static String _compact(String s) => s.replaceAll(RegExp(r'[^0-9a-zа-я]'), '');

  /// Нижний регистр, ё → е, латинские двойники → кириллица.
  static String _fold(String s) {
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final ch in lower.split('')) {
      out.write(_homoglyphs[ch] ?? (ch == 'ё' ? 'е' : ch));
    }
    return out.toString();
  }

  static String _fromQwerty(String s) {
    final out = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      out.write(_qwerty[ch] ?? ch);
    }
    return out.toString();
  }

  static const _homoglyphs = {
    'a': 'а',
    'b': 'в',
    'c': 'с',
    'e': 'е',
    'h': 'н',
    'k': 'к',
    'm': 'м',
    'o': 'о',
    'p': 'р',
    't': 'т',
    'x': 'х',
    'y': 'у',
  };

  static const _qwerty = {
    'q': 'й',
    'w': 'ц',
    'e': 'у',
    'r': 'к',
    't': 'е',
    'y': 'н',
    'u': 'г',
    'i': 'ш',
    'o': 'щ',
    'p': 'з',
    '[': 'х',
    ']': 'ъ',
    'a': 'ф',
    's': 'ы',
    'd': 'в',
    'f': 'а',
    'g': 'п',
    'h': 'р',
    'j': 'о',
    'k': 'л',
    'l': 'д',
    ';': 'ж',
    "'": 'э',
    'z': 'я',
    'x': 'ч',
    'c': 'с',
    'v': 'м',
    'b': 'и',
    'n': 'т',
    'm': 'ь',
    ',': 'б',
    '.': 'ю',
  };
}
