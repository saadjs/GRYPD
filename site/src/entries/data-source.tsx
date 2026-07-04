import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '../styles/tokens.css';
import '../components/page-shell.css';
import '../components/sidebar.css';
import '../styles/content.css';
import { PageShell } from '../components/PageShell';
import { OnThisPage } from '../components/OnThisPage';

const TOC = [
  { id: 'join', label: 'How the catalog is built' },
  { id: 'seatable', label: 'The community SeaTable base' },
  { id: 'refresh', label: 'Weekly refresh' },
];

function DataSource() {
  return (
    <PageShell toc={<OnThisPage items={TOC} />}>
      <p className="eyebrow">Guide</p>
      <h1 className="page-title">Data Source</h1>
      <p className="page-intro">
        GRYPD's catalog isn't scraped at runtime and it isn't hand-maintained. It's
        built weekly by joining two sources that each cover the other's gap.
      </p>

      <section className="doc-section" id="join">
        <h2 className="section-title">How the catalog is built</h2>
        <div className="section-body">
          <p>
            Each week's build reads a SeaTable export, enriches every row that has a
            known Apple workout link by parsing that page's embedded JSON, then joins
            the two records on Apple's stable catalog id.
          </p>
        </div>
        <div className="compare">
          <div className="compare__col">
            <h4>Apple provides</h4>
            <ul>
              <li>Canonical episode name &amp; trainer</li>
              <li>Duration &amp; body focus</li>
              <li>Stable catalog identity</li>
            </ul>
          </div>
          <div className="compare__col compare__col--brand">
            <h4>SeaTable provides</h4>
            <ul>
              <li>12 granular muscle groups</li>
              <li>Per-workout move list</li>
              <li>Dumbbells used</li>
            </ul>
          </div>
        </div>
        <div className="section-body">
          <p>
            Rows without a known Apple link yet are still published as fallback
            entries, so the catalog reflects the full crowdsourced list even where
            Apple's side hasn't been matched.
          </p>
        </div>
      </section>

      <section className="doc-section" id="seatable">
        <h2 className="section-title">The community SeaTable base</h2>
        <div className="section-body">
          <p>
            The granular data comes from a public, crowdsourced SeaTable base called{' '}
            <strong>Crowdsourcing Form for Fitness+ Workouts</strong>, maintained by
            the Apple Fitness+ community, not by GRYPD. Anyone can browse or
            contribute to it directly.
          </p>
        </div>
        <div className="callout">
          <h3>Crowdsourcing Form for Fitness+ Workouts</h3>
          <p>
            <a
              href="https://cloud.seatable.io/dtable/external-links/d08506897d274835bdab/?tid=1vDI&vid=0000"
              target="_blank"
              rel="noreferrer"
            >
              View the SeaTable base ↗
            </a>
          </p>
        </div>
      </section>

      <section className="doc-section" id="refresh">
        <h2 className="section-title">Weekly refresh</h2>
        <div className="section-body">
          <p>
            The pipeline is run by hand each week against a fresh SeaTable export,
            validated, and published as a versioned, content-addressed JSON catalog.
            The app checks that catalog's manifest and only refreshes its local copy
            when the hash changes. The whole pipeline is{' '}
            <a href="https://github.com/saadjs/grypd" target="_blank" rel="noreferrer">
              open source
            </a>{' '}
            if you want to see exactly how a row goes from spreadsheet to app.
          </p>
        </div>
      </section>

      <footer className="doc-footer">
        <span>How this catalog data is used on-device.</span>
        <a href="/privacy.html">Privacy →</a>
      </footer>
    </PageShell>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <DataSource />
  </StrictMode>,
);
