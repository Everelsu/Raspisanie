'use client';

import { memo } from 'react';

function SkeletonLoader() {
  return (
    <div className="schedule-list flex flex-col gap-3 mt-2 animate-fade-in-up">
      {[1, 2, 3].map((i) => (
        <div
          key={i}
          className="day-card bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-5 animate-pulse"
        >
          <div className="day-header flex justify-between items-center mb-3 pb-2 border-b border-[var(--border)]">
            <div className="h-5 w-32 bg-[var(--bg-secondary)] rounded"></div>
            <div className="h-4 w-24 bg-[var(--bg-secondary)] rounded"></div>
          </div>
          
          <div className="space-y-2">
            {[1, 2, 3].map((j) => (
              <div key={j} className="flex gap-3 p-3 bg-[var(--bg-secondary)] rounded-lg">
                <div className="w-9 h-9 bg-[var(--bg-card)] rounded-lg flex-shrink-0"></div>
                <div className="flex-1 space-y-2">
                  <div className="h-4 w-3/4 bg-[var(--bg-card)] rounded"></div>
                  <div className="h-3 w-1/2 bg-[var(--bg-card)] rounded"></div>
                </div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

export default memo(SkeletonLoader);



