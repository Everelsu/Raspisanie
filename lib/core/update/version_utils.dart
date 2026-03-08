/// Сравнивает версии в формате "major.minor.patch" (например 1.2.0 и 1.10.0).
/// Возвращает: < 0 если current < other, 0 если равны, > 0 если current > other.
int compareVersions(String current, String other) {
  final c = _parseVersion(current);
  final o = _parseVersion(other);
  if (c[0] != o[0]) return c[0].compareTo(o[0]);
  if (c[1] != o[1]) return c[1].compareTo(o[1]);
  return c[2].compareTo(o[2]);
}

List<int> _parseVersion(String v) {
  final parts = v.trim().split(RegExp(r"[.\s]"));
  return [
    int.tryParse(parts.isNotEmpty ? parts[0].replaceFirst("v", "") : "0") ?? 0,
    int.tryParse(parts.length > 1 ? parts[1] : "0") ?? 0,
    int.tryParse(parts.length > 2 ? parts[2] : "0") ?? 0,
  ];
}
