import { DaySchedule, ScheduleItem } from './types';

export interface Statistics {
  totalLessons: number;
  totalDays: number;
  disciplines: DisciplineStats[];
  teachers: TeacherStats[];
  classrooms: ClassroomStats[];
  lessonsPerDay: { [day: string]: number };
  mostBusyDay: string;
  leastBusyDay: string;
}

export interface DisciplineStats {
  name: string;
  count: number;
  percentage: number;
}

export interface TeacherStats {
  name: string;
  count: number;
}

export interface ClassroomStats {
  name: string;
  count: number;
}

export function calculateStatistics(schedules: DaySchedule[]): Statistics {
  if (schedules.length === 0) {
    return {
      totalLessons: 0,
      totalDays: 0,
      disciplines: [],
      teachers: [],
      classrooms: [],
      lessonsPerDay: {},
      mostBusyDay: '',
      leastBusyDay: '',
    };
  }

  const disciplineMap = new Map<string, number>();
  const teacherMap = new Map<string, number>();
  const classroomMap = new Map<string, number>();
  const dayMap = new Map<string, number>();
  let totalLessons = 0;

  schedules.forEach(daySchedule => {
    const dayName = daySchedule.day.toLowerCase();
    const dayCount = daySchedule.items.length;
    dayMap.set(dayName, (dayMap.get(dayName) || 0) + dayCount);
    totalLessons += dayCount;

    daySchedule.items.forEach(item => {
      // Подсчет дисциплин
      if (item.subject) {
        const subject = item.subject.trim();
        disciplineMap.set(subject, (disciplineMap.get(subject) || 0) + 1);
      }

      // Подсчет преподавателей
      if (item.teacher) {
        const teacher = item.teacher.trim();
        teacherMap.set(teacher, (teacherMap.get(teacher) || 0) + 1);
      }

      // Подсчет аудиторий
      if (item.classroom) {
        const classroom = item.classroom.trim();
        classroomMap.set(classroom, (classroomMap.get(classroom) || 0) + 1);
      }
    });
  });

  // Сортируем дисциплины по количеству
  const disciplines: DisciplineStats[] = Array.from(disciplineMap.entries())
    .map(([name, count]) => ({
      name,
      count,
      percentage: totalLessons > 0 ? Math.round((count / totalLessons) * 100) : 0,
    }))
    .sort((a, b) => b.count - a.count);

  // Сортируем преподавателей
  const teachers: TeacherStats[] = Array.from(teacherMap.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count);

  // Сортируем аудитории
  const classrooms: ClassroomStats[] = Array.from(classroomMap.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count);

  // Находим самый загруженный и наименее загруженный день
  const dayNames: { [key: string]: string } = {
    'понедельник': 'Понедельник',
    'вторник': 'Вторник',
    'среда': 'Среда',
    'четверг': 'Четверг',
    'пятница': 'Пятница',
    'суббота': 'Суббота',
    'воскресенье': 'Воскресенье',
    'пн': 'Понедельник',
    'вт': 'Вторник',
    'ср': 'Среда',
    'чт': 'Четверг',
    'пт': 'Пятница',
    'сб': 'Суббота',
    'вс': 'Воскресенье',
  };

  const lessonsPerDay: { [day: string]: number } = {};
  dayMap.forEach((count, day) => {
    const normalizedDay = dayNames[day] || day;
    lessonsPerDay[normalizedDay] = (lessonsPerDay[normalizedDay] || 0) + count;
  });

  const sortedDays = Object.entries(lessonsPerDay).sort((a, b) => b[1] - a[1]);
  const mostBusyDay = sortedDays.length > 0 ? sortedDays[0][0] : '';
  const leastBusyDay = sortedDays.length > 0 ? sortedDays[sortedDays.length - 1][0] : '';

  return {
    totalLessons,
    totalDays: schedules.length,
    disciplines,
    teachers,
    classrooms,
    lessonsPerDay,
    mostBusyDay,
    leastBusyDay,
  };
}



