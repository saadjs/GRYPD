import './sidebar.css';

type NavItem = { label: string; href: string; badge?: string };
type NavGroup = { title: string; items: NavItem[] };

const GROUPS: NavGroup[] = [
  {
    title: 'Overview',
    items: [{ label: 'Welcome', href: '/' }],
  },
  {
    title: 'Guide',
    items: [
      { label: 'Features', href: '/features.html' },
      { label: 'Data Source', href: '/data-source.html' },
    ],
  },
  {
    title: 'Resources',
    items: [
      { label: 'Privacy', href: '/privacy.html' },
      { label: 'Support', href: '/support.html' },
    ],
  },
];

function normalizePath(path: string) {
  const trimmed = path.endsWith('/index.html')
    ? path.slice(0, -'index.html'.length)
    : path.replace(/\.html$/, '');
  const withoutTrailingSlash = trimmed.length > 1 ? trimmed.replace(/\/$/, '') : trimmed;
  return withoutTrailingSlash || '/';
}

function isActive(href: string) {
  if (typeof window === 'undefined') return false;
  return normalizePath(window.location.pathname) === normalizePath(href);
}

export function Sidebar({ open }: { open?: boolean }) {
  return (
    <nav className={`sidebar${open ? ' is-open' : ''}`} aria-label="Documentation">
      <a className="sidebar__brand" href="/">
        <img className="sidebar__mark" src="/icon-180.png" alt="" aria-hidden="true" />
        <span className="sidebar__wordmark">GRYPD</span>
      </a>
      <p className="sidebar__tagline">Strength companion for Apple Fitness+</p>

      <div className="sidebar__groups">
        {GROUPS.map((group) => (
          <div className="sidebar__group" key={group.title}>
            <h3 className="sidebar__group-title">{group.title}</h3>
            <ul className="sidebar__list">
              {group.items.map((item) => (
                <li key={item.href}>
                  <a
                    href={item.href}
                    className="sidebar__link"
                    aria-current={isActive(item.href) ? 'page' : undefined}
                  >
                    {item.label}
                    {item.badge && <span className="sidebar__badge">{item.badge}</span>}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>

      <a
        className="sidebar__github"
        href="https://github.com/saadjs/grypd"
        target="_blank"
        rel="noreferrer"
      >
        <span>Open source on GitHub</span>
        <span aria-hidden="true">↗</span>
      </a>
    </nav>
  );
}
