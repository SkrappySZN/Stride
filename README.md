# Stride

A running tracker in one HTML file. Drop in FIT files from the Garmin; it tells you
what to do today, whether the week passed, and whether the same pace is costing
fewer heartbeats.

**Live:** https://skrappyszn.github.io/Stride/

No build step to use it, no server of its own. FIT files are parsed in the page
(Garmin's official FIT SDK, loaded from jsDelivr on first upload) and stored in this
browser's IndexedDB. Sign in, and your runs also sync to your account.

## Tabs

- **Today** — the assignment (run / rest / ref day / get it checked), a mobility
  checklist, the soreness check-in at ~24 and ~48 hrs after the latest run, the next
  run with the 6-step protocol, this week's gate, and the next 7 days. Tap a day to
  mark a sport day (another sport, a big day on your feet); the schedule moves runs
  around them.
- **Progress** — heart rate on the test route (jogging-only when there's a FIT file),
  recovery HR, anaerobic TE, then jog/walk time, max HR, time above threshold, load,
  cardiac drift.
- **Runs** — every run, and a page per run: HR trace over threshold-anchored zones with
  the jog/walk/standing strip, the protocol check, route shape, form metrics, notes,
  and a recovery HR box.
- **Plan** — the 8-week build, week history (gate decides; you can override the last
  week), and the rules.
- **Upload** — FIT or Garmin .zip, sign-in, zones, weigh-ins, backup export/import.

`1`–`5` switch tabs.

## Automatic import (intervals.icu)

Garmin's own API is closed to new developers and Strava's doesn't share original files,
so runs arrive through [intervals.icu](https://intervals.icu): the watch syncs to Garmin
Connect, Garmin syncs to intervals.icu, and Stride downloads each new run's original FIT
file and imports it exactly as if it had been dropped in. Set it up on Upload with an
intervals.icu API key (Settings → Developer Settings).

- Checks run when the app opens or comes back into view (at most every 5 min), or on
  *Check now*. The first check reaches back 30 days.
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

`index.html` is the local copy and its `SEED` block holds personal data. The published
copy is built from it with the seed emptied:

```
python3 build.py      # index.html -> docs/index.html, SEED stripped
```

The build refuses to write an output that still contains a string from `.leakwords`,
and the pre-commit hook (`git config core.hooksPath .githooks`) blocks the same thing at
commit time. `index.html` is gitignored.
