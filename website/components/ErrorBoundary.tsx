'use client';

import { Component, ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('ErrorBoundary caught an error:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="error-boundary text-center py-12 px-4">
          <div className="max-w-md mx-auto">
            <div className="error-icon mb-4 text-[var(--error)] opacity-80">
              <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="mx-auto">
                <circle cx="12" cy="12" r="10"></circle>
                <line x1="12" y1="8" x2="12" y2="12"></line>
                <line x1="12" y1="16" x2="12.01" y2="16"></line>
              </svg>
            </div>
            <h2 className="text-xl font-semibold mb-2 text-[var(--text-primary)]">
              Что-то пошло не так
            </h2>
            <p className="text-sm text-[var(--text-secondary)] mb-6">
              Произошла непредвиденная ошибка. Пожалуйста, обновите страницу.
            </p>
            <button
              onClick={() => {
                this.setState({ hasError: false, error: null });
                window.location.reload();
              }}
              className="btn btn-primary bg-[var(--accent)] border border-[var(--accent)] text-[var(--bg-primary)] px-6 py-3 rounded-lg text-sm font-semibold cursor-pointer transition-all font-inherit inline-flex items-center justify-center gap-2 shadow-lg hover:bg-[var(--accent-hover)] hover:border-[var(--accent-hover)] hover:-translate-y-0.5 hover:shadow-xl"
            >
              Обновить страницу
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}



