'use client';

import { memo } from 'react';
import { DaySchedule, College } from '@/lib/types';
import DayCard from './DayCard';

interface ScheduleProps {
  schedules: DaySchedule[];
  college: College;
  showBreaks: boolean;
  showLunch: boolean;
}

function Schedule({ schedules, college, showBreaks, showLunch }: ScheduleProps) {
  if (schedules.length === 0) {
    return null;
  }

  return (
    <div className="schedule-list flex flex-col gap-3 mt-2">
      {schedules.map((daySchedule, index) => (
        <DayCard
          key={`${daySchedule.day}-${daySchedule.date}-${index}`}
          daySchedule={daySchedule}
          college={college}
          showBreaks={showBreaks}
          showLunch={showLunch}
        />
      ))}
    </div>
  );
}

export default memo(Schedule);

