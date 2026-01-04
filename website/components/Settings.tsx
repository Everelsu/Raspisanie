'use client';

import { useState, useEffect } from 'react';
import { Group, College, Theme } from '@/lib/types';
import { loadGroups } from '@/lib/scheduleParser';
import { saveState } from '@/lib/storage';

interface SettingsProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (settings: {
    college: College;
    group: string;
    groupName: string;
    showBreaks: boolean;
    showLunch: boolean;
    theme: Theme;
  }) => void;
  currentCollege: College;
  currentGroup: string;
  currentGroupName: string;
  currentShowBreaks: boolean;
  currentShowLunch: boolean;
  currentTheme: Theme;
}

export default function Settings({
  isOpen,
  onClose,
  onSave,
  currentCollege,
  currentGroup,
  currentGroupName,
  currentShowBreaks,
  currentShowLunch,
  currentTheme,
}: SettingsProps) {
  const [college, setCollege] = useState<College>(currentCollege);
  const [groupSelect, setGroupSelect] = useState('');
  const [groupInput, setGroupInput] = useState('');
  const [showBreaks, setShowBreaks] = useState(currentShowBreaks);
  const [showLunch, setShowLunch] = useState(currentShowLunch);
  const [theme, setTheme] = useState<Theme>(currentTheme);
  const [groups, setGroups] = useState<Group[]>([]);
  const [loadingGroups, setLoadingGroups] = useState(false);
  
  useEffect(() => {
    if (isOpen) {
      setCollege(currentCollege);
      setGroupSelect(currentGroup);
      setGroupInput(currentGroup);
      setShowBreaks(currentShowBreaks);
      setShowLunch(currentShowLunch);
      setTheme(currentTheme);
      loadGroupsList(currentCollege);
    }
  }, [isOpen, currentCollege, currentGroup, currentShowBreaks, currentShowLunch, currentTheme]);
  
  useEffect(() => {
    if (isOpen && college !== currentCollege) {
      loadGroupsList(college);
    }
  }, [college, isOpen]);
  
  async function loadGroupsList(col: College) {
    setLoadingGroups(true);
    try {
      const groupsList = await loadGroups(col);
      setGroups(groupsList);
      if (groupsList.length > 0 && col === currentCollege) {
        const found = groupsList.find(g => g.file === currentGroup);
        if (found) {
          setGroupSelect(currentGroup);
        }
      }
    } catch (err) {
      console.error('Ошибка загрузки групп:', err);
    } finally {
      setLoadingGroups(false);
    }
  }
  
  function handleSave() {
    let group = '';
    let groupName = '';
    
    if (groupSelect) {
      group = groupSelect;
      const selectedGroup = groups.find(g => g.file === groupSelect);
      groupName = selectedGroup?.name || groupSelect.replace('.htm', '').toUpperCase();
    } else if (groupInput.trim()) {
      group = groupInput.trim();
      groupName = group.replace('.htm', '').toUpperCase();
    }
    
    const settings = {
      college,
      group,
      groupName,
      showBreaks,
      showLunch,
      theme,
    };
    
    saveState(settings);
    onSave(settings);
    onClose();
  }
  
  if (!isOpen) return null;
  
  return (
    <div className="modal fixed inset-0 z-[1000] p-0 flex items-center justify-center">
      <div 
        className="modal-overlay absolute inset-0 bg-black/60 backdrop-blur-md"
        onClick={onClose}
      />
      <div className="modal-content relative bg-[var(--bg-card)] border border-[var(--border)] rounded-2xl w-full max-w-[600px] max-h-[85vh] overflow-hidden z-10 animate-scale-in shadow-2xl mx-4">
        <div className="modal-header flex justify-between items-center p-6 border-b border-[var(--border)] bg-gradient-to-r from-[var(--bg-card)] to-[var(--bg-card-hover)]">
          <h2 className="text-xl font-bold text-[var(--text-primary)]">Настройки</h2>
          <button
            onClick={onClose}
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
          {/* Категория: Основные настройки */}
          <div className="settings-category mb-6">
            <h3 className="text-sm font-semibold text-[var(--text-primary)] mb-3 uppercase tracking-wide">Основные настройки</h3>
            
            <div className="form-group mb-4">
              <label className="block mb-2 text-sm font-medium text-[var(--text-secondary)]">Колледж</label>
            <select
              value={college}
              onChange={(e) => setCollege(e.target.value as College)}
              className="form-input w-full p-3.5 bg-[var(--bg-secondary)] border border-[var(--border)] rounded-lg text-[var(--text-primary)] text-sm font-inherit transition-all focus:outline-none focus:border-[var(--accent)] focus:bg-[var(--bg-card)]"
            >
              <option value="chtotib">ЧТОТИБ</option>
              <option value="zabgc">ЗАБГК</option>
            </select>
            </div>
            
            <div className="form-group mb-4">
              <label className="block mb-2 text-sm font-medium text-[var(--text-secondary)]">Группа</label>
            <div className="group-select-wrapper relative">
              <select
                value={groupSelect}
                onChange={(e) => setGroupSelect(e.target.value)}
                disabled={loadingGroups}
                className="form-input w-full p-3.5 bg-[var(--bg-secondary)] border border-[var(--border)] rounded-lg text-[var(--text-primary)] text-sm font-inherit transition-all focus:outline-none focus:border-[var(--accent)] focus:bg-[var(--bg-card)] disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <option value="">{loadingGroups ? 'Загрузка групп...' : 'Выберите группу'}</option>
                {groups.map(group => (
                  <option key={group.file} value={group.file}>
                    {group.name}
                  </option>
                ))}
              </select>
              {loadingGroups && (
                <div className="absolute right-3 top-1/2 -translate-y-1/2">
                  <div className="mini-spinner w-4 h-4 border-2 border-[var(--border)] border-t-[var(--accent)] rounded-full animate-spin" />
                </div>
              )}
            </div>
            <small className="block text-xs text-[var(--text-secondary)] mt-1">Или введите файл вручную</small>
            <input
              type="text"
              value={groupInput}
              onChange={(e) => setGroupInput(e.target.value)}
              placeholder="cg36.htm"
              className="form-input w-full p-3.5 bg-[var(--bg-secondary)] border border-[var(--border)] rounded-lg text-[var(--text-primary)] text-sm font-inherit transition-all focus:outline-none focus:border-[var(--accent)] focus:bg-[var(--bg-card)] mt-2"
            />
            </div>
          </div>
          
          {/* Категория: Отображение */}
          <div className="settings-category mb-6">
            <h3 className="text-sm font-semibold text-[var(--text-primary)] mb-3 uppercase tracking-wide">Отображение</h3>
            
            <div className="form-group mb-4">
              <label className="block mb-2 text-sm font-medium text-[var(--text-secondary)]">Настройки отображения</label>
            <div className="settings-switches flex flex-col gap-3">
              <label className="switch-label flex items-center gap-3 cursor-pointer p-2 rounded-lg transition-colors hover:bg-[var(--bg-secondary)]">
                <input
                  type="checkbox"
                  checked={showBreaks}
                  onChange={(e) => setShowBreaks(e.target.checked)}
                  className="w-5 h-5 cursor-pointer accent-[var(--accent)]"
                />
                <span className="text-sm text-[var(--text-primary)] select-none">Показывать перемены</span>
              </label>
              <label className="switch-label flex items-center gap-3 cursor-pointer p-2 rounded-lg transition-colors hover:bg-[var(--bg-secondary)]">
                <input
                  type="checkbox"
                  checked={showLunch}
                  onChange={(e) => setShowLunch(e.target.checked)}
                  className="w-5 h-5 cursor-pointer accent-[var(--accent)]"
                />
                <span className="text-sm text-[var(--text-primary)] select-none">Показывать обеды</span>
              </label>
            </div>
            </div>
          </div>
          
          {/* Категория: Внешний вид */}
          <div className="settings-category mb-6">
            <h3 className="text-sm font-semibold text-[var(--text-primary)] mb-3 uppercase tracking-wide">Внешний вид</h3>
            
            <div className="form-group mb-4">
              <label className="block mb-2 text-sm font-medium text-[var(--text-secondary)]">Тема оформления</label>
            <div className="theme-selector grid grid-cols-4 gap-3">
              {(['dark', 'light', 'purple', 'green', 'newyear', 'halloween', 'nothing'] as Theme[]).map((themeOption) => (
                <button
                  key={themeOption}
                  onClick={() => setTheme(themeOption)}
                  className={`theme-btn bg-[var(--bg-secondary)] border-2 rounded-xl p-3 cursor-pointer transition-all flex flex-col items-center gap-2 font-inherit shadow-sm hover:border-[var(--accent)] hover:bg-[var(--bg-card)] hover:-translate-y-1 hover:shadow-lg relative overflow-hidden group ${
                    theme === themeOption 
                      ? 'border-[var(--accent)] bg-[var(--bg-card)] border-[3px] shadow-md scale-105' 
                      : 'border-[var(--border)] hover:scale-105'
                  }`}
                >
                  {theme === themeOption && (
                    <div 
                      className="absolute inset-0 opacity-10"
                      style={{
                        background: `radial-gradient(circle at 50% 50%, var(--accent), transparent 70%)`
                      }}
                    />
                  )}
                  <div
                    className={`theme-preview w-12 h-12 rounded-xl border-2 transition-all relative z-10 overflow-hidden ${
                      theme === themeOption 
                        ? 'border-[var(--accent)] scale-110 shadow-lg' 
                        : 'border-[var(--border)] group-hover:border-[var(--accent)]'
                    }`}
                    style={{
                      backgroundColor: getThemeColor(themeOption),
                      borderColor: themeOption === 'light' && theme !== themeOption ? '#e0e0e0' : undefined,
                      boxShadow: theme === themeOption 
                        ? `0 4px 12px rgba(0, 0, 0, 0.15), 0 0 0 2px var(--accent)` 
                        : undefined
                    }}
                  >
                    {themeOption === 'light' && (
                      <div className="absolute inset-0 border border-[var(--border)] rounded-xl" style={{ borderColor: '#e0e0e0' }}></div>
                    )}
                    {theme === themeOption && (
                      <div className={`absolute inset-0 flex items-center justify-center backdrop-blur-sm ${
                        themeOption === 'light' ? 'bg-black/10' : 'bg-[var(--bg-card)]/20'
                      }`}>
                        <svg 
                          width="18" 
                          height="18" 
                          viewBox="0 0 24 24" 
                          fill="none" 
                          stroke={themeOption === 'light' ? '#000000' : 'currentColor'} 
                          strokeWidth="3" 
                          className={`drop-shadow-sm ${themeOption === 'light' ? 'text-black' : 'text-[var(--accent)]'}`}
                        >
                          <polyline points="20 6 9 17 4 12"></polyline>
                        </svg>
                      </div>
                    )}
                  </div>
                  <span className={`text-xs relative z-10 transition-all ${
                    theme === themeOption 
                      ? 'text-[var(--accent)] font-bold' 
                      : 'text-[var(--text-secondary)] group-hover:text-[var(--text-primary)]'
                  }`}>
                    {getThemeName(themeOption)}
                  </span>
                </button>
              ))}
            </div>
            </div>
          </div>
          
          <button
            onClick={handleSave}
            className="btn btn-primary btn-full w-full bg-[var(--accent)] border border-[var(--accent)] text-[var(--bg-primary)] p-3.5 rounded-lg text-sm font-semibold cursor-pointer transition-all font-inherit flex items-center justify-center gap-2 shadow-lg hover:bg-[var(--accent-hover)] hover:border-[var(--accent-hover)] hover:-translate-y-0.5 hover:shadow-xl"
          >
            <span>Загрузить расписание</span>
          </button>
        </div>
      </div>
    </div>
  );
}

function getThemeColor(theme: Theme): string {
  const colors: { [key in Theme]: string } = {
    dark: '#0a0a0a',
    light: '#ffffff', // Белый для светлой темы
    purple: '#6750A4',
    green: '#4CAF50',
    newyear: '#2E7D32',
    halloween: '#FF7B4A',
    nothing: '#FF3333',
  };
  return colors[theme];
}

function getThemeName(theme: Theme): string {
  const names: { [key in Theme]: string } = {
    dark: 'Тёмная',
    light: 'Светлая',
    purple: 'Фиолетовая',
    green: 'Зелёная',
    newyear: 'Новогодняя',
    halloween: 'Хеллоуин',
    nothing: 'Nothing',
  };
  return names[theme];
}

