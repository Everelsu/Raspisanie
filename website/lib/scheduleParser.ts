import { CONFIG, College } from './config';
import { DaySchedule, ScheduleItem, Group } from './types';

export async function fetchWithProxy(url: string, useRaw = false): Promise<string> {
  const proxyUrl = useRaw 
    ? CONFIG.CORS_PROXY_RAW + encodeURIComponent(url)
    : CONFIG.CORS_PROXY + encodeURIComponent(url);
  
  // Используем AbortController для таймаута
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 15000); // 15 секунд таймаут
  
  try {
    const response = await fetch(proxyUrl, {
      signal: controller.signal,
      // Добавляем заголовки для кэширования браузера
      cache: 'default',
    });
    
    clearTimeout(timeoutId);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    
    if (useRaw) {
      const arrayBuffer = await response.arrayBuffer();
      const bytes = new Uint8Array(arrayBuffer);
      // Декодируем сразу, но используем requestIdleCallback для больших данных
      if (bytes.length > 50000 && typeof window !== 'undefined' && 'requestIdleCallback' in window) {
        return new Promise<string>((resolve) => {
          (window as any).requestIdleCallback(() => {
            resolve(decodeWindows1251(bytes));
          }, { timeout: 100 });
        });
      }
      return decodeWindows1251(bytes);
    } else {
      const data = await response.json();
      return data.contents || '';
    }
  } catch (error: any) {
    clearTimeout(timeoutId);
    if (error.name === 'AbortError') {
      throw new Error('Превышено время ожидания ответа');
    }
    throw error;
  }
}

// Оптимизированная таблица декодирования (статическая для быстрого доступа)
const WIN1251_TO_UTF8 = new Uint16Array(256);
for (let i = 0; i < 256; i++) {
  if (i < 128) {
    WIN1251_TO_UTF8[i] = i;
  } else if (i >= 0xC0 && i <= 0xFF) {
    const map: { [key: number]: number } = {
      0xC0: 0x0410, 0xC1: 0x0411, 0xC2: 0x0412, 0xC3: 0x0413, 0xC4: 0x0414,
      0xC5: 0x0415, 0xC6: 0x0416, 0xC7: 0x0417, 0xC8: 0x0418, 0xC9: 0x0419,
      0xCA: 0x041A, 0xCB: 0x041B, 0xCC: 0x041C, 0xCD: 0x041D, 0xCE: 0x041E,
      0xCF: 0x041F, 0xD0: 0x0420, 0xD1: 0x0421, 0xD2: 0x0422, 0xD3: 0x0423,
      0xD4: 0x0424, 0xD5: 0x0425, 0xD6: 0x0426, 0xD7: 0x0427, 0xD8: 0x0428,
      0xD9: 0x0429, 0xDA: 0x042A, 0xDB: 0x042B, 0xDC: 0x042C, 0xDD: 0x042D,
      0xDE: 0x042E, 0xDF: 0x042F, 0xE0: 0x0430, 0xE1: 0x0431, 0xE2: 0x0432,
      0xE3: 0x0433, 0xE4: 0x0434, 0xE5: 0x0435, 0xE6: 0x0436, 0xE7: 0x0437,
      0xE8: 0x0438, 0xE9: 0x0439, 0xEA: 0x043A, 0xEB: 0x043B, 0xEC: 0x043C,
      0xED: 0x043D, 0xEE: 0x043E, 0xEF: 0x043F, 0xF0: 0x0440, 0xF1: 0x0441,
      0xF2: 0x0442, 0xF3: 0x0443, 0xF4: 0x0444, 0xF5: 0x0445, 0xF6: 0x0446,
      0xF7: 0x0447, 0xF8: 0x0448, 0xF9: 0x0449, 0xFA: 0x044A, 0xFB: 0x044B,
      0xFC: 0x044C, 0xFD: 0x044D, 0xFE: 0x044E, 0xFF: 0x044F
    };
    WIN1251_TO_UTF8[i] = map[i] || i;
  } else {
    WIN1251_TO_UTF8[i] = i;
  }
}

function decodeWindows1251(bytes: Uint8Array): string {
  // Используем TextDecoder для более быстрого декодирования, если доступен
  if (typeof TextDecoder !== 'undefined') {
    try {
      // Пробуем использовать встроенный декодер (самый быстрый метод)
      const decoder = new TextDecoder('windows-1251');
      return decoder.decode(bytes);
    } catch (e) {
      // Fallback на ручное декодирование
    }
  }
  
  // Оптимизированное ручное декодирование с предварительно вычисленной таблицей
  const length = bytes.length;
  
  // Для очень маленьких массивов - простой цикл
  if (length < 1000) {
    let result = '';
    for (let i = 0; i < length; i++) {
      result += String.fromCharCode(WIN1251_TO_UTF8[bytes[i]]);
    }
    return result;
  }
  
  // Для средних массивов - используем массив строк
  if (length < 50000) {
    const result: string[] = new Array(length);
    for (let i = 0; i < length; i++) {
      result[i] = String.fromCharCode(WIN1251_TO_UTF8[bytes[i]]);
    }
    return result.join('');
  }
  
  // Для больших массивов - используем TypedArray и batch обработку
  // Разбиваем на чанки для лучшей производительности
  const CHUNK_SIZE = 10000;
  const chunks: string[] = [];
  
  for (let i = 0; i < length; i += CHUNK_SIZE) {
    const chunkEnd = Math.min(i + CHUNK_SIZE, length);
    const chunkCodes = new Uint16Array(chunkEnd - i);
    for (let j = i; j < chunkEnd; j++) {
      chunkCodes[j - i] = WIN1251_TO_UTF8[bytes[j]];
    }
    chunks.push(String.fromCharCode.apply(null, Array.from(chunkCodes)));
  }
  
  return chunks.join('');
}

// Кэш для групп (чтобы не парсить каждый раз)
const groupsCache = new Map<string, { groups: Group[]; timestamp: number }>();
const GROUPS_CACHE_DURATION = 1000 * 60 * 60; // 1 час

export async function loadGroups(college: College): Promise<Group[]> {
  const cacheKey = `groups_${college}`;
  const cached = groupsCache.get(cacheKey);
  const now = Date.now();
  
  // Проверяем кэш в памяти
  if (cached && (now - cached.timestamp) < GROUPS_CACHE_DURATION) {
    return cached.groups;
  }
  
  const groupsUrl = college === 'zabgc' ? CONFIG.GROUPS_URL_ZABGC : CONFIG.GROUPS_URL_CHTOTIB;
  
  let htmlContent = '';
  
  if (college === 'zabgc') {
    try {
      htmlContent = await fetchWithProxy(groupsUrl, true);
    } catch (e) {
      console.warn('Ошибка загрузки raw данных, пробуем обычный метод:', e);
      htmlContent = await fetchWithProxy(groupsUrl, false);
      htmlContent = fixEncoding(htmlContent);
    }
  } else {
    htmlContent = await fetchWithProxy(groupsUrl, false);
  }
  
  const parser = new DOMParser();
  const doc = parser.parseFromString(htmlContent, 'text/html');
  
  const table = doc.querySelector('table.inf');
  const groups: Group[] = [];
  const seenFiles = new Set<string>(); // Используем Set для быстрой проверки уникальности
  
  if (table) {
    const rows = table.querySelectorAll('tr');
    const rowsLength = rows.length;
    
    // Предкомпилированные проверки для заголовков
    const headerKeywords = ['№ п.п', 'днев', 'пара', 'группа'];
    
    for (let i = 0; i < rowsLength; i++) {
      const row = rows[i];
      const headerCells = row.querySelectorAll('td.hd');
      
      if (headerCells.length > 0) {
        const headerText = (row.textContent || '').toLowerCase();
        let isHeader = false;
        for (let k = 0; k < headerKeywords.length; k++) {
          if (headerText.includes(headerKeywords[k])) {
            isHeader = true;
            break;
          }
        }
        if (isHeader) continue;
      }
      
      const links = row.querySelectorAll('a[href*="cg"][href*=".htm"], a.z0[href*="cg"], a[href^="cg"]');
      const linksLength = links.length;
      
      for (let j = 0; j < linksLength; j++) {
        const link = links[j];
        const href = link.getAttribute('href');
        const text = link.textContent;
        
        if (href && text) {
          const trimmedText = text.trim();
          if (!trimmedText) continue;
          
          // Оптимизация: используем более эффективные строковые операции
          let fileName = href;
          const lastSlash = href.lastIndexOf('/');
          if (lastSlash >= 0) {
            fileName = href.substring(lastSlash + 1);
          }
          const questionMark = fileName.indexOf('?');
          if (questionMark >= 0) {
            fileName = fileName.substring(0, questionMark);
          }
          
          if (fileName.startsWith('cg') && fileName.endsWith('.htm') && !seenFiles.has(fileName)) {
            seenFiles.add(fileName);
            groups.push({
              file: fileName,
              name: trimmedText
            });
          }
        }
      }
    }
  }
  
  // Сохраняем в кэш
  groupsCache.set(cacheKey, { groups, timestamp: now });
  
  return groups;
}

export async function loadSchedule(groupFile: string, college: College): Promise<DaySchedule[]> {
  const baseUrl = college === 'zabgc' ? CONFIG.BASE_URL_ZABGC : CONFIG.BASE_URL_CHTOTIB;
  const scheduleUrl = baseUrl + groupFile;
  
  let htmlContent = '';
  
  if (college === 'zabgc') {
    try {
      htmlContent = await fetchWithProxy(scheduleUrl, true);
    } catch (e) {
      console.warn('Ошибка загрузки raw данных, пробуем обычный метод:', e);
      htmlContent = await fetchWithProxy(scheduleUrl, false);
      htmlContent = fixEncoding(htmlContent);
    }
  } else {
    htmlContent = await fetchWithProxy(scheduleUrl, false);
  }
  
  // Оптимизация: парсим HTML асинхронно, чтобы не блокировать UI
  // Для больших HTML используем requestIdleCallback
  if (htmlContent.length > 100000 && typeof window !== 'undefined' && 'requestIdleCallback' in window) {
    return new Promise<DaySchedule[]>((resolve) => {
      (window as any).requestIdleCallback(() => {
        const parser = new DOMParser();
        const doc = parser.parseFromString(htmlContent, 'text/html');
        resolve(parseSchedule(doc));
      }, { timeout: 50 });
    });
  }
  
  const parser = new DOMParser();
  const doc = parser.parseFromString(htmlContent, 'text/html');
  
  return parseSchedule(doc);
}

// Предкомпилированные регулярные выражения (вынесены за функцию для переиспользования)
const DATE_REGEX = /(\d{2}\.\d{2}\.\d{4})[\s\n\r<>]*([А-Яа-я]+)[\s\n\r<>]*-[\s\n\r<>]*(\d)/;
const BR_REGEX = /<br\s*\/?>/gi;
const CLASSROOM_REGEX = /ca(\d+)\.htm/;
const CLASSROOM_REGEX2 = /ca([^.]+)\.htm/;

function parseSchedule(doc: Document): DaySchedule[] {
  const schedules: DaySchedule[] = [];
  const table = doc.querySelector('table.inf');
  
  if (!table) {
    console.error('Таблица расписания не найдена');
    return schedules;
  }
  
  // Кэшируем все строки один раз
  const rows = table.querySelectorAll('tr');
  const rowsLength = rows.length;
  
  let currentDay: string | null = null;
  let currentDate: string | null = null;
  let currentWeekNumber = 1;
  let dayItems: ScheduleItem[] = [];
  
  // Оптимизация: используем прямой доступ к NodeList вместо Array.from
  // и кэшируем часто используемые проверки
  // Предкомпилированные проверки для ускорения
  const HEADER_KEYWORDS = ['День', 'Пара'];
  
  for (let i = 0; i < rowsLength; i++) {
    const row = rows[i];
    const cells = row.querySelectorAll('td');
    const cellsLength = cells.length;
    
    if (cellsLength === 0) continue;
    
    // Быстрая проверка на заголовок/разделитель без создания массива
    let isHeaderRow = false;
    let isSeparatorRow = false;
    let dayHeaderCell: Element | null = null;
    
    // Один проход для всех проверок с ранним выходом
    for (let k = 0; k < cellsLength; k++) {
      const cell = cells[k];
      const classList = cell.classList;
      
      // Быстрая проверка на разделитель
      if (classList.contains('hd0')) {
        isSeparatorRow = true;
        break;
      }
      
      // Проверка на заголовок (оптимизировано)
      if (classList.contains('hd') && !isHeaderRow) {
        const text = cell.textContent;
        if (text) {
          // Используем indexOf вместо includes для лучшей производительности
          for (let kw = 0; kw < HEADER_KEYWORDS.length; kw++) {
            const keyword = HEADER_KEYWORDS[kw];
            if (text.indexOf(keyword) >= 0) {
              isHeaderRow = true;
              break;
            }
          }
          if (isHeaderRow) break;
        }
      }
      
      // Ищем ячейку с rowspan (только если еще не нашли)
      if (!dayHeaderCell && cell.hasAttribute('rowspan')) {
        dayHeaderCell = cell;
      }
    }
    
    if (isHeaderRow || isSeparatorRow) continue;
    
    let justStartedNewDay = false;
    
    if (dayHeaderCell) {
      const dateHtml = dayHeaderCell.innerHTML;
      // Используем предкомпилированный regex
      const dateText = dateHtml.replace(BR_REGEX, '\n');
      const dateMatch = dateText.match(DATE_REGEX);
      
      if (dateMatch) {
        if (currentDay) {
          schedules.push({
            day: currentDay,
            date: currentDate || '',
            weekNumber: currentWeekNumber,
            items: dayItems
          });
        }
        
        currentDate = dateMatch[1];
        currentDay = dateMatch[2].trim();
        currentWeekNumber = parseInt(dateMatch[3], 10) || 1;
        dayItems = [];
        justStartedNewDay = true;
      }
    }
    
    const isLessonRow = currentDay && (!dayHeaderCell || justStartedNewDay);
    
    if (isLessonRow && cellsLength >= 1) {
      let lessonNumber: number | null = null;
      let lessonCellIndex = -1;
      
      // Оптимизация: используем прямой доступ к NodeList
      for (let j = 0; j < cellsLength; j++) {
        const cell = cells[j];
        
        if (cell.hasAttribute('rowspan')) continue;
        
        const classList = cell.classList;
        if (classList.contains('ur') || classList.contains('nul')) continue;
        
        if (classList.contains('hd')) {
          const cellText = cell.textContent;
          if (cellText) {
            const trimmed = cellText.trim();
            if (trimmed) {
              const num = parseInt(trimmed, 10);
              if (num >= 1 && num <= 10) {
                lessonNumber = num;
                lessonCellIndex = j;
                break;
              }
            }
          }
        }
      }
      
      if (lessonNumber && lessonNumber >= 1 && lessonNumber <= 10) {
        // Оптимизация: собираем subjectCells напрямую без slice и filter
        // И парсим сразу, чтобы не делать два прохода
        const subjectCells: Element[] = [];
        for (let j = lessonCellIndex + 1; j < cellsLength; j++) {
          const cell = cells[j];
          if (cell.classList.contains('ur')) {
            subjectCells.push(cell);
          }
        }
        
        const subjectCellsLength = subjectCells.length;
        // Оптимизация: предвычисляем subgroup для всех элементов
        const hasMultipleSubgroups = subjectCellsLength > 1;
        
        for (let idx = 0; idx < subjectCellsLength; idx++) {
          const cell = subjectCells[idx];
          const subjectInfo = parseSubjectCell(cell as HTMLElement);
          
          if (subjectInfo.subject) {
            const trimmedSubject = subjectInfo.subject.trim();
            if (trimmedSubject) {
              // Оптимизация: вычисляем subgroup только если нужно
              const subgroup = hasMultipleSubgroups ? idx + 1 : null;
              
              dayItems.push({
                lessonNumber,
                subject: trimmedSubject,
                classroom: subjectInfo.classroom || '',
                teacher: subjectInfo.teacher || '',
                subgroup: subgroup || undefined
              });
            }
          }
        }
      }
    }
  }
  
  if (currentDay) {
    schedules.push({
      day: currentDay,
      date: currentDate || '',
      weekNumber: currentWeekNumber,
      items: dayItems
    });
  }
  
  return schedules;
}

function parseSubjectCell(cell: HTMLElement): { subject: string | null; classroom: string | null; teacher: string | null } {
  const result = {
    subject: null as string | null,
    classroom: null as string | null,
    teacher: null as string | null
  };
  
  // Кэшируем все ссылки один раз
  const allLinks = cell.querySelectorAll('a');
  const allLinksLength = allLinks.length;
  
      // Ищем subject link
      let subjectLink = cell.querySelector('a.z1');
      if (!subjectLink) {
        for (let i = 0; i < allLinksLength; i++) {
          const link = allLinks[i];
          const href = link.getAttribute('href') || '';
          if (href.startsWith('j') && !href.startsWith('cp') && !href.startsWith('ca')) {
            subjectLink = link;
            break;
          }
        }
      }
  
  if (subjectLink) {
    const text = subjectLink.textContent;
    result.subject = text ? text.trim() : null;
  } else {
    const cellText = cell.textContent;
    if (cellText) {
      const trimmed = cellText.trim();
      if (trimmed) {
        // Оптимизация: используем indexOf вместо split для первой строки
        const firstNewline = trimmed.indexOf('\n');
        if (firstNewline > 0) {
          result.subject = trimmed.substring(0, firstNewline).trim();
        } else {
          result.subject = trimmed;
        }
      }
    }
  }
  
  // Ищем classroom link
  let classroomLink = cell.querySelector('a.z2');
  if (!classroomLink) {
    for (let i = 0; i < allLinksLength; i++) {
      const link = allLinks[i];
      const href = link.getAttribute('href') || '';
      if (href.startsWith('ca')) {
        classroomLink = link;
        break;
      }
    }
  }
  
  if (classroomLink) {
    const text = classroomLink.textContent;
    result.classroom = text ? text.trim() : null;
    
    if (!result.classroom) {
      const href = classroomLink.getAttribute('href') || '';
      const match = href.match(CLASSROOM_REGEX);
      if (match) {
        result.classroom = match[1];
      } else {
        const match2 = href.match(CLASSROOM_REGEX2);
        if (match2) {
          const title = classroomLink.getAttribute('title');
          result.classroom = title || match2[1];
        }
      }
    }
  }
  
  if (!result.classroom) {
    const cellText = cell.textContent;
    if (cellText) {
      const lines = cellText.split('\n');
      const linesLength = lines.length;
      for (let i = 1; i < linesLength; i++) {
        const line = lines[i].trim();
        if (line && line !== result.subject && line.length < 50 && (/\d/.test(line) || line.length < 20)) {
          result.classroom = line;
          break;
        }
      }
    }
  }
  
  // Ищем teacher link
  let teacherLink = cell.querySelector('a.z3');
  if (!teacherLink) {
    for (let i = 0; i < allLinksLength; i++) {
      const link = allLinks[i];
      const href = link.getAttribute('href') || '';
      if (href.startsWith('cp')) {
        teacherLink = link;
        break;
      }
    }
  }
  
  if (teacherLink) {
    const text = teacherLink.textContent;
    result.teacher = text ? text.trim() : null;
  }
  
  return result;
}

function fixEncoding(text: string): string {
  if (!text) return text;
  
  try {
    const win1251ToUtf8: { [key: number]: number } = {
      0xC0: 0x0410, 0xC1: 0x0411, 0xC2: 0x0412, 0xC3: 0x0413, 0xC4: 0x0414,
      0xC5: 0x0415, 0xC6: 0x0416, 0xC7: 0x0417, 0xC8: 0x0418, 0xC9: 0x0419,
      0xCA: 0x041A, 0xCB: 0x041B, 0xCC: 0x041C, 0xCD: 0x041D, 0xCE: 0x041E,
      0xCF: 0x041F, 0xD0: 0x0420, 0xD1: 0x0421, 0xD2: 0x0422, 0xD3: 0x0423,
      0xD4: 0x0424, 0xD5: 0x0425, 0xD6: 0x0426, 0xD7: 0x0427, 0xD8: 0x0428,
      0xD9: 0x0429, 0xDA: 0x042A, 0xDB: 0x042B, 0xDC: 0x042C, 0xDD: 0x042D,
      0xDE: 0x042E, 0xDF: 0x042F, 0xE0: 0x0430, 0xE1: 0x0431, 0xE2: 0x0432,
      0xE3: 0x0433, 0xE4: 0x0434, 0xE5: 0x0435, 0xE6: 0x0436, 0xE7: 0x0437,
      0xE8: 0x0438, 0xE9: 0x0439, 0xEA: 0x043A, 0xEB: 0x043B, 0xEC: 0x043C,
      0xED: 0x043D, 0xEE: 0x043E, 0xEF: 0x043F, 0xF0: 0x0440, 0xF1: 0x0441,
      0xF2: 0x0442, 0xF3: 0x0443, 0xF4: 0x0444, 0xF5: 0x0445, 0xF6: 0x0446,
      0xF7: 0x0447, 0xF8: 0x0448, 0xF9: 0x0449, 0xFA: 0x044A, 0xFB: 0x044B,
      0xFC: 0x044C, 0xFD: 0x044D, 0xFE: 0x044E, 0xFF: 0x044F
    };
    
    const hasManyE = (text.match(/Э/g) || []).length > text.length * 0.05;
    const hasCyrillic = /[А-Яа-яЁё]/.test(text);
    const hasGarbled = text.length > 100 && !hasCyrillic;
    
    if (!hasManyE && hasCyrillic && !hasGarbled) {
      return text;
    }
    
    if (hasManyE || hasGarbled) {
      let result = '';
      for (let i = 0; i < text.length; i++) {
        const charCode = text.charCodeAt(i);
        if (charCode >= 0xC0 && charCode <= 0xFF) {
          const utf8Code = win1251ToUtf8[charCode];
          if (utf8Code) {
            result += String.fromCharCode(utf8Code);
          } else {
            result += text[i];
          }
        } else if (charCode < 128) {
          result += text[i];
        } else {
          result += text[i];
        }
      }
      
      if (/[А-Яа-яЁё]/.test(result) && !result.includes('ЭЭЭ')) {
        return result;
      }
    }
    
    return text;
  } catch (e) {
    console.warn('Ошибка исправления кодировки:', e);
    return text;
  }
}

