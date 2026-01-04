'use client';

import { memo, useMemo, useState, useEffect } from 'react';
import { DaySchedule, College } from '@/lib/types';
import { calculateStatistics } from '@/lib/statistics';
import { loadStatistics, StatisticsData } from '@/lib/statisticsParser';
import { getStoredState } from '@/lib/storage';

interface StatisticsProps {
  schedules: DaySchedule[];
  groupFile?: string;
  college?: College;
}

function Statistics({ schedules, groupFile, college }: StatisticsProps) {
  const [realStats, setRealStats] = useState<StatisticsData | null>(null);
  const [loadingStats, setLoadingStats] = useState(false);
  const scheduleStats = useMemo(() => calculateStatistics(schedules), [schedules]);
  
  useEffect(() => {
    if (groupFile && college) {
      setLoadingStats(true);
      loadStatistics(groupFile, college)
        .then(data => {
          if (data && data.disciplines.length > 0) {
            setRealStats(data);
          } else {
            setRealStats(null);
          }
        })
        .catch(err => {
          console.warn('Не удалось загрузить статистику:', err);
          setRealStats(null);
        })
        .finally(() => {
          setLoadingStats(false);
        });
    } else {
      setRealStats(null);
    }
  }, [groupFile, college]);
  
  const stats = realStats || scheduleStats;

  if (loadingStats) {
    return (
      <div className="text-center py-12">
        <div className="spinner w-10 h-10 border-3 border-[var(--border)] border-t-[var(--accent)] rounded-full animate-spin mx-auto mb-4"></div>
        <p className="text-[var(--text-secondary)]">Загрузка статистики...</p>
      </div>
    );
  }

  if (schedules.length === 0 && !realStats) {
    return (
      <div className="text-center py-12 text-[var(--text-secondary)]">
        <div className="mb-4">
          <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="mx-auto opacity-50">
            <path d="M3 3v18h18"></path>
            <path d="M7 16l4-4 4 4 6-6"></path>
            <path d="M21 12h-4"></path>
          </svg>
        </div>
        <p>Загрузите расписание, чтобы увидеть статистику</p>
      </div>
    );
  }

  // Если есть реальная статистика, показываем её
  if (realStats) {
    const completionPercentage = realStats.totalHours > 0 
      ? Math.round((realStats.totalFactHours / realStats.totalHours) * 100) 
      : 0;
    
    return (
      <div className="statistics space-y-6 animate-fade-in-up">
        {/* Общая статистика */}
        <div className="stats-cards grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div className="stat-card bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-4 text-center relative overflow-hidden group hover:border-[var(--accent)] transition-all">
            <div className="absolute inset-0 opacity-0 group-hover:opacity-5 transition-opacity" style={{ background: `radial-gradient(circle at 50% 50%, var(--accent), transparent 70%)` }} />
            <div className="text-3xl font-bold text-[var(--accent)] mb-1 relative z-10">{realStats.totalDisciplines}</div>
            <div className="text-xs text-[var(--text-secondary)] relative z-10">Дисциплин</div>
          </div>
          <div className="stat-card bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-4 text-center relative overflow-hidden group hover:border-[var(--accent)] transition-all">
            <div className="absolute inset-0 opacity-0 group-hover:opacity-5 transition-opacity" style={{ background: `radial-gradient(circle at 50% 50%, var(--accent), transparent 70%)` }} />
            <div className="text-3xl font-bold text-[var(--accent)] mb-1 relative z-10">{realStats.totalHours}</div>
            <div className="text-xs text-[var(--text-secondary)] relative z-10">Всего часов</div>
          </div>
          <div className="stat-card bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-4 text-center relative overflow-hidden group hover:border-[var(--accent)] transition-all">
            <div className="absolute inset-0 opacity-0 group-hover:opacity-5 transition-opacity" style={{ background: `radial-gradient(circle at 50% 50%, var(--accent), transparent 70%)` }} />
            <div className="text-3xl font-bold text-[var(--accent)] mb-1 relative z-10">{realStats.totalFactHours}</div>
            <div className="text-xs text-[var(--text-secondary)] relative z-10">Проведено</div>
          </div>
          <div className="stat-card bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-4 text-center relative overflow-hidden group hover:border-[var(--accent)] transition-all">
            <div className="absolute inset-0 opacity-0 group-hover:opacity-5 transition-opacity" style={{ background: `radial-gradient(circle at 50% 50%, var(--accent), transparent 70%)` }} />
            <div className="text-3xl font-bold text-[var(--accent)] mb-1 relative z-10">{completionPercentage}%</div>
            <div className="text-xs text-[var(--text-secondary)] relative z-10">Выполнено</div>
          </div>
        </div>

        {/* Дисциплины с реальными данными */}
        {realStats.disciplines.length > 0 && (
          <div className="section">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-[var(--text-primary)]">Дисциплины</h3>
              <div className="text-xs text-[var(--text-secondary)]">
                Всего: <span className="font-semibold text-[var(--accent)]">{realStats.disciplines.length}</span>
              </div>
            </div>
            <div className="space-y-3">
              {realStats.disciplines.map((discipline, index) => (
                <div 
                  key={`${discipline.name}-${index}`} 
                  className="discipline-item bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-4 hover:border-[var(--accent)] transition-all relative overflow-hidden group shadow-sm hover:shadow-md"
                >
                  <div 
                    className="absolute inset-0 opacity-0 group-hover:opacity-5 transition-opacity pointer-events-none"
                    style={{ background: `radial-gradient(circle at 50% 50%, var(--accent), transparent 70%)` }}
                  />
                  <div className="relative z-10">
                    <div className="flex justify-between items-start mb-3">
                      <div className="flex-1 min-w-0 pr-3">
                        <div className="text-sm font-bold text-[var(--text-primary)] mb-2 leading-tight">
                          {discipline.name}
                        </div>
                        <div className="flex flex-wrap gap-2 text-xs">
                          <div className="flex items-center gap-1 text-[var(--text-secondary)] bg-[var(--bg-secondary)] px-2 py-1 rounded-md">
                            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                              <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
                              <circle cx="12" cy="7" r="4"></circle>
                            </svg>
                            {discipline.teacher}
                          </div>
                          <div className="flex items-center gap-1 text-[var(--text-secondary)] bg-[var(--bg-secondary)] px-2 py-1 rounded-md">
                            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                              <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"></path>
                              <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"></path>
                            </svg>
                            {discipline.type}
                          </div>
                          {discipline.completionDate && (
                            <div className="flex items-center gap-1 text-[var(--text-secondary)] bg-[var(--bg-secondary)] px-2 py-1 rounded-md">
                              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                                <circle cx="12" cy="12" r="10"></circle>
                                <polyline points="12 6 12 12 16 14"></polyline>
                              </svg>
                              {discipline.completionDate}
                            </div>
                          )}
                        </div>
                      </div>
                      <div className="text-right flex-shrink-0">
                        <div className="text-2xl font-bold text-[var(--accent)] mb-0.5">{discipline.percentage}%</div>
                        <div className="text-xs text-[var(--text-secondary)]">выполнено</div>
                      </div>
                    </div>
                    
                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-3">
                      <div className="bg-[var(--bg-secondary)] rounded-lg p-2.5 text-center">
                        <div className="text-[var(--text-secondary)] text-xs mb-1">Всего</div>
                        <div className="text-lg font-bold text-[var(--text-primary)]">{discipline.totalHours}</div>
                        <div className="text-[10px] text-[var(--text-secondary)]">часов</div>
                      </div>
                      <div className="bg-[var(--bg-secondary)] rounded-lg p-2.5 text-center">
                        <div className="text-[var(--text-secondary)] text-xs mb-1">Проведено</div>
                        <div className="text-lg font-bold text-[var(--accent)]">{discipline.factHours}</div>
                        <div className="text-[10px] text-[var(--text-secondary)]">часов</div>
                      </div>
                      <div className="bg-[var(--bg-secondary)] rounded-lg p-2.5 text-center">
                        <div className="text-[var(--text-secondary)] text-xs mb-1">Осталось</div>
                        <div className="text-lg font-bold text-[var(--text-primary)]">{discipline.remainingHours}</div>
                        <div className="text-[10px] text-[var(--text-secondary)]">часов</div>
                      </div>
                      <div className="bg-[var(--bg-secondary)] rounded-lg p-2.5 text-center">
                        <div className="text-[var(--text-secondary)] text-xs mb-1">План</div>
                        <div className="text-lg font-bold text-[var(--text-primary)]">{discipline.plan2Weeks.toFixed(1)}</div>
                        <div className="text-[10px] text-[var(--text-secondary)]">2 нед.</div>
                      </div>
                    </div>
                    
                    <div className="relative">
                      <div className="w-full bg-[var(--bg-secondary)] rounded-full h-3 overflow-hidden">
                        <div
                          className="h-full bg-gradient-to-r from-[var(--accent)] to-[var(--accent-hover)] rounded-full transition-all duration-700 shadow-sm relative overflow-hidden"
                          style={{ width: `${Math.min(discipline.percentage, 100)}%` }}
                        >
                          <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent animate-shimmer"></div>
                        </div>
                      </div>
                      <div className="flex justify-between items-center mt-1.5 text-[10px] text-[var(--text-secondary)]">
                        <span>0%</span>
                        <span className="font-semibold text-[var(--accent)]">{discipline.percentage}%</span>
                        <span>100%</span>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    );
  }

  // Fallback на статистику из расписания
  return (
    <div className="statistics space-y-6 animate-fade-in-up">
      {/* Общая статистика */}
      <div className="stats-cards grid grid-cols-2 gap-3">
        <div className="stat-card bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-4 text-center">
          <div className="text-2xl font-bold text-[var(--accent)] mb-1">{scheduleStats.totalLessons}</div>
          <div className="text-xs text-[var(--text-secondary)]">Всего пар</div>
        </div>
        <div className="stat-card bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-4 text-center">
          <div className="text-2xl font-bold text-[var(--accent)] mb-1">{scheduleStats.totalDays}</div>
          <div className="text-xs text-[var(--text-secondary)]">Дней в расписании</div>
        </div>
      </div>

      {/* Дисциплины */}
      {scheduleStats.disciplines.length > 0 && (
        <div className="section">
          <h3 className="text-lg font-semibold mb-3 text-[var(--text-primary)]">Дисциплины</h3>
          <div className="space-y-2">
            {scheduleStats.disciplines.slice(0, 10).map((discipline, index) => (
              <div key={discipline.name} className="discipline-item bg-[var(--bg-card)] border border-[var(--border)] rounded-lg p-3">
                <div className="flex justify-between items-center mb-1">
                  <span className="text-sm font-medium text-[var(--text-primary)] truncate flex-1">
                    {discipline.name}
                  </span>
                  <span className="text-sm font-bold text-[var(--accent)] ml-2">
                    {discipline.count}
                  </span>
                </div>
                <div className="w-full bg-[var(--bg-secondary)] rounded-full h-2 overflow-hidden">
                  <div
                    className="h-full bg-[var(--accent)] rounded-full transition-all duration-500"
                    style={{ width: `${discipline.percentage}%` }}
                  />
                </div>
                <div className="text-xs text-[var(--text-secondary)] mt-1">
                  {discipline.percentage}% от общего количества
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Преподаватели */}
      {stats.teachers.length > 0 && (
        <div className="section">
          <h3 className="text-lg font-semibold mb-3 text-[var(--text-primary)]">Преподаватели</h3>
          <div className="grid grid-cols-1 gap-2">
            {stats.teachers.slice(0, 10).map((teacher) => (
              <div
                key={teacher.name}
                className="teacher-item bg-[var(--bg-card)] border border-[var(--border)] rounded-lg p-3 flex justify-between items-center hover:bg-[var(--bg-card-hover)] transition-colors"
              >
                <span className="text-sm text-[var(--text-primary)] truncate flex-1">
                  {teacher.name}
                </span>
                <span className="text-sm font-semibold text-[var(--accent)] ml-2">
                  {teacher.count} {teacher.count === 1 ? 'пара' : teacher.count < 5 ? 'пары' : 'пар'}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Аудитории */}
      {stats.classrooms.length > 0 && (
        <div className="section">
          <h3 className="text-lg font-semibold mb-3 text-[var(--text-primary)]">Аудитории</h3>
          <div className="grid grid-cols-2 gap-2">
            {stats.classrooms.slice(0, 12).map((classroom) => (
              <div
                key={classroom.name}
                className="classroom-item bg-[var(--bg-card)] border border-[var(--border)] rounded-lg p-2 text-center hover:bg-[var(--bg-card-hover)] transition-colors"
              >
                <div className="text-sm font-medium text-[var(--text-primary)]">{classroom.name}</div>
                <div className="text-xs text-[var(--text-secondary)]">{classroom.count} пар</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Дни недели */}
      {Object.keys(stats.lessonsPerDay).length > 0 && (
        <div className="section">
          <h3 className="text-lg font-semibold mb-3 text-[var(--text-primary)]">Нагрузка по дням</h3>
          <div className="space-y-2">
            {Object.entries(stats.lessonsPerDay)
              .sort((a, b) => b[1] - a[1])
              .map(([day, count]) => (
                <div key={day} className="day-item bg-[var(--bg-card)] border border-[var(--border)] rounded-lg p-3">
                  <div className="flex justify-between items-center mb-2">
                    <span className="text-sm font-medium text-[var(--text-primary)]">{day}</span>
                    <span className="text-sm font-bold text-[var(--accent)]">{count} пар</span>
                  </div>
                  <div className="w-full bg-[var(--bg-secondary)] rounded-full h-2 overflow-hidden">
                    <div
                      className="h-full bg-[var(--accent)] rounded-full transition-all duration-500"
                      style={{
                        width: `${(count / Math.max(...Object.values(stats.lessonsPerDay))) * 100}%`,
                      }}
                    />
                  </div>
                </div>
              ))}
          </div>
          {stats.mostBusyDay && (
            <div className="mt-4 p-3 bg-[var(--bg-card)] border border-[var(--accent)]/30 rounded-lg">
              <div className="text-sm text-[var(--text-secondary)]">
                Самый загруженный день: <span className="font-semibold text-[var(--accent)]">{stats.mostBusyDay}</span>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default memo(Statistics);

