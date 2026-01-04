export function formatDayName(day: string): string {
  const dayMap: { [key: string]: string } = {
    'пн': 'Понедельник',
    'вт': 'Вторник',
    'ср': 'Среда',
    'чт': 'Четверг',
    'пт': 'Пятница',
    'сб': 'Суббота',
    'вс': 'Воскресенье',
    'понедельник': 'Понедельник',
    'вторник': 'Вторник',
    'среда': 'Среда',
    'четверг': 'Четверг',
    'пятница': 'Пятница',
    'суббота': 'Суббота',
    'воскресенье': 'Воскресенье'
  };
  
  const lower = day.toLowerCase().trim();
  for (const [key, value] of Object.entries(dayMap)) {
    if (lower.includes(key)) {
      return value;
    }
  }
  return day;
}

export function isToday(dateString: string): boolean {
  if (!dateString) return false;
  
  try {
    const today = new Date();
    const scheduleDate = new Date(dateString.split('.').reverse().join('-'));
    
    return today.getDate() === scheduleDate.getDate() &&
           today.getMonth() === scheduleDate.getMonth() &&
           today.getFullYear() === scheduleDate.getFullYear();
  } catch (e) {
    return false;
  }
}

export function formatDate(dateString: string): string {
  if (!dateString) return '';
  
  try {
    const date = new Date(dateString.split('.').reverse().join('-'));
    return date.toLocaleDateString('ru-RU', { 
      day: 'numeric', 
      month: 'long',
      weekday: 'long'
    });
  } catch (e) {
    return dateString;
  }
}



