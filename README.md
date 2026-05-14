# CFMA TASKA

CFMA TASKA is a single-page work calendar and task briefing app for CFMA jobs.
The visible in-app title is **CFMA JOB**.

It currently supports:

- Tasks To Do and your work calendar
- Logged work blocks with hours
- Outlook local scan through the PowerShell helper
- Gmail date extraction through Google Apps Script
- Optional Supabase Team Sync so users in the same organisation workspace can see each other's work calendars

## Local Use

1. Open `Start Server.bat`.
2. Open `http://localhost:8080/`.
3. Keep the server window open for Outlook, Gmail proxy, local backups, and file-opening features.

The app stores working data in browser `localStorage` and also writes local JSON backups through `server.ps1`.

## GitHub Hosting

This repo includes `index.html`, which redirects to `surveyors-toolbox.html` for GitHub Pages.

For the exact upload list, start with `docs/UPLOAD_TO_GITHUB.md`.

Before pushing:

- Do not commit `.timewrap-secrets.json`.
- Do not commit `Job Emails/`, `Backups/`, or private documents.
- Use the included `.gitignore`.

Useful checks:

```bash
npm run verify
```

## Supabase Team Sync

1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL editor.
3. Host the static app.
4. In the app, click `Team Sync`.
5. Paste:
   - Supabase project URL
   - Supabase anon/public key
   - shared workspace id, for example `cfma`
   - your display name

Each user syncs their own snapshot. Other users in the same workspace appear under **Shared Work Calendars**.

To create a user from the organisation, click `Add User`. This creates a row in `timewrap_org_users` and returns an invite code/user id for manual onboarding.

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
- `server.ps1` - local helper server
- `gmail-analysis-core.js` - deterministic Gmail analysis
- `gmail-analysis-tests.js` - fixtures/tests
- `supabase/schema.sql` - Team Sync schema
