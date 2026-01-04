'use client';

import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { DaySchedule, College, Theme } from '@/lib/types';
import { loadSchedule } from '@/lib/scheduleParser';
import { getStoredState, saveState } from '@/lib/storage';
import { getCachedSchedule, setCachedSchedule } from '@/lib/cache';
import { retry } from '@/lib/retry';
import { isOnline, addOnlineListener, addOfflineListener } from '@/lib/network';
import Schedule from '@/components/Schedule';
import Settings from '@/components/Settings';
import Statistics from '@/components/Statistics';
import SkeletonLoader from '@/components/SkeletonLoader';
import { ErrorBoundary } from '@/components/ErrorBoundary';

export default function Home() {
  const [state, setState] = useState({
    college: 'chtotib' as College,
    group: '',
    groupName: '',
    theme: 'dark' as Theme,
    showBreaks: true,
    showLunch: true,
  });
  
  const [schedules, setSchedules] = useState<DaySchedule[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [statisticsOpen, setStatisticsOpen] = useState(false);
  const [isOffline, setIsOffline] = useState(false);
  const stateRef = useRef(state);
  
  useEffect(() => {
    stateRef.current = state;
  }, [state]);
  
  useEffect(() => {
    const stored = getStoredState();
    const newState = {
      college: (stored.college as College) || 'chtotib',
      group: stored.group || '',
      groupName: stored.groupName || '',
      theme: (stored.theme as Theme) || 'dark',
      showBreaks: stored.showBreaks !== false,
      showLunch: stored.showLunch !== false,
    };
    setState(newState);
    applyTheme(newState.theme);
    
    setIsOffline(!isOnline());
    
    if (newState.group) {
      loadScheduleData(newState.group, newState.college);
    }
    
    // Слушаем изменения онлайн/оффлайн статуса
    const removeOnlineListener = addOnlineListener(() => {
      setIsOffline(false);
      const currentState = stateRef.current;
      if (currentState.group) {
        loadScheduleData(currentState.group, currentState.college);
      }
    });
    
    const removeOfflineListener = addOfflineListener(() => {
      setIsOffline(true);
      setError('Нет подключения к интернету. Показано кэшированное расписание.');
    });
    
    return () => {
      removeOnlineListener();
      removeOfflineListener();
    };
  }, []);
  
  const applyTheme = useCallback((theme: Theme) => {
    if (typeof document !== 'undefined') {
      document.body.setAttribute('data-theme', theme);
    }
  }, []);
  
  const loadScheduleData = useCallback(async (group: string, college: College, useCache = true) => {
    if (!group) {
      setSchedules([]);
      return;
    }
    
    // Проверяем онлайн статус
    if (!isOnline() && !useCache) {
      const cached = getCachedSchedule(group, college);
      if (cached && cached.length > 0) {
        setSchedules(cached);
        setError('Нет подключения к интернету. Показано кэшированное расписание.');
      } else {
        setError('Нет подключения к интернету и нет кэшированного расписания.');
      }
      return;
    }
    
    // Проверяем кэш синхронно для мгновенного отображения
    if (useCache) {
      const cached = getCachedSchedule(group, college);
      if (cached && cached.length > 0) {
        // Показываем кэш сразу (синхронно для мгновенного отображения)
        setSchedules(cached);
        setError(null);
        
        // Загружаем свежие данные в фоне только если онлайн
        if (isOnline()) {
          // Используем setTimeout для асинхронной загрузки в фоне
          setTimeout(() => {
            loadScheduleData(group, college, false).catch(() => {
              // Игнорируем ошибки фоновой загрузки
            });
          }, 0);
        }
        return;
      }
    }
    
    setLoading(true);
    setError(null);
    
    try {
      // Используем Promise.race для таймаута и параллельной загрузки
      const loadPromise = retry(
        () => loadSchedule(group, college),
        { maxRetries: 3, delay: 300, backoff: 1.5 } // Еще уменьшили задержку для быстрой загрузки
      );
      
      // Добавляем таймаут для загрузки (уменьшили до 15 секунд)
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Превышено время ожидания')), 15000);
      });
      
      const data = await Promise.race([loadPromise, timeoutPromise]);
      
      if (data && data.length > 0) {
        // Обновляем UI сразу (приоритет)
        setSchedules(data);
        setError(null);
        
        // Сохраняем в кэш асинхронно в следующем тике, чтобы не блокировать UI
        // Используем requestIdleCallback для еще большей оптимизации
        if (typeof window !== 'undefined' && 'requestIdleCallback' in window) {
          (window as any).requestIdleCallback(() => {
            setCachedSchedule(group, college, data);
          }, { timeout: 500 });
        } else {
          Promise.resolve().then(() => {
            setCachedSchedule(group, college, data);
          });
        }
        
        // Предзагружаем данные для следующей группы в фоне
        preloadNextGroup(group, college);
      } else {
        throw new Error('Расписание пустое');
      }
    } catch (err) {
      console.error('Ошибка загрузки:', err);
      const errorMessage = err instanceof Error ? err.message : 'Неизвестная ошибка';
      setError(`Ошибка загрузки расписания: ${errorMessage}`);
      
      // Пробуем показать кэш даже если он устарел
      const cached = getCachedSchedule(group, college, true); // allowStale = true
      if (cached && cached.length > 0) {
        setSchedules(cached);
        setError(`Показано кэшированное расписание. ${errorMessage}`);
      } else {
        setSchedules([]);
      }
    } finally {
      setLoading(false);
    }
  }, []);
  
  const handleSettingsSave = useCallback((settings: {
    college: College;
    group: string;
    groupName: string;
    showBreaks: boolean;
    showLunch: boolean;
    theme: Theme;
  }) => {
    setState(prev => ({ ...prev, ...settings }));
    applyTheme(settings.theme);
    if (settings.group) {
      loadScheduleData(settings.group, settings.college);
    } else {
      setSchedules([]);
    }
  }, [applyTheme, loadScheduleData]);
  
  // Предзагрузка данных для следующей возможной группы (оптимизация UX)
  const preloadNextGroup = useCallback(async (currentGroup: string, college: College) => {
    // Предзагружаем только если есть кэш и мы онлайн
    if (!isOnline() || !currentGroup) return;
    
    // Небольшая задержка, чтобы не мешать основной загрузке
    setTimeout(() => {
      // Можно добавить логику предзагрузки похожих групп
      // Например, загружать соседние группы в фоне
    }, 2000);
  }, [loadScheduleData]);
  
  const hasGroup = useMemo(() => !!state.group, [state.group]);
  const hasSchedules = useMemo(() => schedules.length > 0, [schedules.length]);
  
  // Мемоизируем колбэки для оптимизации рендеринга
  const handleRefresh = useCallback(() => {
    loadScheduleData(state.group, state.college, false);
  }, [state.group, state.college, loadScheduleData]);
  
  const handleOpenSettings = useCallback(() => {
    setSettingsOpen(true);
  }, []);
  
  const handleOpenStatistics = useCallback(() => {
    setStatisticsOpen(true);
  }, []);
  
  const handleCloseSettings = useCallback(() => {
    setSettingsOpen(false);
  }, []);
  
  const handleCloseStatistics = useCallback(() => {
    setStatisticsOpen(false);
  }, []);
  
  return (
    <ErrorBoundary>
      <main className="min-h-screen flex flex-col">
      <header className="header bg-[var(--bg-card)] border-b border-[var(--border)] sticky top-0 z-50 backdrop-blur-xl shadow-sm relative overflow-hidden">
        <div 
          className="absolute inset-0 opacity-30 pointer-events-none"
          style={{
            background: `radial-gradient(circle at 20% 50%, var(--bg-gradient-start) 0%, transparent 50%),
                        radial-gradient(circle at 80% 80%, var(--bg-gradient-end) 0%, transparent 50%)`
          }}
        />
        <div className="header-content max-w-[600px] mx-auto px-4 py-4 relative z-10">
          <div className="flex justify-between items-center">
            <div className="flex items-center gap-3">
              <div className="logo-wrapper relative">
                <div className="logo text-xl font-bold text-[var(--text-primary)]">
                  Расписание
                </div>
              </div>
              {state.groupName && (
                <div className="group-indicator hidden sm:flex items-center gap-2 px-3 py-1.5 bg-[var(--bg-secondary)] border border-[var(--border)] rounded-full backdrop-blur-sm">
                  <div className="w-2 h-2 rounded-full bg-[var(--accent)] animate-pulse"></div>
                  <span className="text-xs font-medium text-[var(--text-secondary)]">{state.groupName}</span>
                </div>
              )}
            </div>
            <div className="flex gap-2">
              {hasSchedules && (
                <button
                  onClick={handleOpenStatistics}
                  className="icon-btn bg-[var(--bg-secondary)] hover:bg-[var(--bg-card-hover)] border border-[var(--border)] hover:border-[var(--accent)] text-[var(--text-primary)] w-10 h-10 rounded-xl flex items-center justify-center cursor-pointer transition-all hover:shadow-md hover:scale-105 active:scale-95"
                  aria-label="Статистика"
                  title="Итоги"
                >
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <path d="M3 3v18h18"></path>
                    <path d="M7 16l4-4 4 4 6-6"></path>
                    <path d="M21 12h-4"></path>
                  </svg>
                </button>
              )}
              <button
                onClick={handleOpenSettings}
                className="icon-btn bg-[var(--bg-secondary)] hover:bg-[var(--bg-card-hover)] border border-[var(--border)] hover:border-[var(--accent)] text-[var(--text-primary)] w-10 h-10 rounded-xl flex items-center justify-center cursor-pointer transition-all hover:shadow-md hover:scale-105 active:scale-95"
                aria-label="Настройки"
              >
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <circle cx="12" cy="12" r="3"></circle>
                  <path d="M12 1v6m0 6v6M5.64 5.64l4.24 4.24m4.24 4.24l4.24 4.24M1 12h6m6 0h6M5.64 18.36l4.24-4.24m4.24-4.24l4.24-4.24"></path>
                </svg>
              </button>
            </div>
          </div>
        </div>
      </header>
      
      <div className="main p-2 flex-1">
        <div className="container max-w-[600px] mx-auto">
          {hasGroup && (
            <>
              <div className="quick-actions flex gap-2 mb-3">
                <button
                  onClick={handleRefresh}
                  disabled={loading}
                  className="quick-btn flex-1 bg-[var(--bg-card)] border border-[var(--border)] text-[var(--text-primary)] p-3.5 rounded-xl text-sm font-semibold cursor-pointer transition-all flex items-center justify-center gap-2.5 font-inherit shadow-sm hover:bg-[var(--bg-card-hover)] hover:border-[var(--accent)] hover:-translate-y-0.5 hover:shadow-md relative overflow-hidden group disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:translate-y-0"
                  style={{
                    background: `linear-gradient(135deg, var(--bg-card) 0%, var(--bg-card-hover) 100%)`
                  }}
                  aria-label="Обновить расписание"
                >
                  <div 
                    className="absolute inset-0 opacity-0 group-hover:opacity-10 transition-opacity"
                    style={{
                      background: `radial-gradient(circle at 50% 50%, var(--accent), transparent 70%)`
                    }}
                  />
                  <svg 
                    width="20" 
                    height="20" 
                    viewBox="0 0 24 24" 
                    fill="none" 
                    stroke="currentColor" 
                    strokeWidth="2" 
                    className={`relative z-10 ${loading ? 'animate-spin' : ''}`}
                  >
                    <polyline points="23 4 23 10 17 10"></polyline>
                    <polyline points="1 20 1 14 7 14"></polyline>
                    <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path>
                  </svg>
                  <span className="relative z-10">{loading ? 'Обновление...' : 'Обновить'}</span>
                </button>
                <button
                  onClick={handleOpenSettings}
                  className="quick-btn flex-1 bg-[var(--bg-card)] border border-[var(--border)] text-[var(--text-primary)] p-3.5 rounded-xl text-sm font-semibold cursor-pointer transition-all flex items-center justify-center gap-2.5 font-inherit shadow-sm hover:bg-[var(--bg-card-hover)] hover:border-[var(--accent)] hover:-translate-y-0.5 hover:shadow-md relative overflow-hidden group"
                  style={{
                    background: `linear-gradient(135deg, var(--bg-card) 0%, var(--bg-card-hover) 100%)`
                  }}
                >
                  <div 
                    className="absolute inset-0 opacity-0 group-hover:opacity-10 transition-opacity"
                    style={{
                      background: `radial-gradient(circle at 50% 50%, var(--accent), transparent 70%)`
                    }}
                  />
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="relative z-10">
                    <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
                    <circle cx="9" cy="7" r="4"></circle>
                    <path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>
                    <path d="M16 3.13a4 4 0 0 1 0 7.75"></path>
                  </svg>
                  <span className="relative z-10">Сменить группу</span>
                </button>
              </div>
              
            </>
          )}
          
          {loading && !hasSchedules && (
            <SkeletonLoader />
          )}
          
          {loading && hasSchedules && (
            <div className="loading-overlay fixed inset-0 bg-black/20 backdrop-blur-sm z-40 flex items-center justify-center">
              <div className="bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-6 shadow-xl">
                <div className="spinner w-10 h-10 border-3 border-[var(--border)] border-t-[var(--accent)] rounded-full animate-spin mx-auto mb-4"></div>
                <p className="text-[var(--text-primary)] text-sm">Обновление расписания...</p>
              </div>
            </div>
          )}
          
          {error && !loading && !hasSchedules && (
            <div className="error-state text-center py-8 text-[var(--error)] animate-fade-in-up">
              <div className="error-icon mb-4 text-[var(--error)] opacity-80">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="mx-auto">
                  <circle cx="12" cy="12" r="10"></circle>
                  <line x1="12" y1="8" x2="12" y2="12"></line>
                  <line x1="12" y1="16" x2="12.01" y2="16"></line>
                </svg>
              </div>
              <p className="mb-4 text-[var(--text-primary)]">{error}</p>
              <button
                onClick={handleRefresh}
                className="btn btn-primary bg-[var(--accent)] border border-[var(--accent)] text-[var(--bg-primary)] px-6 py-3.5 rounded-lg text-sm font-semibold cursor-pointer transition-all font-inherit inline-flex items-center justify-center gap-2 shadow-lg hover:bg-[var(--accent-hover)] hover:border-[var(--accent-hover)] hover:-translate-y-0.5 hover:shadow-xl"
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <polyline points="23 4 23 10 17 10"></polyline>
                  <polyline points="1 20 1 14 7 14"></polyline>
                  <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path>
                </svg>
                Попробовать снова
              </button>
            </div>
          )}
          
          {isOffline && (
            <div className="offline-banner bg-yellow-500/20 border border-yellow-500/40 rounded-lg p-3 mb-3 text-yellow-600 dark:text-yellow-400 text-sm animate-fade-in-up">
              <div className="flex items-center gap-2">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path>
                  <circle cx="12" cy="10" r="3"></circle>
                </svg>
                <span>Нет подключения к интернету. Показано кэшированное расписание.</span>
              </div>
            </div>
          )}
          
          {error && hasSchedules && (
            <div className="error-banner bg-[var(--error)]/10 border border-[var(--error)]/30 rounded-lg p-3 mb-3 text-[var(--error)] text-sm animate-fade-in-up">
              <div className="flex items-center gap-2">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <circle cx="12" cy="12" r="10"></circle>
                  <line x1="12" y1="8" x2="12" y2="12"></line>
                  <line x1="12" y1="16" x2="12.01" y2="16"></line>
                </svg>
                <span>{error}</span>
              </div>
            </div>
          )}
          
          {!loading && !error && hasSchedules && (
            <Schedule
              schedules={schedules}
              college={state.college}
              showBreaks={state.showBreaks}
              showLunch={state.showLunch}
            />
          )}
          
          {!loading && !error && !hasSchedules && !hasGroup && (
            <div className="empty-state text-center py-8 text-[var(--text-secondary)]">
              <div className="empty-icon mb-4 text-[var(--text-secondary)] opacity-50">
                <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="mx-auto">
                  <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
                  <line x1="3" y1="10" x2="21" y2="10"></line>
                </svg>
              </div>
              <h2 className="text-2xl font-semibold my-4 text-[var(--text-primary)]">Добро пожаловать!</h2>
              <p className="mb-4">Выберите группу в настройках, чтобы начать</p>
              <button
                onClick={handleOpenSettings}
                className="btn btn-primary bg-[var(--accent)] border border-[var(--accent)] text-[var(--bg-primary)] px-6 py-3.5 rounded-lg text-sm font-semibold cursor-pointer transition-all font-inherit inline-flex items-center justify-center gap-2 shadow-lg hover:bg-[var(--accent-hover)] hover:border-[var(--accent-hover)] hover:-translate-y-0.5 hover:shadow-xl"
              >
                Выбрать группу
              </button>
            </div>
          )}
        </div>
      </div>
      
      {/* Footer */}
      <footer className="footer border-t border-[var(--border)] bg-[var(--bg-secondary)] mt-auto">
        <div className="max-w-[600px] mx-auto px-4 py-6">
          <div className="flex flex-col md:flex-row justify-between items-center gap-4 text-sm text-[var(--text-secondary)]">
            <div className="flex flex-col md:flex-row items-center gap-2 md:gap-4">
              <span className="font-medium text-[var(--text-primary)]">© 2025 Расписание</span>
              <span className="hidden md:inline text-[var(--border)]">•</span>
              <a 
                href="https://www.chtotib.ru/schedule_gl/" 
                target="_blank" 
                rel="noopener noreferrer"
                className="hover:text-[var(--accent)] transition-colors flex items-center gap-1"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path>
                  <polyline points="15 3 21 3 21 9"></polyline>
                  <line x1="10" y1="14" x2="21" y2="3"></line>
                </svg>
                ЧТОТиБ
              </a>
              <span className="hidden md:inline text-[var(--border)]">•</span>
              <a 
                href="https://bbb.zabgc.ru/" 
                target="_blank" 
                rel="noopener noreferrer"
                className="hover:text-[var(--accent)] transition-colors flex items-center gap-1"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path>
                  <polyline points="15 3 21 3 21 9"></polyline>
                  <line x1="10" y1="14" x2="21" y2="3"></line>
                </svg>
                ЗАБГК
              </a>
            </div>
            <div className="flex items-center gap-2 text-xs">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="opacity-60">
                <circle cx="12" cy="12" r="10"></circle>
                <polyline points="12 6 12 12 16 14"></polyline>
              </svg>
              <span>Обновлено:</span>
              <span className="text-[var(--text-primary)] font-medium">
                {new Date().toLocaleDateString('ru-RU', { 
                  day: 'numeric', 
                  month: 'long',
                  year: 'numeric'
                })}
              </span>
            </div>
          </div>
          <div className="mt-4 pt-4 border-t border-[var(--border)] text-xs text-[var(--text-secondary)] text-center space-y-1">
            <p className="flex items-center justify-center gap-1">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="opacity-60">
                <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"></path>
              </svg>
              Расписание загружается с официальных сайтов колледжей
            </p>
            <p className="flex items-center justify-center gap-1">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="opacity-60">
                <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"></path>
                <polyline points="3.27 6.96 12 12.01 20.73 6.96"></polyline>
                <line x1="12" y1="22.08" x2="12" y2="12"></line>
              </svg>
              Данные обновляются автоматически
            </p>
          </div>
        </div>
      </footer>
      
      <Settings
        isOpen={settingsOpen}
        onClose={handleCloseSettings}
        onSave={handleSettingsSave}
        currentCollege={state.college}
        currentGroup={state.group}
        currentGroupName={state.groupName}
        currentShowBreaks={state.showBreaks}
        currentShowLunch={state.showLunch}
        currentTheme={state.theme}
      />
      
      {statisticsOpen && (
        <div className="modal fixed inset-0 z-[1000] p-0 flex items-center justify-center">
          <div 
            className="modal-overlay absolute inset-0 bg-black/60 backdrop-blur-md"
            onClick={handleCloseStatistics}
          />
          <div className="modal-content relative bg-[var(--bg-card)] border border-[var(--border)] rounded-2xl w-full max-w-[600px] max-h-[85vh] overflow-hidden z-10 animate-scale-in shadow-2xl mx-4">
            <div className="modal-header flex justify-between items-center p-6 border-b border-[var(--border)] bg-gradient-to-r from-[var(--bg-card)] to-[var(--bg-card-hover)]">
              <h2 className="text-xl font-bold text-[var(--text-primary)] flex items-center gap-2">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M3 3v18h18"></path>
                  <path d="M7 16l4-4 4 4 6-6"></path>
                  <path d="M21 12h-4"></path>
                </svg>
                Итоги
              </h2>
              <button
                onClick={handleCloseStatistics}
                className="modal-close bg-[var(--bg-secondary)] hover:bg-[var(--bg-card-hover)] border border-[var(--border)] text-[var(--text-secondary)] text-xl leading-none p-0 w-8 h-8 flex items-center justify-center rounded-lg transition-all hover:text-[var(--text-primary)] hover:border-[var(--accent)]"
                aria-label="Закрыть"
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <line x1="18" y1="6" x2="6" y2="18"></line>
                  <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
              </button>
            </div>
            <div className="modal-body p-6 overflow-y-auto max-h-[calc(85vh-80px)]">
              <Statistics schedules={schedules} groupFile={state.group} college={state.college} />
            </div>
          </div>
        </div>
      )}
      
      </main>
    </ErrorBoundary>
  );
}

