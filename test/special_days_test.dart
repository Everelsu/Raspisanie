import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:raspiflutter/features/schedule/data/lesson_times.dart';
import 'package:raspiflutter/features/schedule/data/special_days.dart';

void main() {
  const json = '''
{
  "2026-12-31": {
    "kind": "short",
    "title": "Сокращённый день",
    "colleges": ["chtotib"],
    "times": {
      "1": { "start": "08:15", "end": "09:00" },
      "2": { "start": "09:10", "end": "09:55" }
    }
  },
  "2026-12-29..2027-01-11": {
    "kind": "holiday", "title": "Зимние каникулы", "noClasses": true
  },
  "битая дата": { "title": "x" },
  "2026-05-01": { "kind": "holiday" }
}
''';

  setUp(() => SpecialDays.load(SpecialDays.parse(json)));
  tearDown(() => SpecialDays.load(const []));

  test('битые записи пропускаются, остальное читается', () {
    expect(SpecialDays.parse(json), hasLength(2));
    expect(SpecialDays.parse('не json'), isEmpty);
  });

  test('сокращённый день меняет время только своей даты и техникума', () {
    expect(
      LessonTimes.formatTime(1, college: 'chtotib', date: '31.12.2026'),
      '08:15 - 09:00',
    );
    // Другой день — обычное время.
    expect(
      LessonTimes.formatTime(1, college: 'chtotib', date: '30.12.2026'),
      LessonTimes.formatTime(1, college: 'chtotib'),
    );
    // Другой техникум — обычное время.
    expect(
      LessonTimes.formatTime(1, college: 'zabgc', date: '31.12.2026'),
      LessonTimes.formatTime(1, college: 'zabgc'),
    );
    // Перемена считается по времени сокращённого дня.
    expect(
      LessonTimes.getBreakText(1, 2, college: 'chtotib', date: '2026-12-31'),
      'Перемена: 09:00 - 09:10',
    );
  });

  test('узкая запись важнее широкой, диапазон покрывает все дни', () {
    expect(
      SpecialDays.forRawDate('31.12.2026', 'chtotib')?.title,
      'Сокращённый день',
    );
    // Для zabgc сокращённого нет — действуют каникулы.
    expect(
      SpecialDays.forRawDate('31.12.2026', 'zabgc')?.title,
      'Зимние каникулы',
    );
    expect(SpecialDays.forRawDate('05.01.2027', 'zabgc')?.noClasses, isTrue);
    expect(SpecialDays.forRawDate('12.01.2027', 'zabgc'), isNull);
  });

  test('пресет времени и строгие даты', () {
    SpecialDays.load(SpecialDays.parse(
        File('tool/remote_config/special_days.json').readAsStringSync()));
    // Сокращёнка ЧТОТиБ по астрономическому часу — из пресета.
    expect(
      LessonTimes.formatTime(4, college: 'chtotib', date: '31.12.2026'),
      '12:05 - 13:05',
    );
    expect(
      LessonTimes.getLunchText(3, college: 'chtotib', date: '31.12.2026'),
      'Обед: 11:35 - 12:05',
    );
    // Перепутанные день и месяц не «переносятся» в другую дату.
    expect(
      SpecialDays.parse('{"2026-31-12": {"title": "x"}}'),
      isEmpty,
    );
  });

  test('шаблоны для консоли Firebase валидны', () {
    final days = SpecialDays.parse(
        File('tool/remote_config/special_days.json').readAsStringSync());
    expect(days, hasLength(3));
    final times = File('tool/remote_config/lesson_times.json').readAsStringSync();
    expect(times, contains('"chtotib"'));
  });
}
