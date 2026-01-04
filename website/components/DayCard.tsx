'use client';

import { memo, useMemo } from 'react';
import { DaySchedule, ScheduleItem } from '@/lib/types';
import { LESSON_TIMES, BREAKS, LUNCHES, College } from '@/lib/config';
import { formatDayName, isToday, formatDate } from '@/lib/utils';
import LessonItem from './LessonItem';

interface DayCardProps {
  daySchedule: DaySchedule;
  college: College;
  showBreaks: boolean;
  showLunch: boolean;
}

function DayCard({ daySchedule, college, showBreaks, showLunch }: DayCardProps) {
  const lessonTimes = LESSON_TIMES[college];
  const isTodayDate = useMemo(() => isToday(daySchedule.date), [daySchedule.date]);
  
  // Group items by lesson number - memoized
  const { groupedByLesson, sortedLessonNumbers } = useMemo(() => {
    const grouped: { [key: number]: ScheduleItem[] } = {};
    daySchedule.items.forEach(item => {
      if (!grouped[item.lessonNumber]) {
        grouped[item.lessonNumber] = [];
      }
      grouped[item.lessonNumber].push(item);
    });
    const sorted = Object.keys(grouped).map(Number).sort((a, b) => a - b);
    return { groupedByLesson: grouped, sortedLessonNumbers: sorted };
  }, [daySchedule.items]);
  
  let previousLessonNumber: number | null = null;
  
  return (
    <div
      className={`day-card bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-5 transition-all duration-300 shadow-sm hover:shadow-lg hover:-translate-y-1 animate-scale-in ${
        isTodayDate 
          ? 'border-2 border-[var(--accent)] shadow-xl relative overflow-hidden' 
          : ''
      }`}
      style={{
        background: isTodayDate 
          ? `linear-gradient(135deg, var(--bg-card) 0%, var(--bg-card-hover) 100%)`
          : undefined,
        boxShadow: isTodayDate 
          ? `0 4px 20px rgba(0, 0, 0, 0.3), 0 0 0 3px rgba(var(--accent-rgb, 255, 255, 255), 0.15)` 
          : undefined
      }}
    >
      {isTodayDate && (
        <div 
          className="absolute inset-0 opacity-10 pointer-events-none"
          style={{
            background: `radial-gradient(circle at 50% 0%, var(--accent), transparent 70%)`
          }}
        />
      )}
      <div className="day-header flex justify-between items-center mb-3 pb-2 border-b border-[var(--border)] relative z-10">
        <div className={`day-name text-base font-semibold relative ${isTodayDate ? 'text-[var(--accent)] font-bold' : 'text-[var(--text-primary)]'}`}>
          {formatDayName(daySchedule.day)}
          {isTodayDate && (
            <span 
              className="absolute -left-2 top-1/2 -translate-y-1/2 w-1.5 h-1.5 rounded-full bg-[var(--accent)] animate-pulse"
              style={{
                boxShadow: `0 0 8px var(--accent)`
              }}
            />
          )}
        </div>
        <div className="date-text text-sm text-[var(--text-secondary)]">
          {formatDate(daySchedule.date)}
        </div>
      </div>
      
      <div className="relative z-10">
        {daySchedule.items.length === 0 ? (
          <div className="empty-day text-center py-6 text-[var(--text-secondary)] text-sm opacity-70">
            Нет занятий
          </div>
        ) : (
          <>
            {sortedLessonNumbers.map(lessonNum => {
            const items = groupedByLesson[lessonNum];
            const result = [];
            
            // Add break before lesson if needed
            if (previousLessonNumber !== null && showBreaks) {
              const breakKey = `${previousLessonNumber}-${lessonNum}`;
              const breakText = BREAKS[college]?.[breakKey as keyof typeof BREAKS[typeof college]];
              if (breakText) {
                result.push(
                  <div key={`break-${breakKey}`} className="break-item text-center py-1 my-1 text-xs text-[var(--text-secondary)] opacity-80 italic">
                    {breakText}
                  </div>
                );
              }
            }
            
            // Add lessons (оптимизация: используем индекс для key)
            const itemsLength = items.length;
            for (let idx = 0; idx < itemsLength; idx++) {
              const item = items[idx];
              result.push(
                <LessonItem
                  key={`lesson-${lessonNum}-${idx}`}
                  item={item}
                  lessonTimes={lessonTimes[item.lessonNumber]}
                />
              );
            }
            
            // Add lunch after lesson if needed
            if (showLunch) {
              const lunchText = LUNCHES[college]?.[lessonNum as keyof typeof LUNCHES[typeof college]];
              if (lunchText) {
                result.push(
                  <div key={`lunch-${lessonNum}`} className="lunch-item text-center py-1 my-1 text-xs text-[var(--accent)] opacity-90 italic">
                    {lunchText}
                  </div>
                );
              }
            }
            
            previousLessonNumber = lessonNum;
            return result;
          })}
          </>
        )}
      </div>
    </div>
  );
}

export default memo(DayCard);

