export const CONFIG = {
  BASE_URL_CHTOTIB: 'https://www.chtotib.ru/schedule_gl/',
  BASE_URL_ZABGC: 'https://bbb.zabgc.ru/',
  GROUPS_URL_CHTOTIB: 'https://www.chtotib.ru/schedule_gl/cg.htm',
  GROUPS_URL_ZABGC: 'https://bbb.zabgc.ru/cg.htm',
  CORS_PROXY: 'https://api.allorigins.win/get?url=',
  CORS_PROXY_RAW: 'https://api.allorigins.win/raw?url=',
} as const;

export const LESSON_TIMES = {
  chtotib: {
    1: { start: '8:15', end: '9:15' },
    2: { start: '9:25', end: '10:25' },
    3: { start: '10:35', end: '11:35' },
    4: { start: '12:15', end: '13:15' },
    5: { start: '13:25', end: '14:25' },
    6: { start: '14:35', end: '15:35' },
    7: { start: '16:05', end: '17:05' },
    8: { start: '17:15', end: '18:15' }
  },
  zabgc: {
    1: { start: '8:30', end: '10:05' },
    2: { start: '10:15', end: '11:50' },
    3: { start: '12:30', end: '14:05' },
    4: { start: '14:15', end: '15:50' },
    5: { start: '16:00', end: '17:35' },
    6: { start: '17:45', end: '19:20' }
  }
} as const;

export const BREAKS = {
  chtotib: {
    '1-2': 'Перемена: 9:15 - 9:25',
    '2-3': 'Перемена: 10:25 - 10:35',
    '4-5': 'Перемена: 13:15 - 13:25',
    '5-6': 'Перемена: 14:25 - 14:35',
    '7-8': 'Перемена: 17:05 - 17:15'
  },
  zabgc: {
    '1-2': 'Перемена: 10:05 - 10:15',
    '3-4': 'Перемена: 14:05 - 14:15',
    '4-5': 'Перемена: 15:50 - 16:00',
    '5-6': 'Перемена: 17:35 - 17:45'
  }
} as const;

export const LUNCHES = {
  chtotib: {
    3: 'Обед: 11:35 - 12:15',
    6: 'Обед: 15:35 - 16:05'
  },
  zabgc: {
    2: 'Обед: 11:50 - 12:30'
  }
} as const;

export type College = 'chtotib' | 'zabgc';
export type Theme = 'dark' | 'light' | 'purple' | 'green' | 'halloween' | 'nothing' | 'newyear';



