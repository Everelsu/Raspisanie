// Конфигурация
const CONFIG = {
    BASE_URL_CHTOTIB: 'https://www.chtotib.ru/schedule_gl/',
    BASE_URL_ZABGC: 'https://bbb.zabgc.ru/',
    GROUPS_URL_CHTOTIB: 'https://www.chtotib.ru/schedule_gl/cg.htm',
    GROUPS_URL_ZABGC: 'https://bbb.zabgc.ru/cg.htm',
    CORS_PROXY: 'https://api.allorigins.win/get?url='
};

// Времена пар
const LESSON_TIMES = {
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
};

// Перерывы между парами
const BREAKS = {
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
};

// Обеды
const LUNCHES = {
    chtotib: {
        3: 'Обед: 11:35 - 12:15',
        6: 'Обед: 15:35 - 16:05'
    },
    zabgc: {
        2: 'Обед: 11:50 - 12:30'
    }
};

// Состояние приложения
const app = {
    state: {
        college: localStorage.getItem('college') || 'chtotib',
        group: localStorage.getItem('group') || '',
        groupName: localStorage.getItem('groupName') || '',
        theme: localStorage.getItem('theme') || 'dark',
        showBreaks: localStorage.getItem('showBreaks') !== 'false', // По умолчанию true
        showLunch: localStorage.getItem('showLunch') !== 'false' // По умолчанию true
    },
    
    groups: {
        chtotib: [],
        zabgc: []
    },

    init() {
        this.loadSettings();
        this.applyTheme(this.state.theme);
        this.setupEventListeners();
        this.loadGroups();
        
        // Автозагрузка расписания, если группа сохранена
        if (this.state.group) {
            setTimeout(() => this.loadSchedule(), 500);
        }
    },

    setupEventListeners() {
        // Настройки
        document.getElementById('settingsBtn').addEventListener('click', () => {
            this.openSettings();
        });
        
        document.getElementById('openSettingsBtn').addEventListener('click', () => {
            this.openSettings();
        });

        document.getElementById('closeModal').addEventListener('click', () => {
            this.closeSettings();
        });

        document.getElementById('modalOverlay').addEventListener('click', () => {
            this.closeSettings();
        });

        // Загрузка расписания
        document.getElementById('loadBtn').addEventListener('click', () => {
            this.saveSettings();
            this.loadSchedule();
            this.closeSettings();
        });

        // Смена колледжа
        document.getElementById('collegeSelect').addEventListener('change', (e) => {
            this.state.college = e.target.value;
            this.loadGroups();
        });

        // Быстрые действия
        document.getElementById('refreshBtn').addEventListener('click', () => {
            this.loadSchedule();
        });

        document.getElementById('changeGroupBtn').addEventListener('click', () => {
            this.openSettings();
        });

        // Выбор темы
        document.querySelectorAll('.theme-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const theme = e.currentTarget.dataset.theme;
                this.selectTheme(theme);
            });
        });
    },

    loadSettings() {
        if (document.getElementById('collegeSelect')) {
            document.getElementById('collegeSelect').value = this.state.college;
        }
        if (document.getElementById('groupInput')) {
            document.getElementById('groupInput').value = this.state.group;
        }
        if (document.getElementById('showBreaks')) {
            document.getElementById('showBreaks').checked = this.state.showBreaks;
        }
        if (document.getElementById('showLunch')) {
            document.getElementById('showLunch').checked = this.state.showLunch;
        }
        this.selectTheme(this.state.theme);
    },

    saveSettings() {
        const college = document.getElementById('collegeSelect').value;
        const groupSelect = document.getElementById('groupSelect');
        const groupInput = document.getElementById('groupInput').value.trim();
        const showBreaks = document.getElementById('showBreaks')?.checked !== false;
        const showLunch = document.getElementById('showLunch')?.checked !== false;
        
        let group = '';
        let groupName = '';
        
        if (groupSelect && groupSelect.value) {
            group = groupSelect.value;
            const selectedOption = groupSelect.options[groupSelect.selectedIndex];
            groupName = selectedOption.text;
        } else if (groupInput) {
            group = groupInput;
            groupName = groupInput.replace('.htm', '').toUpperCase();
        }

        this.state.college = college;
        this.state.group = group;
        this.state.groupName = groupName;
        this.state.showBreaks = showBreaks;
        this.state.showLunch = showLunch;

        localStorage.setItem('college', college);
        localStorage.setItem('group', group);
        localStorage.setItem('groupName', groupName);
        localStorage.setItem('theme', this.state.theme);
        localStorage.setItem('showBreaks', showBreaks);
        localStorage.setItem('showLunch', showLunch);
    },

    applyTheme(theme) {
        document.body.setAttribute('data-theme', theme);
        this.state.theme = theme;
        localStorage.setItem('theme', theme);
    },

    selectTheme(theme) {
        document.querySelectorAll('.theme-btn').forEach(btn => {
            btn.classList.remove('active');
            if (btn.dataset.theme === theme) {
                btn.classList.add('active');
            }
        });
        // themeSelect больше нет, используем только кнопки
        this.applyTheme(theme);
    },

    openSettings() {
        document.getElementById('settingsModal').classList.add('active');
        this.loadSettings();
        // Загружаем группы при открытии настроек
        if (this.groups[this.state.college].length === 0) {
            this.loadGroups();
        }
    },

    closeSettings() {
        document.getElementById('settingsModal').classList.remove('active');
    },

    async loadGroups() {
        const college = this.state.college;
        const groupSelect = document.getElementById('groupSelect');
        const groupLoading = document.getElementById('groupLoading');
        
        if (!groupSelect || !groupLoading) return;
        
        groupSelect.disabled = true;
        groupSelect.innerHTML = '<option value="">Загрузка групп...</option>';
        groupLoading.style.display = 'block';

        try {
            // Если группы уже загружены, используем их
            if (this.groups[college] && this.groups[college].length > 0) {
                this.populateGroups(this.groups[college]);
                return;
            }

            // Загружаем список групп
            const groupsUrl = college === 'zabgc' ? CONFIG.GROUPS_URL_ZABGC : CONFIG.GROUPS_URL_CHTOTIB;
            const baseUrl = college === 'zabgc' ? CONFIG.BASE_URL_ZABGC : CONFIG.BASE_URL_CHTOTIB;
            
            let htmlContent = '';
            
            if (college === 'zabgc') {
                // Для ЗабГК используем raw endpoint для получения байтов
                try {
                    const rawProxyUrl = 'https://api.allorigins.win/raw?url=' + encodeURIComponent(groupsUrl);
                    const rawResponse = await fetch(rawProxyUrl);
                    if (rawResponse.ok) {
                        // Получаем данные как ArrayBuffer
                        const arrayBuffer = await rawResponse.arrayBuffer();
                        const bytes = new Uint8Array(arrayBuffer);
                        
                        // Декодируем как Windows-1251
                        try {
                            const decoder = new TextDecoder('windows-1251');
                            htmlContent = decoder.decode(bytes);
                        } catch (e) {
                            // Если TextDecoder не поддерживает Windows-1251, используем ручную конвертацию
                            htmlContent = this.decodeWindows1251(bytes);
                        }
                    } else {
                        throw new Error('Не удалось загрузить raw данные');
                    }
                } catch (e) {
                    console.warn('Ошибка загрузки raw данных, пробуем обычный метод:', e);
                    // Fallback на обычный метод
                    const proxyUrl = CONFIG.CORS_PROXY + encodeURIComponent(groupsUrl);
                    const response = await fetch(proxyUrl);
                    if (!response.ok) throw new Error(`HTTP ${response.status}`);
                    const data = await response.json();
                    htmlContent = this.fixEncoding(data.contents);
                }
            } else {
                // Для ЧТОТиБ используем обычный метод
                const proxyUrl = CONFIG.CORS_PROXY + encodeURIComponent(groupsUrl);
                const response = await fetch(proxyUrl);
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                const data = await response.json();
                htmlContent = data.contents;
            }
            
            const parser = new DOMParser();
            const doc = parser.parseFromString(htmlContent, 'text/html');
            
            // Парсим ссылки на группы из таблицы (как в основном приложении)
            const table = doc.querySelector('table.inf');
            const groups = [];
            
            if (table) {
                // Используем метод из основного приложения
                const rows = table.querySelectorAll('tr');
                
                rows.forEach(row => {
                    // Пропускаем заголовки
                    const headerCells = row.querySelectorAll('td.hd');
                    if (headerCells.length > 0) {
                        const headerText = row.textContent.toLowerCase();
                        if (headerText.includes('№ п.п') || 
                            headerText.includes('днев') || 
                            headerText.includes('пара') ||
                            headerText.includes('группа')) {
                            return;
                        }
                    }
                    
                    // Ищем ссылки: a[href*=cg][href*=htm], a.z0[href*=cg], a[href^=cg]
                    const links = row.querySelectorAll('a[href*="cg"][href*=".htm"], a.z0[href*="cg"], a[href^="cg"]');
                    
                    links.forEach(link => {
                        const href = link.getAttribute('href');
                        const text = link.textContent.trim();
                        
                        if (href && text) {
                            // Извлекаем имя файла
                            let fileName = href;
                            if (href.includes('/')) {
                                fileName = href.substring(href.lastIndexOf('/') + 1);
                            }
                            fileName = fileName.split('?')[0]; // Убираем query параметры
                            
                            // Проверяем, что это файл группы
                            if (fileName.startsWith('cg') && fileName.endsWith('.htm')) {
                                // Проверяем на дубликаты
                                if (!groups.find(g => g.file === fileName)) {
                                    groups.push({
                                        file: fileName,
                                        name: text
                                    });
                                }
                            }
                        }
                    });
                });
            } else {
                // Fallback: ищем во всех таблицах
                const allTables = doc.querySelectorAll('table');
                allTables.forEach(table => {
                    const rows = table.querySelectorAll('tr');
                    rows.forEach(row => {
                        const links = row.querySelectorAll('a[href*="cg"][href*=".htm"], a.z0[href*="cg"]');
                        links.forEach(link => {
                            const href = link.getAttribute('href');
                            const text = link.textContent.trim();
                            if (href && text) {
                                let fileName = href;
                                if (href.includes('/')) {
                                    fileName = href.substring(href.lastIndexOf('/') + 1);
                                }
                                fileName = fileName.split('?')[0];
                                if (fileName.startsWith('cg') && fileName.endsWith('.htm')) {
                                    if (!groups.find(g => g.file === fileName)) {
                                        groups.push({
                                            file: fileName,
                                            name: text
                                        });
                                    }
                                }
                            }
                        });
                    });
                });
            }

            this.groups[college] = groups;
            this.populateGroups(groups);
            
        } catch (err) {
            console.error('Ошибка загрузки групп:', err);
            if (groupSelect) {
                groupSelect.innerHTML = '<option value="">Ошибка загрузки. Введите файл вручную.</option>';
            }
        } finally {
            if (groupSelect) {
                groupSelect.disabled = false;
            }
            if (groupLoading) {
                groupLoading.style.display = 'none';
            }
        }
    },

    populateGroups(groups) {
        const groupSelect = document.getElementById('groupSelect');
        if (!groupSelect) return;
        
        groupSelect.innerHTML = '<option value="">Выберите группу</option>';
        
        if (groups.length === 0) {
            groupSelect.innerHTML = '<option value="">Группы не найдены</option>';
            return;
        }
        
        groups.forEach(group => {
            const option = document.createElement('option');
            option.value = group.file;
            option.textContent = group.name;
            if (group.file === this.state.group) {
                option.selected = true;
            }
            groupSelect.appendChild(option);
        });
        
        // Если группа сохранена, но не в списке, показываем её в input
        if (this.state.group && !groups.find(g => g.file === this.state.group)) {
            const groupInput = document.getElementById('groupInput');
            if (groupInput) {
                groupInput.value = this.state.group;
            }
        }
    },

    async loadSchedule() {
        const loading = document.getElementById('loading');
        const error = document.getElementById('error');
        const emptyState = document.getElementById('emptyState');
        const scheduleSection = document.getElementById('scheduleSection');
        const quickActions = document.getElementById('quickActions');
        const currentGroup = document.getElementById('currentGroup');

        loading.style.display = 'block';
        error.style.display = 'none';
        emptyState.style.display = 'none';
        scheduleSection.style.display = 'none';
        quickActions.style.display = 'none';
        currentGroup.style.display = 'none';

        try {
            if (!this.state.group) {
                throw new Error('Группа не выбрана');
            }

            const baseUrl = this.state.college === 'zabgc' ? CONFIG.BASE_URL_ZABGC : CONFIG.BASE_URL_CHTOTIB;
            const scheduleUrl = baseUrl + this.state.group;

            let htmlContent = '';
            
            if (this.state.college === 'zabgc') {
                // Для ЗабГК используем raw endpoint для получения байтов
                try {
                    const rawProxyUrl = 'https://api.allorigins.win/raw?url=' + encodeURIComponent(scheduleUrl);
                    const rawResponse = await fetch(rawProxyUrl);
                    if (rawResponse.ok) {
                        // Получаем данные как ArrayBuffer
                        const arrayBuffer = await rawResponse.arrayBuffer();
                        const bytes = new Uint8Array(arrayBuffer);
                        
                        // Декодируем как Windows-1251
                        try {
                            const decoder = new TextDecoder('windows-1251');
                            htmlContent = decoder.decode(bytes);
                        } catch (e) {
                            // Если TextDecoder не поддерживает Windows-1251, используем ручную конвертацию
                            htmlContent = this.decodeWindows1251(bytes);
                        }
                    } else {
                        throw new Error('Не удалось загрузить raw данные');
                    }
                } catch (e) {
                    console.warn('Ошибка загрузки raw данных, пробуем обычный метод:', e);
                    // Fallback на обычный метод
                    const proxyUrl = CONFIG.CORS_PROXY + encodeURIComponent(scheduleUrl);
                    const response = await fetch(proxyUrl);
                    if (!response.ok) {
                        throw new Error(`HTTP ${response.status}`);
                    }
                    const data = await response.json();
                    if (!data.contents) {
                        throw new Error('Пустой ответ от сервера');
                    }
                    htmlContent = this.fixEncoding(data.contents);
                }
            } else {
                // Для ЧТОТиБ используем обычный метод
                const proxyUrl = CONFIG.CORS_PROXY + encodeURIComponent(scheduleUrl);
                const response = await fetch(proxyUrl);
                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}`);
                }
                const data = await response.json();
                if (!data.contents) {
                    throw new Error('Пустой ответ от сервера');
                }
                htmlContent = data.contents;
            }
            
            const parser = new DOMParser();
            const doc = parser.parseFromString(htmlContent, 'text/html');
            
            const schedules = this.parseSchedule(doc);
            
            if (schedules.length === 0) {
                throw new Error('Расписание не найдено. Проверьте правильность файла группы.');
            }

            this.displaySchedule(schedules);
            this.showCurrentGroup();
            
        } catch (err) {
            console.error('Ошибка загрузки:', err);
            document.getElementById('errorText').textContent = 
                `Ошибка загрузки расписания: ${err.message}`;
            error.style.display = 'block';
        } finally {
            loading.style.display = 'none';
        }
    },

    showCurrentGroup() {
        const currentGroup = document.getElementById('currentGroup');
        const currentGroupName = document.getElementById('currentGroupName');
        const quickActions = document.getElementById('quickActions');
        
        if (this.state.groupName) {
            currentGroupName.textContent = this.state.groupName;
            currentGroup.style.display = 'block';
            quickActions.style.display = 'flex';
        }
    },

    parseSchedule(doc) {
        const schedules = [];
        const table = doc.querySelector('table.inf');
        
        if (!table) {
            console.error('Таблица расписания не найдена');
            return schedules;
        }

        const rows = Array.from(table.querySelectorAll('tr'));
        let currentDay = null;
        let currentDate = null;
        let currentWeekNumber = 1;
        let dayItems = [];

        rows.forEach((row) => {
            const cells = Array.from(row.querySelectorAll('td'));
            
            if (cells.length === 0) return;

            // Пропускаем заголовки
            const isHeaderRow = cells.some(cell => 
                cell.classList.contains('hd') && 
                (cell.textContent.includes('День') || cell.textContent.includes('Пара'))
            );
            if (isHeaderRow) return;

            // Пропускаем разделители
            const isSeparatorRow = cells.some(cell => cell.classList.contains('hd0'));
            if (isSeparatorRow) return;

            // Ищем ячейку с rowspan - это заголовок дня
            const dayHeaderCell = cells.find(cell => cell.hasAttribute('rowspan'));
            
            let justStartedNewDay = false;

            if (dayHeaderCell) {
                const dateHtml = dayHeaderCell.innerHTML;
                const dateText = dateHtml.replace(/<br\s*\/?>/gi, '\n');
                
                const dateMatch = dateText.match(/(\d{2}\.\d{2}\.\d{4})[\s\n\r<>]*([А-Яа-я]+)[\s\n\r<>]*-[\s\n\r<>]*(\d)/);
                
                if (dateMatch) {
                    // Добавляем предыдущий день (даже если пустой)
                    if (currentDay) {
                        schedules.push({
                            day: currentDay,
                            date: currentDate || '',
                            weekNumber: currentWeekNumber,
                            items: [...dayItems]
                        });
                    }

                    currentDate = dateMatch[1];
                    currentDay = dateMatch[2].trim();
                    currentWeekNumber = parseInt(dateMatch[3]) || 1;
                    dayItems = [];
                    justStartedNewDay = true;
                }
            }

            // Это строка с парой, если есть текущий день и (нет заголовка дня или только что начался новый день)
            const isLessonRow = currentDay && (!dayHeaderCell || justStartedNewDay);
            
            if (isLessonRow && cells.length >= 1) {
                // Ищем ячейку с номером пары - она имеет класс "hd" и содержит число 1-10
                let lessonNumber = null;
                let lessonCellIndex = -1;

                // Проверяем ячейки с начала - первая может быть днём (если rowspan ещё присутствует),
                // вторая может быть номером пары, или первая может быть номером пары, если день отсутствует из-за rowspan
                for (let i = 0; i < cells.length; i++) {
                    const cell = cells[i];
                    
                    // Пропускаем ячейку заголовка дня (имеет атрибут rowspan) - это не номер пары
                    if (cell.hasAttribute('rowspan')) {
                        continue;
                    }
                    
                    // Пропускаем ячейки, которые содержат предметы (классы "ur" или "nul") - они идут после номера пары
                    if (cell.classList.contains('ur') || cell.classList.contains('nul')) {
                        continue;
                    }
                    
                    // Ищем ячейку с классом "hd", которая содержит номер пары
                    if (cell.classList.contains('hd')) {
                        const cellText = cell.textContent.trim();
                        // Пропускаем пустые ячейки
                        if (!cellText) {
                            continue;
                        }
                        const num = parseInt(cellText);
                        // Принимаем числа от 1 до 10 (в некоторых расписаниях больше 8 пар)
                        if (num >= 1 && num <= 10) {
                            lessonNumber = num;
                            lessonCellIndex = i;
                            break;
                        }
                    }
                }

                if (lessonNumber && lessonNumber >= 1 && lessonNumber <= 10) {
                    // Ячейки с предметами идут после ячейки с номером пары
                    // Получаем все ячейки после ячейки с номером пары - нужно обработать ВСЕ ячейки "ur" в ЭТОЙ строке
                    const allCellsAfterLesson = cells.slice(lessonCellIndex + 1);
                    
                    // Находим все ячейки с классом "ur" (имеют занятие) в ЭТОЙ строке
                    // ВАЖНО: Каждая ячейка "ur", даже если идентична другой, должна создать отдельный ScheduleItem
                    // Это обрабатывает случаи, когда есть несколько одинаковых предметов (подгруппы, разные аудитории и т.д.)
                    const subjectCells = allCellsAfterLesson.filter(cell => 
                        cell.classList.contains('ur')
                    );

                    // Обрабатываем каждую ячейку "ur" - даже если они содержат один и тот же предмет
                    // Каждая ячейка должна создать отдельный ScheduleItem, независимо от содержимого
                    subjectCells.forEach((cell, index) => {
                        const subjectInfo = this.parseSubjectCell(cell);
                        
                        if (subjectInfo.subject && subjectInfo.subject.trim()) {
                            // Определяем подгруппу: только если есть несколько ячеек с занятиями
                            const subgroup = subjectCells.length > 1 ? index + 1 : null;
                            
                            dayItems.push({
                                lessonNumber,
                                subject: subjectInfo.subject,
                                classroom: subjectInfo.classroom || '',
                                teacher: subjectInfo.teacher || '',
                                subgroup: subgroup
                            });
                        }
                    });
                }
            }
        });

        // Добавляем последний день (даже если пустой)
        if (currentDay) {
            schedules.push({
                day: currentDay,
                date: currentDate || '',
                weekNumber: currentWeekNumber,
                items: [...dayItems]
            });
        }

        return schedules;
    },

    parseSubjectCell(cell) {
        const result = {
            subject: null,
            classroom: null,
            teacher: null
        };

        // Метод из основного приложения
        const allLinks = cell.querySelectorAll('a');
        
        // Находим ссылку на предмет (class z1 или href начинается с "j")
        const subjectLink = cell.querySelector('a.z1') || 
            Array.from(allLinks).find(link => {
                const href = link.getAttribute('href') || '';
                return href.startsWith('j') && !href.startsWith('cp') && !href.startsWith('ca');
            });
        
        if (subjectLink) {
            result.subject = subjectLink.textContent.trim();
        } else {
            // Fallback: берем первую строку текста
            const cellText = cell.textContent.trim();
            const lines = cellText.split('\n').filter(l => l.trim());
            if (lines.length > 0) {
                result.subject = lines[0].trim();
            }
        }

        // Находим ссылку на аудиторию (class z2 или href начинается с "ca")
        const classroomLink = cell.querySelector('a.z2') || 
            Array.from(allLinks).find(link => {
                const href = link.getAttribute('href') || '';
                return href.startsWith('ca');
            });
        
        if (classroomLink) {
            result.classroom = classroomLink.textContent.trim();
            
            // Если текст ссылки пустой, пробуем извлечь из href
            if (!result.classroom) {
                const href = classroomLink.getAttribute('href') || '';
                const match = href.match(/ca(\d+)\.htm/);
                if (match) {
                    result.classroom = match[1];
                } else {
                    const match2 = href.match(/ca([^.]+)\.htm/);
                    if (match2) {
                        const title = classroomLink.getAttribute('title');
                        result.classroom = title || match2[1];
                    }
                }
            }
        }
        
        // Если аудитория не найдена, пробуем найти в тексте
        if (!result.classroom) {
            const cellText = cell.textContent;
            const lines = cellText.split('\n').map(l => l.trim()).filter(l => l);
            if (lines.length > 1) {
                // Пропускаем предмет, ищем аудиторию
                const possibleClassroom = lines.find(line => 
                    line !== result.subject && 
                    line.length < 50 &&
                    (line.match(/\d/) || line.length < 20)
                );
                if (possibleClassroom) {
                    result.classroom = possibleClassroom;
                }
            }
        }

        // Находим ссылку на преподавателя (class z3 или href начинается с "cp")
        const teacherLink = cell.querySelector('a.z3') || 
            Array.from(allLinks).find(link => {
                const href = link.getAttribute('href') || '';
                return href.startsWith('cp');
            });
        
        if (teacherLink) {
            result.teacher = teacherLink.textContent.trim();
        }

        return result;
    },

    displaySchedule(schedules) {
        const container = document.getElementById('scheduleContainer');
        container.innerHTML = '';

        const lessonTimes = LESSON_TIMES[this.state.college];

        schedules.forEach((daySchedule) => {
            const dayCard = document.createElement('div');
            dayCard.className = 'day-card';

            const dayHeader = document.createElement('div');
            dayHeader.className = 'day-header';

            const dayName = document.createElement('div');
            dayName.className = 'day-name';
            dayName.textContent = this.formatDayName(daySchedule.day);

            const dateText = document.createElement('div');
            dateText.className = 'date-text';
            if (daySchedule.date) {
                const date = new Date(daySchedule.date.split('.').reverse().join('-'));
                dateText.textContent = date.toLocaleDateString('ru-RU', { 
                    day: 'numeric', 
                    month: 'long',
                    weekday: 'long'
                });
            }

            dayHeader.appendChild(dayName);
            dayHeader.appendChild(dateText);
            dayCard.appendChild(dayHeader);

            // Проверяем, сегодня ли это
            const isToday = this.isToday(daySchedule.date);
            if (isToday) {
                dayCard.classList.add('day-card-today');
            }

            if (daySchedule.items.length === 0) {
                const emptyDay = document.createElement('div');
                emptyDay.className = 'empty-day';
                emptyDay.textContent = 'Нет занятий';
                dayCard.appendChild(emptyDay);
            } else {
                // Группируем по номерам пар
                const groupedByLesson = {};
                daySchedule.items.forEach(item => {
                    if (!groupedByLesson[item.lessonNumber]) {
                        groupedByLesson[item.lessonNumber] = [];
                    }
                    groupedByLesson[item.lessonNumber].push(item);
                });

                const sortedLessonNumbers = Object.keys(groupedByLesson).map(Number).sort((a, b) => a - b);
                let previousLessonNumber = null;

                sortedLessonNumbers.forEach(lessonNum => {
                    const items = groupedByLesson[lessonNum];

                    // Добавляем перерыв перед парой (если включено)
                    if (previousLessonNumber !== null && this.state.showBreaks) {
                        const breakKey = `${previousLessonNumber}-${lessonNum}`;
                        const breakText = BREAKS[this.state.college]?.[breakKey];
                        if (breakText) {
                            const breakItem = document.createElement('div');
                            breakItem.className = 'break-item';
                            breakItem.textContent = breakText;
                            dayCard.appendChild(breakItem);
                        }
                    }

                    // Отображаем пары
                    items.forEach(item => {
                        const lessonItem = document.createElement('div');
                        lessonItem.className = 'lesson-item';

                        const lessonNumber = document.createElement('div');
                        lessonNumber.className = 'lesson-number';
                        lessonNumber.textContent = item.lessonNumber;

                        const lessonContent = document.createElement('div');
                        lessonContent.className = 'lesson-content';

                        if (item.subject) {
                            const subject = document.createElement('div');
                            subject.className = 'lesson-subject';
                            subject.textContent = item.subject;
                            lessonContent.appendChild(subject);
                        }

                        const details = [];
                        if (item.classroom) details.push(`Аудитория: ${item.classroom}`);
                        if (item.teacher) details.push(item.teacher);
                        if (item.subgroup) details.push(`Подгруппа ${item.subgroup}`);
                        
                        // Время пары добавляем в детали
                        const time = lessonTimes[item.lessonNumber];
                        if (time) {
                            details.push(`${time.start} - ${time.end}`);
                        }

                        if (details.length > 0) {
                            const detailsEl = document.createElement('div');
                            detailsEl.className = 'lesson-details';
                            detailsEl.textContent = details.join(' • ');
                            lessonContent.appendChild(detailsEl);
                        }

                        lessonItem.appendChild(lessonNumber);
                        lessonItem.appendChild(lessonContent);
                        dayCard.appendChild(lessonItem);
                    });

                    // Добавляем обед ПОСЛЕ текущей пары (если включено)
                    if (this.state.showLunch) {
                        const lunchText = LUNCHES[this.state.college]?.[lessonNum];
                        if (lunchText) {
                            const lunchItem = document.createElement('div');
                            lunchItem.className = 'lunch-item';
                            lunchItem.textContent = lunchText;
                            dayCard.appendChild(lunchItem);
                        }
                    }

                    previousLessonNumber = lessonNum;
                });

            }

            container.appendChild(dayCard);
        });

        document.getElementById('emptyState').style.display = 'none';
        scheduleSection.style.display = 'block';
    },

    formatDayName(day) {
        const dayMap = {
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
    },

    isToday(dateString) {
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
    },

    // Декодирование Windows-1251 из байтов
    decodeWindows1251(bytes) {
        const win1251ToUtf8 = {
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
    },

    // Исправление кодировки для ЗабГК (Windows-1251 -> UTF-8)
    fixEncoding(text) {
        if (!text) return text;
        
        try {
            // Таблица конвертации Windows-1251 в UTF-8 для кириллицы
            const win1251ToUtf8 = {
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
            
            // Проверяем, есть ли проблемы с кодировкой (много символов Э или кракозябры)
            const hasManyE = (text.match(/Э/g) || []).length > text.length * 0.05;
            const hasCyrillic = /[А-Яа-яЁё]/.test(text);
            const hasGarbled = /[]/.test(text) || (text.length > 100 && !hasCyrillic);
            
            // Если кодировка уже правильная, возвращаем как есть
            if (!hasManyE && hasCyrillic && !hasGarbled) {
                return text;
            }
            
            // Если много символов Э или кракозябры, пробуем исправить
            if (hasManyE || hasGarbled) {
                let result = '';
                for (let i = 0; i < text.length; i++) {
                    const charCode = text.charCodeAt(i);
                    // Если символ в диапазоне Windows-1251 кириллицы (0xC0-0xFF)
                    if (charCode >= 0xC0 && charCode <= 0xFF) {
                        const utf8Code = win1251ToUtf8[charCode];
                        if (utf8Code) {
                            result += String.fromCharCode(utf8Code);
                        } else {
                            result += text[i];
                        }
                    } else if (charCode < 128) {
                        // ASCII символы
                        result += text[i];
                    } else {
                        // Другие символы - оставляем как есть
                        result += text[i];
                    }
                }
                
                // Проверяем результат
                if (/[А-Яа-яЁё]/.test(result) && !result.includes('ЭЭЭ')) {
                    return result;
                }
            }
            
            // Пробуем использовать TextDecoder, если поддерживается
            try {
                // Конвертируем строку в байты (предполагаем, что это байты Windows-1251)
                const bytes = new Uint8Array(text.length);
                for (let i = 0; i < text.length; i++) {
                    const charCode = text.charCodeAt(i);
                    if (charCode < 256) {
                        bytes[i] = charCode;
                    } else {
                        bytes[i] = charCode & 0xFF;
                    }
                }
                
                // Пробуем декодировать как Windows-1251
                const decoder = new TextDecoder('windows-1251');
                const decoded = decoder.decode(bytes);
                
                // Проверяем результат
                if (/[А-Яа-яЁё]/.test(decoded) && !decoded.includes('ЭЭЭ')) {
                    return decoded;
                }
            } catch (e) {
                // TextDecoder не поддерживает Windows-1251
            }
            
            // Если ничего не помогло, возвращаем оригинальный текст
            return text;
            
        } catch (e) {
            console.warn('Ошибка исправления кодировки:', e);
            return text;
        }
    }
};

// Инициализация
document.addEventListener('DOMContentLoaded', () => {
    app.init();
});

// Экспорт для глобального использования
window.app = app;
window.loadSchedule = () => app.loadSchedule();
