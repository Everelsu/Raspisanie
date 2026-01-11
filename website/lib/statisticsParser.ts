import { CONFIG, College } from './config';
import { CONFIG as SCHEDULE_CONFIG } from './config';

// Копируем функцию fetchWithProxy, так как она не экспортирована
async function fetchWithProxy(url: string, useRaw = false): Promise<string> {
  const proxyUrl = useRaw 
    ? SCHEDULE_CONFIG.CORS_PROXY_RAW + encodeURIComponent(url)
    : SCHEDULE_CONFIG.CORS_PROXY + encodeURIComponent(url);
  
  const response = await fetch(proxyUrl);
  
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  
  if (useRaw) {
    const arrayBuffer = await response.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    return decodeWindows1251(bytes);
  } else {
    const data = await response.json();
    return data.contents || '';
  }
}

function decodeWindows1251(bytes: Uint8Array): string {
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
  
  let result = '';
  for (let i = 0; i < bytes.length; i++) {
    const byte = bytes[i];
    if (byte >= 0xC0 && byte <= 0xFF) {
      const utf8Code = win1251ToUtf8[byte];
      if (utf8Code) {
        result += String.fromCharCode(utf8Code);
      } else {
        result += String.fromCharCode(byte);
      }
    } else if (byte < 128) {
      result += String.fromCharCode(byte);
    } else {
      result += String.fromCharCode(byte);
    }
  }
  return result;
}

export interface StatisticsData {
  disciplines: Array<{
    name: string;
    teacher: string;
    type: string;
    totalHours: number;
    planHours: number;
    factHours: number;
    remainingHours: number;
    plan2Weeks: number;
    fact2Weeks: number;
    completionDate: string;
    percentage: number;
  }>;
  totalDisciplines: number;
  totalHours: number;
  totalPlanHours: number;
  totalFactHours: number;
}

export async function loadStatistics(groupFile: string, college: College): Promise<StatisticsData> {
  // Для ЧТОТиБ страница итогов имеет формат vg{number}.htm
  // Нужно извлечь номер группы из файла расписания
  // Например, cg50.htm -> vg50.htm
  let statisticsFile = '';
  
  if (groupFile.startsWith('cg')) {
    // Извлекаем номер из cg50.htm -> vg50.htm
    const match = groupFile.match(/cg(\d+)\.htm/);
    if (match) {
      statisticsFile = `vg${match[1]}.htm`;
    } else {
      // Пробуем найти номер в любом месте
      const numberMatch = groupFile.match(/(\d+)\.htm/);
      if (numberMatch) {
        statisticsFile = `vg${numberMatch[1]}.htm`;
      } else {
        throw new Error('Не удалось определить номер группы для статистики');
      }
    }
  } else if (groupFile.startsWith('vg')) {
    statisticsFile = groupFile;
  } else {
    // Пробуем извлечь номер из любого формата
    const numberMatch = groupFile.match(/(\d+)\.htm/);
    if (numberMatch) {
      statisticsFile = `vg${numberMatch[1]}.htm`;
    } else {
      throw new Error('Не удалось определить файл статистики');
    }
  }
  
  const baseUrl = college === 'zabgc' ? CONFIG.BASE_URL_ZABGC : CONFIG.BASE_URL_CHTOTIB;
  const statisticsUrl = baseUrl + statisticsFile;
  
  let htmlContent = '';
  
  if (college === 'zabgc') {
    try {
      htmlContent = await fetchWithProxy(statisticsUrl, true);
    } catch (e) {
      console.warn('Ошибка загрузки raw данных, пробуем обычный метод:', e);
      htmlContent = await fetchWithProxy(statisticsUrl, false);
    }
  } else {
    htmlContent = await fetchWithProxy(statisticsUrl, false);
  }
  
  return parseStatistics(htmlContent);
}

function parseStatistics(html: string): StatisticsData {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, 'text/html');
  
  const table = doc.querySelector('table.inf');
  if (!table) {
    return {
      disciplines: [],
      totalDisciplines: 0,
      totalHours: 0,
      totalPlanHours: 0,
      totalFactHours: 0,
    };
  }
  
  const rows = Array.from(table.querySelectorAll('tr'));
  const disciplines: StatisticsData['disciplines'] = [];
  
  rows.forEach((row, index) => {
    // Пропускаем заголовок (первая строка с заголовками колонок)
    const headerCells = row.querySelectorAll('td.hd, th');
    if (headerCells.length > 0) {
      const headerText = row.textContent?.toLowerCase() || '';
      if (headerText.includes('№ п.п') || headerText.includes('преподаватель') || headerText.includes('дисциплина')) {
        return;
      }
    }
    
    const cells = Array.from(row.querySelectorAll('td'));
    if (cells.length < 10) return;
    
    try {
      // Парсим данные из таблицы согласно структуре:
      // 0 - № п.п
      // 1 - Преподаватель
      // 2 - Группа
      // 3 - П/г
      // 4 - Дисциплина
      // 5 - Тип занятия
      // 6 - Всего, час.
      // 7 - План, час.
      // 8 - Факт, час.
      // 9 - Остаток, час.
      // 10 - План в 2 нед., час.
      // 11 - Факт в 2 нед., час.
      // 12 - Окончание
      // 13 - Процент выполнения
      
      const teacher = cells[1]?.textContent?.trim() || '';
      const disciplineLink = cells[4]?.querySelector('a');
      const disciplineName = disciplineLink?.textContent?.trim() || cells[4]?.textContent?.trim() || '';
      const type = cells[5]?.textContent?.trim() || '';
      
      // Парсим числа, убирая все нечисловые символы
      const parseNumber = (text: string): number => {
        const cleaned = text.replace(/[^\d.,]/g, '').replace(',', '.');
        return parseFloat(cleaned) || 0;
      };
      
      const totalHours = Math.round(parseNumber(cells[6]?.textContent?.trim() || '0'));
      const planHours = Math.round(parseNumber(cells[7]?.textContent?.trim() || '0'));
      const factHours = Math.round(parseNumber(cells[8]?.textContent?.trim() || '0'));
      const remainingHours = Math.round(parseNumber(cells[9]?.textContent?.trim() || '0'));
      const plan2Weeks = parseNumber(cells[10]?.textContent?.trim() || '0');
      const fact2Weeks = parseNumber(cells[11]?.textContent?.trim() || '0');
      const completionDate = cells[12]?.textContent?.trim() || '';
      
      // Парсим процент выполнения
      let percentage = 0;
      const percentageCell = cells[13];
      if (percentageCell) {
        const img = percentageCell.querySelector('img');
        if (img) {
          const src = img.getAttribute('src') || '';
          const match = src.match(/graf(\d+)\.gif/);
          if (match) {
            percentage = parseInt(match[1]) || 0;
          }
        } else {
          const text = percentageCell.textContent?.trim() || '';
          const percentMatch = text.match(/(\d+)%/);
          if (percentMatch) {
            percentage = parseInt(percentMatch[1]) || 0;
          } else if (totalHours > 0) {
            // Вычисляем процент, если не указан
            percentage = Math.round((factHours / totalHours) * 100);
          }
        }
      } else if (totalHours > 0) {
        // Вычисляем процент, если ячейка отсутствует
        percentage = Math.round((factHours / totalHours) * 100);
      }
      
      if (disciplineName && disciplineName.length > 0) {
        disciplines.push({
          name: disciplineName,
          teacher: teacher || 'Не указан',
          type: type || 'Лекция',
          totalHours,
          planHours,
          factHours,
          remainingHours: remainingHours || (totalHours - factHours),
          plan2Weeks,
          fact2Weeks,
          completionDate,
          percentage: Math.min(percentage, 100),
        });
      }
    } catch (e) {
      console.warn('Ошибка парсинга строки статистики:', e, row.textContent);
    }
  });
  
  const totalHours = disciplines.reduce((sum, d) => sum + d.totalHours, 0);
  const totalPlanHours = disciplines.reduce((sum, d) => sum + d.planHours, 0);
  const totalFactHours = disciplines.reduce((sum, d) => sum + d.factHours, 0);
  
  return {
    disciplines,
    totalDisciplines: disciplines.length,
    totalHours,
    totalPlanHours,
    totalFactHours,
  };
}

