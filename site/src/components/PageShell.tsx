import { useState, type ReactNode } from 'react';
import { Sidebar } from './Sidebar';
import './page-shell.css';

export function PageShell({
  children,
  toc,
}: {
  children: ReactNode;
  toc?: ReactNode;
}) {
  const [open, setOpen] = useState(false);

  return (
    <div className="shell">
      <button
        className="shell__menu-btn"
        onClick={() => setOpen((v) => !v)}
        aria-label="Toggle navigation"
      >
        <span />
        <span />
        <span />
      </button>

      {open && <div className="shell__scrim" onClick={() => setOpen(false)} />}

      <Sidebar open={open} />

      <main className="shell__content">
        <div className="shell__content-inner">{children}</div>
      </main>

      {toc && <aside className="shell__toc">{toc}</aside>}
    </div>
  );
}
