'use client';

import { memo, useMemo } from 'react';
import { ScheduleItem } from '@/lib/types';

interface LessonItemProps {
  item: ScheduleItem;
  lessonTimes?: { start: string; end: string };
}

function LessonItem({ item, lessonTimes }: LessonItemProps) {
  // Мемоизируем детали для избежания пересчета при каждом рендере
  const details = useMemo(() => {
    const result: string[] = [];
    if (item.classroom) result.push(`Аудитория: ${item.classroom}`);
    if (item.teacher) result.push(item.teacher);
    if (item.subgroup) result.push(`Подгруппа ${item.subgroup}`);
    if (lessonTimes) {
      result.push(`${lessonTimes.start} - ${lessonTimes.end}`);
    }
    return result;
  }, [item.classroom, item.teacher, item.subgroup, lessonTimes?.start, lessonTimes?.end]);
  
  return (
    <div className="lesson-item flex gap-3 p-3 mb-2 bg-[var(--bg-secondary)] border border-[var(--border)] border-l-[3px] border-l-[var(--accent)] rounded-lg transition-all duration-250 hover:bg-[var(--bg-card-hover)] hover:border-[var(--accent)] hover:translate-x-1 shadow-sm hover:shadow-md animate-fade-in-up">
      <div className="lesson-number-wrapper relative w-9 h-9 flex-shrink-0">
        <div 
          className="lesson-number gradient-number text-[var(--accent)] w-9 h-9 rounded-lg flex items-center justify-center font-bold text-sm shadow-lg relative overflow-hidden"
          style={{
            background: `linear-gradient(135deg, var(--gradient-start, #2a2a2a) 0%, var(--gradient-center, #1e1e1e) 50%, var(--gradient-end, #0f0f0f) 100%)`,
            boxShadow: `0 2px 8px rgba(0, 0, 0, 0.3), 0 0 0 1px rgba(var(--accent-rgb, 255, 255, 255), 0.1) inset`
          }}
        >
          <span className="relative z-10">{item.lessonNumber}</span>
          <div 
            className="absolute inset-0 opacity-20"
            style={{
              background: `radial-gradient(circle at 30% 30%, var(--accent), transparent 70%)`
            }}
          />
        </div>
      </div>
      <div className="lesson-content flex-1 min-w-0">
        {item.subject && (
          <div className="lesson-subject text-sm font-semibold mb-0.5 text-[var(--text-primary)] break-words leading-tight">
            {item.subject}
          </div>
        )}
        {details.length > 0 && (
          <div className="lesson-details text-xs text-[var(--text-secondary)] leading-tight break-words">
            {details.join(' • ')}
          </div>
        )}
      </div>
    </div>
  );
}

export default memo(LessonItem);

