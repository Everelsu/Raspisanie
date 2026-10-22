import 'package:flutter_test/flutter_test.dart';
import 'package:raspiflutter/features/schedule/domain/group_search.dart';

void main() {
  const groups = ['СиС-23', 'СиС-22', 'ИСиП-21', 'АРХ-24-1', 'ТО-23'];
  List<String> find(String q) => GroupSearch.filter(groups, q, (g) => g);

  test('пробелы, дефисы и регистр не важны', () {
    expect(find('сис 23').first, 'СиС-23');
    expect(find('СИС23').first, 'СиС-23');
    expect(find('арх 24'), ['АРХ-24-1']);
  });

  test('сокращения по буквам подряд', () {
    expect(find('исп21'), ['ИСиП-21']);
  });

  test('английская раскладка и латинские двойники', () {
    expect(find('cbc 23').first, 'СиС-23'); // набрано в EN-раскладке
    expect(find('CиC-23').first, 'СиС-23'); // латинские C вместо С
  });

  test('преподаватели по фамилии и инициалу', () {
    final teachers = ['Иванов И.И.', 'Иванова А.П.', 'Петров И.С.'];
    expect(
      GroupSearch.filter(teachers, 'иванов и', (t) => t).first,
      'Иванов И.И.',
    );
  });

  test('лучшее совпадение — первым, лишнее отброшено', () {
    expect(find('сис 22').first, 'СиС-22');
    expect(find('ззз'), isEmpty);
    expect(find(''), groups);
  });
}
