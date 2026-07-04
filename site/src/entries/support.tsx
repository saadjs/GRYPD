import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '../styles/tokens.css';
import '../components/page-shell.css';
import '../components/sidebar.css';
import '../styles/content.css';
import { PageShell } from '../components/PageShell';

const FAQS = [
  {
    q: 'GRYPD says a workout is "Unavailable": what happened?',
    a: "That workout left the published catalog (Apple occasionally retires episodes). Your logged history for it is preserved, it just can't be re-opened for browsing.",
  },
  {
    q: 'Why does GRYPD need a Fitness+ subscription?',
    a: "It doesn't for logging, but the catalog only covers workouts that exist on Apple Fitness+, and playing them back requires the Fitness app and an active subscription.",
  },
  {
    q: "Can I add a workout that isn't in GRYPD yet?",
    a: 'The catalog is rebuilt weekly from a community-maintained source. See Data Source for how to contribute a missing workout.',
  },
  {
    q: 'Does GRYPD support Android or the web?',
    a: 'No, it is a native SwiftUI app for iOS 26+, by design (see the GitHub repo for the full technical rationale).',
  },
];

function Support() {
  return (
    <PageShell>
      <p className="eyebrow">Resources</p>
      <h1 className="page-title">Support</h1>
      <p className="page-intro">
        GRYPD is a small, open-source project. The fastest way to reach the
        maintainer is GitHub.
      </p>

      <div className="callout callout--brand">
        <h3>Report a bug or request a feature</h3>
        <p>
          <a href="https://github.com/saadjs/grypd/issues" target="_blank" rel="noreferrer">
            Open an issue on GitHub ↗
          </a>
        </p>
      </div>

      <section className="doc-section" id="faq">
        <h2 className="section-title">Frequently asked</h2>
        <div className="faq-list">
          {FAQS.map((item) => (
            <div className="faq-item" key={item.q}>
              <h3>{item.q}</h3>
              <p>{item.a}</p>
            </div>
          ))}
        </div>
      </section>

      <footer className="doc-footer">
        <span>GRYPD is an independent project and is not affiliated with Apple Inc.</span>
        <a href="/">Home</a>
      </footer>
    </PageShell>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Support />
  </StrictMode>,
);
