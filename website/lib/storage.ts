import { AppState, College, Theme } from './config';

export function getStoredState(): Partial<AppState> {
  if (typeof window === 'undefined') {
    return {};
  }
  
  return {
    college: (localStorage.getItem('college') as College) || 'chtotib',
    group: localStorage.getItem('group') || '',
    groupName: localStorage.getItem('groupName') || '',
    theme: (localStorage.getItem('theme') as Theme) || 'dark',
    showBreaks: localStorage.getItem('showBreaks') !== 'false',
    showLunch: localStorage.getItem('showLunch') !== 'false',
  };
}

export function saveState(state: Partial<AppState>): void {
  if (typeof window === 'undefined') {
    return;
  }
  
  if (state.college !== undefined) {
    localStorage.setItem('college', state.college);
  }
  if (state.group !== undefined) {
    localStorage.setItem('group', state.group);
  }
  if (state.groupName !== undefined) {
    localStorage.setItem('groupName', state.groupName);
  }
  if (state.theme !== undefined) {
    localStorage.setItem('theme', state.theme);
  }
  if (state.showBreaks !== undefined) {
    localStorage.setItem('showBreaks', String(state.showBreaks));
  }
  if (state.showLunch !== undefined) {
    localStorage.setItem('showLunch', String(state.showLunch));
  }
}



