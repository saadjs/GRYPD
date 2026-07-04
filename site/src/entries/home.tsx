import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '../styles/tokens.css';
import '../components/page-shell.css';
import '../components/sidebar.css';
import '../components/device-frame.css';
import '../styles/content.css';
import './home.css';
import { PageShell } from '../components/PageShell';
import { DeviceFrame } from '../components/DeviceFrame';

function Home() {
  return (
    <PageShell>
      <div className="hero">
        <div className="hero__text">
          <p className="eyebrow">GRYPD Docs</p>
          <h1 className="page-title">
            The strength companion
            <br />
            for Apple Fitness+.
          </h1>
          {/* GRYPD = "gripped"; Fitness+ Strength is dumbbells only. */}
          <p className="pronunciation">
            <span className="pronunciation__word">gripped</span>
            <span className="pronunciation__sep" aria-hidden="true">
              ·
            </span>
            <span className="pronunciation__phon">/ɡrɪpt/</span>
            <span className="pronunciation__sep" aria-hidden="true">
              ·
            </span>
            <span className="pronunciation__def">a dumbbell in each hand</span>
          </p>
          <p className="page-intro">
            Filter Strength workouts by muscle group, duration, and body focus, then
            log the weight you lifted, per workout and per move, to see progress over
            time. 100% native SwiftUI, on-device, open source.
          </p>
          <div className="hero__actions">
            <a className="btn btn--primary" href="/features.html">
              Explore features
            </a>
            <a
              className="btn btn--ghost"
              href="https://github.com/saadjs/grypd"
              target="_blank"
              rel="noreferrer"
            >
              View source ↗
            </a>
          </div>
          <div className="pill-row">
            <span className="pill">iOS 26</span>
            <span className="pill">SwiftUI</span>
            <span className="pill">Local-only</span>
            <span className="pill">No account</span>
          </div>
        </div>
        <div className="hero__visual">
          <DeviceFrame src="/screenshots/browse.png" alt="GRYPD Browse screen showing a list of Strength workouts" />
        </div>
      </div>

      <div className="link-grid">
        <a className="link-card" href="/features.html">
          <span className="link-card__label">Guide</span>
          <h3>Features</h3>
          <p>Filtering, logging, and progression: how GRYPD fills the gap.</p>
        </a>
        <a className="link-card" href="/data-source.html">
          <span className="link-card__label">Guide</span>
          <h3>Data Source</h3>
          <p>How Apple's catalog and a community SeaTable base are joined.</p>
        </a>
        <a
          className="link-card"
          href="https://github.com/saadjs/grypd"
          target="_blank"
          rel="noreferrer"
        >
          <span className="link-card__label">Repository</span>
          <h3>GitHub ↗</h3>
          <p>Open source, MIT-licensed, built entirely with Apple frameworks.</p>
        </a>
      </div>

      <footer className="doc-footer">
        <span>GRYPD is an independent project and is not affiliated with Apple Inc.</span>
        <a href="/privacy.html">Privacy</a>
      </footer>
    </PageShell>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Home />
  </StrictMode>,
);
