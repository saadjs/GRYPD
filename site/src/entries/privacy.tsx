import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '../styles/tokens.css';
import '../components/page-shell.css';
import '../components/sidebar.css';
import '../styles/content.css';
import { PageShell } from '../components/PageShell';

function Privacy() {
  return (
    <PageShell>
      <p className="eyebrow">Resources</p>
      <h1 className="page-title">Privacy</h1>
      <p className="page-meta">Last updated July 2026</p>

      <div className="callout callout--brand">
        <h3>The short version</h3>
        <p>
          GRYPD has no accounts, no analytics, and no tracking. Everything you log
          stays on your device.
        </p>
      </div>

      <section className="doc-section" id="collect">
        <h2 className="section-title">What GRYPD collects</h2>
        <div className="section-body">
          <p>Nothing that identifies you. GRYPD does not require or offer sign-in.</p>
        </div>
      </section>

      <section className="doc-section" id="stored">
        <h2 className="section-title">What's stored, and where</h2>
        <div className="section-body">
          <p>
            Workout logs, meaning weights, dates, and notes you enter, are stored locally
            on your device using Apple's SwiftData framework. They are never uploaded
            anywhere. Deleting the app deletes them.
          </p>
        </div>
      </section>

      <section className="doc-section" id="network">
        <h2 className="section-title">Network requests</h2>
        <div className="section-body">
          <p>
            GRYPD makes exactly one kind of outbound request: a read-only fetch of the
            public workout catalog (the same JSON files this site is hosted alongside).
            That request contains no identifying information, not even a device
            identifier.
          </p>
        </div>
      </section>

      <section className="doc-section" id="thirdparty">
        <h2 className="section-title">Third parties</h2>
        <div className="section-body">
          <p>
            None. No ad networks, no crash reporters, no analytics SDKs. See{' '}
            <a href="/data-source.html">Data Source</a> for where the catalog itself
            comes from.
          </p>
        </div>
      </section>

      <footer className="doc-footer">
        <span>Questions? Open an issue on GitHub.</span>
        <a href="/support.html">Support →</a>
      </footer>
    </PageShell>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Privacy />
  </StrictMode>,
);
