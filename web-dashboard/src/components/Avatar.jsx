import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { initials } from './Sidebar.jsx';

const SIZES = {
  sm: 'h-9 w-9 text-xs',
  md: 'h-11 w-11 text-sm',
  lg: 'h-24 w-24 text-2xl',
};

/**
 * Profile picture from `avatar_url` (needs the login token, so it's fetched
 * as a blob), or the person's initials. `preview` shows a local file instead
 * (a picture chosen but not uploaded yet).
 */
export default function Avatar({ path, name, size = 'md', preview, className = 'bg-brand-900 text-gold-400' }) {
  const [src, setSrc] = useState('');
  useEffect(() => {
    if (preview || !path) {
      setSrc('');
      return undefined;
    }
    let alive = true;
    api
      .avatarUrl(path)
      .then((url) => alive && setSrc(url))
      .catch(() => alive && setSrc(''));
    return () => {
      alive = false;
    };
  }, [path, preview]);

  const shown = preview || src;
  return (
    <span className={`relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full font-bold ${SIZES[size]} ${className}`} title={name}>
      {shown ? <img src={shown} alt="" className="h-full w-full object-cover" /> : initials(name)}
    </span>
  );
}
