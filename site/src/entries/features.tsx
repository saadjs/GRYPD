import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '../styles/tokens.css';
import '../components/page-shell.css';
import '../components/sidebar.css';
import '../components/device-frame.css';
import '../styles/content.css';
import { PageShell } from '../components/PageShell';
import { DeviceFrame } from '../components/DeviceFrame';
import { OnThisPage } from '../components/OnThisPage';

const TOC = [
  { id: 'filter', label: 'Filter by what matters' },
  { id: 'log', label: 'Log the weight you lift' },
  { id: 'dumbbells', label: 'Smart dumbbell defaults' },
  { id: 'progress', label: 'Progression, per move' },
  { id: 'goals', label: 'Weekly goals & streaks' },
  { id: 'local', label: 'Local-only, always' },
];

function Features() {
  return (
    <PageShell toc={<OnThisPage items={TOC} />}>
      <p className="eyebrow">Guide</p>
      <h1 className="page-title">Features</h1>
      <p className="page-intro">
        Apple Fitness+ has the workouts. GRYPD adds the strength-training tools it's
        missing: finding the right workout and tracking what you lifted.
      </p>

      <section className="doc-section" id="filter">
        <div className="feature-row">
          <div>
            <h2 className="section-title">Filter by what matters</h2>
            <div className="section-body">
              <p>
                Apple's own filters stop at coarse body focus. GRYPD adds{' '}
                <strong>muscle group</strong>, <strong>duration</strong>, and{' '}
                <strong>equipment</strong>, so "20-minute lower-body dumbbell workout"
                is one filter tap, not a scroll.
              </p>
            </div>
            <div className="pill-row">
              <span className="pill">12 muscle groups</span>
              <span className="pill">Duration</span>
              <span className="pill">Body focus</span>
              <span className="pill">Trainer</span>
            </div>
          </div>
          <div className="feature-row__visual">
            <DeviceFrame
              src="/screenshots/detail.png"
              alt="Workout detail screen showing muscle group chips, dumbbell tiers, and the move list for a Strength episode"
              caption="Muscle groups, dumbbells, and moves at a glance"
            />
          </div>
        </div>
      </section>

      <section className="doc-section" id="log">
        <div className="feature-row feature-row--reverse">
          <div>
            <h2 className="section-title">Log the weight you lift</h2>
            <div className="section-body">
              <p>
                Fitness+ tracks calories and effort, not load. After a workout, log the
                weight for each move. GRYPD keeps that history <strong>per workout</strong>{' '}
                and <strong>per move</strong>, so the same move done in two different
                workouts still shows one continuous trend.
              </p>
            </div>
          </div>
          <div className="feature-row__visual">
            <DeviceFrame
              src="/screenshots/log.png"
              alt="Add Workout sheet with per-move sets, auto-filled dumbbell weight, reps, and duration"
              caption="Logging a session: weight auto-filled per move"
            />
          </div>
        </div>
      </section>

      <section className="doc-section" id="dumbbells">
        <div className="feature-row">
          <div>
            <h2 className="section-title">Smart dumbbell defaults</h2>
            <div className="section-body">
              <p>
                Set your own <strong>light / medium / heavy</strong> dumbbell weights
                once in Settings. GRYPD classifies each move and auto-fills the right
                tier when you log, no re-typing "15 lb" every session.
              </p>
            </div>
          </div>
          <div className="feature-row__visual">
            <DeviceFrame
              src="/screenshots/settings.png"
              alt="Settings screen showing default weight unit and light, medium, heavy dumbbell tiers"
              caption="Set your tiers once in Settings"
            />
          </div>
        </div>
      </section>

      <section className="doc-section" id="progress">
        <div className="feature-row feature-row--reverse">
          <div>
            <h2 className="section-title">Progression, per move</h2>
            <div className="section-body">
              <p>
                See whether you're actually getting stronger, charted per workout and
                per individual move, grouped by source so unrelated exercises never get
                merged together.
              </p>
            </div>
          </div>
          <div className="feature-row__visual">
            <DeviceFrame
              src="/screenshots/progress.png"
              alt="Progress screen showing session totals and an exercise progression chart"
              caption="Progression: charted per move"
            />
          </div>
        </div>
      </section>

      <section className="doc-section" id="goals">
        <div className="feature-row">
          <div>
            <h2 className="section-title">Weekly goals & streaks</h2>
            <div className="section-body">
              <p>
                Opt in to a Monday–Sunday target: one total session count, or split
                across <strong>upper</strong>, <strong>lower</strong>, and{' '}
                <strong>total body</strong>. History fills a ring for each as you log,
                and tracks a <strong>current</strong> and <strong>best streak</strong>{' '}
                of weeks you hit it.
              </p>
            </div>
            <div className="pill-row">
              <span className="pill">Total or by body focus</span>
              <span className="pill">Current + best streak</span>
              <span className="pill">Effective-dated</span>
            </div>
          </div>
          <div className="feature-row__visual">
            <DeviceFrame
              src="/screenshots/weekly-goals.png"
              alt="History screen showing this week's progress rings for upper body, lower body, and total body goals, plus current and best streak tiles"
              caption="Rings fill as you log; streaks tick up when the week's goal is met"
            />
          </div>
        </div>
        <div className="callout">
          <h3>No retroactive streaks</h3>
          <p>
            Editing a target only changes the current week; a finished week keeps
            the definition it was actually completed under, so lowering a target
            later can't manufacture a streak.
          </p>
        </div>
      </section>

      <section className="doc-section" id="local">
        <h2 className="section-title">Local-only, always</h2>
        <div className="callout callout--brand">
          <h3>No account. No sync. No analytics.</h3>
          <p>
            Every log lives on-device in SwiftData. GRYPD only ever makes one kind of
            network request: a read-only fetch of the public workout catalog. See{' '}
            <a href="/privacy.html">Privacy</a> for the full picture.
          </p>
        </div>
      </section>

      <footer className="doc-footer">
        <span>Next: how the catalog itself is built.</span>
        <a href="/data-source.html">Data Source →</a>
      </footer>
    </PageShell>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Features />
  </StrictMode>,
);
