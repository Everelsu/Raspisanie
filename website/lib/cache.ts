import { DaySchedule, College } from './types';

const CACHE_PREFIX = 'schedule_cache_';
const CACHE_DURATION = 1000 * 60 * 30; // 30 минут
const CACHE_STALE_DURATION = 1000 * 60 * 60 * 24; // 24 часа для устаревшего кэша

interface CachedSchedule {
  data: DaySchedule[];
  timestamp: number;
  college: College;
  group: string;
}

export function getCachedSchedule(group: string, college: College, allowStale = false): DaySchedule[] | null {
  if (typeof window === 'undefined') {
    return null;
  }
  
  try {
    const cacheKey = `${CACHE_PREFIX}${college}_${group}`;
    const cached = localStorage.getItem(cacheKey);
    
    if (!cached) {
      return null;
    }
    
    const parsed: CachedSchedule = JSON.parse(cached);
    const now = Date.now();
    const age = now - parsed.timestamp;
    
    // Проверяем, что это та же группа и колледж
    if (parsed.college !== college || parsed.group !== group) {
      return null;
    }
    
    // Проверяем срок действия кэша
    if (age > CACHE_DURATION) {
      if (allowStale && age < CACHE_STALE_DURATION) {
        // Возвращаем устаревший кэш, если разрешено
        return parsed.data;
      }
      localStorage.removeItem(cacheKey);
      return null;
    }
    
    return parsed.data;
  } catch (e) {
    console.warn('Ошибка чтения кэша:', e);
    return null;
  }
}

export function setCachedSchedule(group: string, college: College, data: DaySchedule[]): void {
  if (typeof window === 'undefined') {
    return;
  }
  
  try {
    const cacheKey = `${CACHE_PREFIX}${college}_${group}`;
    const cached: CachedSchedule = {
      data,
      timestamp: Date.now(),
      college,
      group,
    };
    
    localStorage.setItem(cacheKey, JSON.stringify(cached));
  } catch (e) {
    console.warn('Ошибка записи кэша:', e);
    // Если localStorage переполнен, очищаем старые кэши
    clearOldCaches();
  }
}

function clearOldCaches(): void {
  if (typeof window === 'undefined') {
    return;
  }
  
  try {
    const now = Date.now();
    const keysToRemove: string[] = [];
    
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key?.startsWith(CACHE_PREFIX)) {
        try {
          const cached = localStorage.getItem(key);
          if (cached) {
            const parsed: CachedSchedule = JSON.parse(cached);
            if (now - parsed.timestamp > CACHE_DURATION) {
              keysToRemove.push(key);
            }
          }
        } catch (e) {
          keysToRemove.push(key);
        }
      }
    }
    
    keysToRemove.forEach(key => localStorage.removeItem(key));
  } catch (e) {
    console.warn('Ошибка очистки кэша:', e);
  }
}

export function clearAllCaches(): void {
  if (typeof window === 'undefined') {
    return;
  }
  
  try {
    const keysToRemove: string[] = [];
    
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key?.startsWith(CACHE_PREFIX)) {
        keysToRemove.push(key);
      }
    }
    
    keysToRemove.forEach(key => localStorage.removeItem(key));
  } catch (e) {
    console.warn('Ошибка очистки всех кэшей:', e);
  }
}

