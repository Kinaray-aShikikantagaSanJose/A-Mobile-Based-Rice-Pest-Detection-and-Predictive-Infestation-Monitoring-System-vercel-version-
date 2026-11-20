import { useEffect, useState } from 'react';
import { ROLE_LABELS } from '../lib.js';
import Avatar from './Avatar.jsx';
import { Logo } from './Brand.jsx';
import Icon from './icons.jsx';

export const initials = (name) =>
  (name || '?')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() || '')
    .join('') || '?';

const countLabel = (n) => (n > 99 ? '99+' : String(n));

/**
 * The dashboard navigation. On large screens it sits on the left and
 * collapses to an icon rail (labels then show as tooltips); on small screens
 * it opens as a drawer from the top bar's menu button.
 */
export default function Sidebar({ groups, currentId, badges, viewer, collapsed, onToggle, onNavigate, onSignOut, mobileOpen, onCloseMobile, freshId }) {
  // Close the drawer with Escape and keep the page behind it still.
  useEffect(() => {
    if (!mobileOpen) return undefined;
    const onKey = (e) => e.key === 'Escape' && onCloseMobile();
    window.addEventListener('keydown', onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = prev;
    };
  }, [mobileOpen, onCloseMobile]);

  const common = { groups, currentId, badges, viewer, onSignOut, freshId };
  return (
    <>
      <aside
        className={`sticky top-0 z-[1600] hidden h-screen shrink-0 flex-col bg-brand-900 text-brand-100 shadow-xl shadow-black/10 transition-[width] duration-300 ease-out lg:flex ${
          collapsed ? 'w-20' : 'w-[272px]'
        }`}
      >
        <SidebarBody {...common} collapsed={collapsed} onNavigate={onNavigate} />
        </aside>

      {mobileOpen && (
        <div className="fixed inset-0 z-[2100] lg:hidden" role="dialog" aria-modal="true" aria-label="Navigation">
          <div className="absolute inset-0 animate-fade-in bg-black/50 backdrop-blur-[2px]" onClick={onCloseMobile} />
          <aside className="relative flex h-full w-[284px] max-w-[85vw] animate-slide-in flex-col bg-brand-900 text-brand-100 shadow-2xl">
            <button
              type="button"
              onClick={onCloseMobile}
              aria-label="Close menu"
              className="absolute right-3 top-5 rounded-lg p-1.5 text-brand-100/80 hover:bg-white/10 hover:text-white"
            >
              <Icon name="x" />
            </button>
            <SidebarBody
              {...common}
              collapsed={false}
              onNavigate={(id) => {
                onNavigate(id);
                onCloseMobile();
              }}
            />
          </aside>
        </div>
      )}
    </>
  );
}

function SidebarBody({ groups, currentId, badges, viewer, collapsed, onNavigate, onSignOut, freshId }) {
  // Collapsed items show their label in a tooltip next to the rail. The nav
  // scrolls, which would clip a CSS tooltip, so it is placed with fixed position.
  const [tip, setTip] = useState(null);
  useEffect(() => setTip(null), [collapsed]);
  const showTip = (e, label) => {
    if (!collapsed) return;
    const r = e.currentTarget.getBoundingClientRect();
    setTip({ label, top: r.top + r.height / 2, left: r.right + 12 });
  };
  const hideTip = () => setTip(null);
  const name = viewer.full_name || viewer.email;

  return (
    <>
      <div className={`flex h-[76px] shrink-0 items-center gap-3 border-b border-white/[0.07] ${collapsed ? 'justify-center px-2' : 'px-5'}`}>
        <Logo className="h-11 w-11" tile />
        {!collapsed && (
          <div className="min-w-0 animate-fade-in">
            <div className="truncate text-[17px] font-extrabold tracking-tight text-white">
              Palay <span className="text-gold-400">Patrol</span>
            </div>
            <div className="truncate text-xs text-brand-100/60">Web dashboard</div>
          </div>
        )}
      </div>

      <nav className="nav-scroll flex-1 overflow-y-auto overflow-x-hidden px-3 py-4" onScroll={hideTip}>
        {groups.map((g, gi) => (
          <div key={g.group} className={gi ? 'mt-5' : ''}>
            {collapsed ? (
              gi > 0 && <div className="mx-auto mb-3 h-px w-8 bg-white/10" />
            ) : (
              <div className="px-3 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-brand-100/45">{g.group}</div>
            )}
            <div className="space-y-1">
              {g.items.map((i) => {
                const active = i.id === currentId;
                const count = i.badge ? badges[i.badge] || 0 : 0;
                // New submissions since the person last opened this page.
                const isNew = i.id === freshId;
                return (
                  <button
                    key={i.id}
                    type="button"
                    onClick={() => onNavigate(i.id)}
                    onMouseEnter={(e) => showTip(e, count ? `${i.label} (${count})` : i.label)}
                    onMouseLeave={hideTip}
                    onFocus={(e) => showTip(e, count ? `${i.label} (${count})` : i.label)}
                    onBlur={hideTip}
                    aria-current={active ? 'page' : undefined}
                    aria-label={collapsed ? i.label : undefined}
                    className={`group relative flex w-full items-center rounded-xl py-2.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-400/70 ${
                      collapsed ? 'justify-center px-0' : 'gap-3 px-3'
                    } ${active ? 'bg-white/[0.12] text-white' : 'text-brand-100/80 hover:bg-white/[0.06] hover:text-white'}`}
                  >
                    {active && <span className="absolute left-0 top-1/2 h-6 w-1 -translate-y-1/2 rounded-r-full bg-gold-400" />}
                    <span className="relative">
                      <Icon
                        name={i.icon}
                        className={`h-5 w-5 transition-colors ${active ? 'text-gold-400' : 'text-brand-100/65 group-hover:text-white'}`}
                      />
                      {isNew && (
                        <span className={`absolute flex h-2.5 w-2.5 ${collapsed ? '-left-1.5 -top-1.5' : '-right-1 -top-1'}`}>
                          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-red-500 opacity-75" />
                          <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-red-500 ring-2 ring-brand-900" />
                        </span>
                      )}
                      {collapsed && count > 0 && (
                        <span className="absolute -right-2 -top-2 min-w-[18px] rounded-full bg-orange-500 px-1 text-center text-[10px] font-bold leading-[18px] text-white ring-2 ring-brand-900">
                          {countLabel(count)}
                        </span>
                      )}
                    </span>
                    {!collapsed && <span className="flex-1 truncate text-left">{i.label}</span>}
                    {!collapsed && isNew && <span className="rounded-full bg-red-500 px-1.5 py-0.5 text-[10px] font-extrabold uppercase tracking-wide text-white">New</span>}
                    {!collapsed && count > 0 && (
                      <span className="rounded-full bg-orange-500 px-2 py-0.5 text-[11px] font-bold text-white">{countLabel(count)}</span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        ))}
      </nav>

      <div className={`shrink-0 border-t border-white/[0.07] ${collapsed ? 'p-3' : 'p-4'}`}>
        <div className={`flex items-center ${collapsed ? 'flex-col gap-2' : 'gap-3'}`}>
          <span onMouseEnter={(e) => showTip(e, name)} onMouseLeave={hideTip}>
            <Avatar path={viewer.avatar_url} name={name} className="bg-gold-500 text-brand-950" />
          </span>
          {!collapsed && (
            <div className="min-w-0 flex-1">
              <div className="truncate text-sm font-semibold text-white">{name}</div>
              <div className="truncate text-xs text-brand-100/60">
                {ROLE_LABELS[viewer.role]}
                {viewer.role === 'technician' && ` Â· ${viewer.area_label || 'no coverage set'}`}
              </div>
            </div>
          )}
          <button
            type="button"
            onClick={onSignOut}
            onMouseEnter={(e) => showTip(e, 'Sign out')}
            onMouseLeave={hideTip}
            aria-label="Sign out"
            title={collapsed ? undefined : 'Sign out'}
            className="rounded-lg p-2 text-brand-100/70 transition hover:bg-white/10 hover:text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-400/70"
          >
            <Icon name="logout" className="h-[18px] w-[18px]" />
          </button>
        </div>
      </div>

      {tip && (
        <div
          role="tooltip"
          className="pointer-events-none fixed z-[2200] -translate-y-1/2 animate-fade-in whitespace-nowrap rounded-lg bg-brand-950 px-2.5 py-1.5 text-xs font-semibold text-white shadow-xl ring-1 ring-white/10"
          style={{ top: tip.top, left: tip.left }}
        >
          {tip.label}
        </div>
      )}
    </>
  );
}

