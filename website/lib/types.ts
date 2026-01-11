import { College, Theme } from './config';

// Реэкспортируем типы, чтобы их можно было импортировать из '@/lib/types'
export type { College, Theme } from './config';

export interface Group {
  file: string;
  name: string;
}

export interface ScheduleItem {
  lessonNumber: number;
  subject: string;
  classroom?: string;
  teacher?: string;
  subgroup?: number;
}

export interface DaySchedule {
  day: string;
  date: string;
  weekNumber: number;
  items: ScheduleItem[];
}

export interface AppState {
  college: College;
  group: string;
  groupName: string;
  theme: Theme;
  showBreaks: boolean;
  showLunch: boolean;
}

