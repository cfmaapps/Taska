# CFMA TASKA

CFMA TASKA is a single-page work calendar and task briefing app for CFMA jobs.
The visible in-app title is **CFMA JOB**.

It currently supports:

- Tasks To Do and your work calendar
- Supabase-backed username/password login
- Logged work blocks with hours
- Outlook local scan through the PowerShell helper
- Gmail date extraction through Google Apps Script
- Optional Supabase Team Sync so users in the same organisation workspace can see each other's work calendars

## Local Use

For normal desktop-style use:

1. Double-click `Install Taska App.bat` once.
2. Open `CFMA TASKA` from the Desktop or Start Menu shortcut.
3. Pin `CFMA TASKA` to the taskbar from the Start Menu if desired.

The shortcut starts the local server hidden, then opens `http://localhost:8080/` in an app-style browser window.

For troubleshooting, open `Start Server.bat` instead. That keeps the server window visible so errors can be read.

The app stores working data in browser `localStorage` and writes local JSON backups through `server.ps1`.
Local/private files are saved beside `Start Server.bat` by default and protected from Git by `.gitignore`.

## GitHub Hosting

This repo includes `index.html`, which redirects to `surveyors-toolbox.html` for GitHub Pages.

For the exact upload list, start with `docs/UPLOAD_TO_GITHUB.md`.

Before pushing:

- Do not commit `.timewrap-secrets.json`.
- Do not commit `Job Emails/`, `Backups/`, `RM Sessions/`, or private documents.
- Use the included `.gitignore`.

Useful checks:

```bash
npm run verify
```

## Supabase Team Sync

1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL editor.
3. Create the first owner login using `docs/LOGIN_SETUP.md`.
4. Host the static app.
5. In the app, click `Team Sync`.
6. Paste:
   - Supabase project URL
   - Supabase anon/public key
   - shared workspace id, for example `cfma`
   - your display name

Each user syncs their own snapshot. Other users in the same workspace appear under **Shared Work Calendars**.

To create a user from the organisation, sign in as an owner/admin and click `Add User`. This creates both an organisation user and a login account.

## Gmail Setup

Gmail is optional per user. In the Gmail tab, the app shows setup instructions when Gmail is not connected.

Files involved:

- `gmail-scanner-apps-script.js`
- `gmail-scanner-appsscript-manifest.json`
- `gmail-analysis-core.js`

The Apps Script requires Gmail read-only permission.

## Security Note

The included Supabase policies are intentionally permissive for a private prototype using a static page and anon key. Before public production use, replace this with Supabase Auth and Row Level Security policies that check authenticated organisation membership.

## Main Files

- `surveyors-toolbox.html` - main app
- `assets/cfma-taska-icon.*` - app icon for shortcuts, browser tabs, and pinned taskbar use
- `manifest.webmanifest` / `service-worker.js` - mobile installable app shell
- `cfma-public-config.js` - public deployment defaults for Team Sync
- `version.json` - hosted version manifest used for update notifications and desktop update downloads
- `server.ps1` - local helper server
- `Open Taska.bat` / `Open Taska.ps1` - app-style hidden-server launcher
- `Install Taska App.bat` / `Install Taska App.ps1` - creates Desktop and Start Menu shortcuts
- `Stop Taska Server.bat` / `Stop Taska Server.ps1` - stops the hidden local server for restart/troubleshooting
- `gmail-analysis-core.js` - deterministic Gmail analysis
- `gmail-analysis-tests.js` - fixtures/tests
- `supabase/schema.sql` - Team Sync schema
