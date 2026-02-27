enum ScheduleKind {
  basic(prefix: "bg"),
  current(prefix: "cg"),
  today(prefix: "hg");

  const ScheduleKind({required this.prefix});
  final String prefix;
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.fileName,
    required this.pageUrl,
  });

  final int id;
  final String name;
  final String fileName;
  final String pageUrl;

  String fileForKind(ScheduleKind kind) => "${kind.prefix}$id.htm";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group && id == other.id && fileName == other.fileName;

  @override
  int get hashCode => Object.hash(id, fileName);

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "fileName": fileName,
        "pageUrl": pageUrl,
      };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json["id"] as int,
        name: json["name"] as String,
        fileName: json["fileName"] as String,
        pageUrl: json["pageUrl"] as String,
      );
}

class ScheduleItem {
  const ScheduleItem({
    required this.day,
    required this.date,
    required this.weekNumber,
    required this.lessonNumber,
    this.subject,
    this.classroom,
    this.teacher,
    this.subgroup,
    this.subjectHref,
    this.classroomHref,
    this.teacherHref,
  });

  final String day;
  final String date;
  final int weekNumber;
  final int lessonNumber;
  final String? subject;
  final String? classroom;
  final String? teacher;
  final int? subgroup;
  final String? subjectHref;
  final String? classroomHref;
  final String? teacherHref;

  Map<String, dynamic> toJson() => {
        "day": day,
        "date": date,
        "weekNumber": weekNumber,
        "lessonNumber": lessonNumber,
        "subject": subject,
        "classroom": classroom,
        "teacher": teacher,
        "subgroup": subgroup,
        "subjectHref": subjectHref,
        "classroomHref": classroomHref,
        "teacherHref": teacherHref,
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        day: json["day"] as String,
        date: json["date"] as String,
        weekNumber: json["weekNumber"] as int,
        lessonNumber: json["lessonNumber"] as int,
        subject: json["subject"] as String?,
        classroom: json["classroom"] as String?,
        teacher: json["teacher"] as String?,
        subgroup: json["subgroup"] as int?,
        subjectHref: json["subjectHref"] as String?,
        classroomHref: json["classroomHref"] as String?,
        teacherHref: json["teacherHref"] as String?,
      );
}

class DaySchedule {
  const DaySchedule({
    required this.day,
    required this.date,
    required this.weekNumber,
    required this.items,
  });

  final String day;
  final String date;
  final int weekNumber;
  final List<ScheduleItem> items;

  bool get isEmpty => items.isEmpty;

  Map<String, dynamic> toJson() => {
        "day": day,
        "date": date,
        "weekNumber": weekNumber,
        "items": items.map((e) => e.toJson()).toList(),
      };

  factory DaySchedule.fromJson(Map<String, dynamic> json) => DaySchedule(
        day: json["day"] as String,
        date: json["date"] as String,
        weekNumber: json["weekNumber"] as int,
        items: (json["items"] as List)
            .map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DisciplineStatistics {
  const DisciplineStatistics({
    this.number = "",
    this.teacher = "",
    this.group = "",
    this.discipline = "",
    this.lessonType = "",
    this.totalHours,
    this.plannedHours,
    this.factHours,
    this.remainingHours,
    this.plannedIn2Weeks,
    this.factIn2Weeks,
    this.completionDate,
    this.completionPercent,
  });

  final String number;
  final String teacher;
  final String group;
  final String discipline;
  final String lessonType;
  final int? totalHours;
  final int? plannedHours;
  final int? factHours;
  final int? remainingHours;
  final String? plannedIn2Weeks;
  final String? factIn2Weeks;
  final String? completionDate;
  final String? completionPercent;

  int get completionPercentInt {
    if (totalHours == null || totalHours == 0) return 0;
    final fact = factHours ?? 0;
    return ((fact * 100) / totalHours!).clamp(0, 100).toInt();
  }

  Map<String, dynamic> toJson() => {
        "number": number,
        "teacher": teacher,
        "group": group,
        "discipline": discipline,
        "lessonType": lessonType,
        "totalHours": totalHours,
        "plannedHours": plannedHours,
        "factHours": factHours,
        "remainingHours": remainingHours,
        "plannedIn2Weeks": plannedIn2Weeks,
        "factIn2Weeks": factIn2Weeks,
        "completionDate": completionDate,
        "completionPercent": completionPercent,
      };

  factory DisciplineStatistics.fromJson(Map<String, dynamic> json) =>
      DisciplineStatistics(
        number: json["number"] as String? ?? "",
        teacher: json["teacher"] as String? ?? "",
        group: json["group"] as String? ?? "",
        discipline: json["discipline"] as String? ?? "",
        lessonType: json["lessonType"] as String? ?? "",
        totalHours: json["totalHours"] as int?,
        plannedHours: json["plannedHours"] as int?,
        factHours: json["factHours"] as int?,
        remainingHours: json["remainingHours"] as int?,
        plannedIn2Weeks: json["plannedIn2Weeks"] as String?,
        factIn2Weeks: json["factIn2Weeks"] as String?,
        completionDate: json["completionDate"] as String?,
        completionPercent: json["completionPercent"] as String?,
      );
}

class GroupStatistics {
  const GroupStatistics({
    this.groupName = "",
    this.disciplines = const [],
    this.totalHours,
    this.completedHours,
    this.remainingHours,
    this.plannedHours,
  });

  final String groupName;
  final List<DisciplineStatistics> disciplines;
  final int? totalHours;
  final int? completedHours;
  final int? remainingHours;
  final int? plannedHours;

  Map<String, dynamic> toJson() => {
        "groupName": groupName,
        "disciplines": disciplines.map((d) => d.toJson()).toList(),
        "totalHours": totalHours,
        "completedHours": completedHours,
        "remainingHours": remainingHours,
        "plannedHours": plannedHours,
      };

  factory GroupStatistics.fromJson(Map<String, dynamic> json) =>
      GroupStatistics(
        groupName: json["groupName"] as String? ?? "",
        disciplines: (json["disciplines"] as List?)
                ?.map((e) =>
                    DisciplineStatistics.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        totalHours: json["totalHours"] as int?,
        completedHours: json["completedHours"] as int?,
        remainingHours: json["remainingHours"] as int?,
        plannedHours: json["plannedHours"] as int?,
      );
}
