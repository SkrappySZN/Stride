# Evil Stride

A running tracker in one HTML file. Drop in FIT files from the Garmin; it tells you
what to do today, whether the week passed, and whether the same pace is costing
fewer heartbeats.

**Live:** https://skrappyszn.github.io/Stride/

No build step to use it, no server of its own. FIT files are parsed in the page
(Garmin's official FIT SDK, loaded from jsDelivr on first upload) and stored in this
browser's IndexedDB. Sign in, and your runs also sync to your account.

## Layout

No sidebar: a slim top bar with the tabs (a bottom dock on phones), and every page opens
with a full-width poster band — the page's headline in giant condensed type and its key
numbers — over a grid of cards. `1`–`6` switch tabs.

## Plans

The first visit asks which plan to follow; switch any time from the Plan tab. Runs,
check-ins and body data never change when you switch.

- **Run/walk build** — 8 weeks from 9–10 minutes of jogging with walk breaks to a continuous
  1.5 miles, then some speed.
- **Build to 5K** — 8 weeks for people who can already jog 20 minutes; long runs, then
  5K-effort intervals, then a time trial.
- **Marathon** — generated backward from race day, from three inputs: race date, the longest
  run you've done in the last four weeks, and 3–5 runs a week (long run Saturday or Sunday).
  The long run climbs ~1.5–2 mi a week with an easier week every fourth, peaks at no more
  than 20 mi, then tapers 2–3 weeks. Race day can't move, so weeks follow the calendar
  instead of repeating; the adaptive part is the cap — a long run is never more than 2 mi
  past the longest run in the last three weeks. Setup previews the plan and says plainly
  when the timeline is too short for the long run to reach 16 mi.
- **Just track** — no plan, no gate. Today becomes a weekly summary.

Coached plans are three runs a week with a rest day between; each week has to pass its
gate (3 runs, no soreness past 48 hours, HR under the guardrail) before the next unlocks.

## Tabs

- **Today** — the assignment (or this week's summary when just tracking), the soreness
  check-in, the week's gate, the next 7 days (tap a day with another sport and the runs
  move around it), today's body numbers, and the next run with the 6-step protocol.
- **Progress** — heart rate on the test route, recovery HR, anaerobic TE, then jog/walk
  time, max HR, time above threshold, load, cardiac drift.
- **Runs** — every run, and a page per run: HR trace over threshold-anchored zones with
  the jog/walk/standing strip, the protocol check, route shape, form metrics, notes.
- **Body** — weight (with a 7-day average), resting HR, HRV, sleep and VO2 max over 30
  days, 90 days or a year, filled daily from Garmin through intervals.icu, plus weigh-ins
  and body-composition entries (DEXA and the like) added by hand. A manual weigh-in wins
  over Garmin's number for the same day.
- **Plan** — the active plan's weeks, week history (the gate decides; you can override the
  last week), the rules, and switching plans.
- **Setup** — sign-in, intervals.icu, zones, manual FIT upload, backup export/import.

## Automatic import (intervals.icu)

Garmin's own API is closed to new developers and Strava's doesn't share original files,
so runs arrive through [intervals.icu](https://intervals.icu): the watch syncs to Garmin
Connect, Garmin syncs to intervals.icu, and Stride downloads each new run's original FIT
file and imports it exactly as if it had been dropped in. Set it up on Upload with an
intervals.icu API key (Settings → Developer Settings).

- Checks run when the app opens or comes back into view (at most every 5 min), or on
  *Check now*. The first check reaches back 30 days for runs and 180 days for body data
  (intervals.icu's wellness endpoint; weight arrives in kg and is stored in lbs).
- The key lives in the synced doc so every signed-in device imports. It's left out of
  backup files. What each device has already checked stays on that device, so a check
  only writes to the account when it finds a run.
- Runs already uploaded by hand are recognised by their FIT start time and skipped.
  Activities that reached intervals.icu through Strava have no original file and are
  skipped with a note.

## How the numbers are made

- **Jog / walk / standing** come from Garmin's own run/walk detection (the `rwdRun`,
  `rwdWalk`, `rwdStand` splits), so totals match Garmin Connect to the second. Where a
  file has no such splits, it falls back to smoothed cadence (≥125 spm = jogging) and speed.
- **Jogging HR** is Garmin's average over the jogging segments only, so walk breaks
  don't flatter it.
- **Recovery HR** is read from session field 202, which the FR265 writes when you stand
  still for 2 minutes after stopping the timer. It's undocumented in the FIT profile.
- **Dates** use the watch's local time from the file, not the computer's time zone.
- **Clean** = on the test route and ≤20 s standing with the timer running. Only clean
  runs feed the trend.
- **Test route** is matched by start and end within 150 m and distance within 20%.
- **Glitches** (single-sample HR, cadence and ground-contact spikes) are dropped against
  a rolling median.
- **Zones** come from the lactate threshold, not Garmin's drifting max HR. Change them
  on Upload and every run is re-scored from its samples.

## Known gaps

- Recovery HR can still be typed in by hand on a run's page, for runs where the watch
  didn't record it.
- New accounts start on placeholder zones (threshold 170) until they set their own on
  Upload; Today nags until they do, and quotes the watch's threshold if a FIT file has one.

## Sync

Optional. With `SUPABASE` filled in near the top of the script, the Upload page and the
sidebar gain a sign-in; leave it empty and the app never touches the network.

Login is an emailed link (or the code in that email) — no passwords. Each person's
data is two kinds of row, reachable only by the account that owns them:

- `stride_docs` — one row per person: runs, check-ins, zones, plan state. Writes are
  debounced 2.5 s and compare-and-set on `version`: if another device saved first, the
  write fails and you pick which copy to keep. It never guesses, and never uploads an
  empty browser over a real account.
- `stride_samples` — one row per run with the second-by-second traces. Uploaded once,
  fetched only when a run's page needs it.

If a different person signs in on the same browser, the previous person's runs are
cleared from it rather than uploaded into the new account.

### Setting it up for a new project

Run `supabase-setup.sql` in the SQL editor. Under Authentication → URL Configuration,
set the site URL and add it to the redirect URLs. Put the project URL and publishable
key into the `SUPABASE` block. Supabase's built-in email sender allows only a few
sign-in emails an hour across all users; for more than a handful of friends, add a
custom SMTP sender (Authentication → Emails → SMTP).

## Working on it

`index.html` is the whole app, and GitHub Pages serves it straight from `main`: push and
it's live. Nobody's personal data lives in the repo; it's in each person's Stride account.
On Neil's machine, `git config core.hooksPath .githooks` turns on a pre-commit check that
refuses anything containing a string from `.leakwords` (a gitignored list). `CLAUDE.md`
has the architecture and rules.
