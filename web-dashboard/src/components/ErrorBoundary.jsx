import { Component } from 'react';
import Icon from './icons.jsx';

/**
 * Catches a crash while rendering a page so the rest of the dashboard (the
 * sidebar, other pages) keeps working. Give it a `resetKey` (the page id) so
 * moving to another page clears the error.
 */
export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('[dashboard] page crashed', error, info?.componentStack);
  }

  componentDidUpdate(prev) {
    if (this.state.error && prev.resetKey !== this.props.resetKey) this.setState({ error: null });
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    return (
      <div className="mx-auto mt-10 max-w-lg animate-fade-up rounded-2xl border border-red-200 bg-white p-6 text-center shadow-sm">
        <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-red-50 text-red-600">
          <Icon name="alert" className="h-6 w-6" />
        </span>
        <h2 className="mt-4 text-lg font-bold text-ink">This page ran into a problem</h2>
        <p className="mt-1 text-sm text-ink2">
          The rest of the dashboard still works. Try loading the page again; if it keeps happening, reload the browser tab.
        </p>
        <details className="mt-4 text-left text-xs text-muted">
          <summary className="cursor-pointer select-none text-ink2">Technical details</summary>
          <pre className="mt-2 max-h-40 overflow-auto whitespace-pre-wrap rounded-lg bg-canvas p-3">{String(error?.message || error)}</pre>
        </details>
        <div className="mt-5 flex justify-center gap-2">
          <button
            type="button"
            onClick={() => this.setState({ error: null })}
            className="inline-flex items-center gap-2 rounded-lg bg-brand-700 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-800"
          >
            <Icon name="refresh" className="h-4 w-4" />
            Try again
          </button>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="rounded-lg border border-line bg-white px-4 py-2 text-sm font-semibold text-ink hover:bg-canvas"
          >
            Reload tab
          </button>
        </div>
      </div>
    );
  }
}
