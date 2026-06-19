# Setup After Upload

After the app is uploaded to GitHub, these are the only setup items to remember.

## Option 1 Workflow For Each User

For the current hybrid setup, each user does this:

1. Open the hosted CFMA TASKA link for normal browser use.
2. If they need Outlook desktop scanning, local attachment opening, local backups, useful documents, or the RC analyser AI proxy, download/clone the GitHub repo.
3. Double-click `Install Taska App.bat` once.
4. Open `CFMA TASKA` from the Desktop or Start Menu shortcut.
5. To pin it, open Start, search `CFMA TASKA`, right-click it, then choose `Pin to taskbar`.

The `CFMA TASKA` shortcut starts the local server hidden and opens:

```text
http://localhost:8080/
```

No visible terminal needs to stay open for normal use.

If the app icon changes later, run `Install Taska App.bat` again to refresh the Desktop and Start Menu shortcuts.

## Updates

The app checks the hosted `version.json` file from `cfma-public-config.js`. If the hosted version is newer than the local copy, users see an update popup after the app starts.

For most bug fixes, users only need to sync or replace the local `Taska` folder and reopen `CFMA TASKA`. They only need to run `Install Taska App.bat` again when shortcut/launcher/icon files change.

## Mobile App

The hosted URL can be installed on mobile as a Progressive Web App.

- On Android/Chrome, the app can show an install prompt after the user opens the hosted URL.
- On iPhone/iPad, Safari does not allow a custom one-tap install prompt, so Taska shows Add to Home Screen instructions instead.

The mobile layout hides the right sidebar and uses two bottom tabs: `Calendar` and `Tasks`.

Supabase handles shared users, autosave snapshots, jobs, tasks, and work calendars. The hidden local server only handles local desktop access that the browser and Supabase cannot access directly.

Local/private folders such as `Backups/`, `Job Emails/`, `RM Sessions/`, and `Useful Documents/` are stored beside `Start Server.bat` by default. They are ignored by Git through `.gitignore`, so GitHub Desktop should not try to push them.

For troubleshooting, use `Start Server.bat` instead of the shortcut so the server window is visible. Use `Stop Taska Server.bat` to stop the hidden server before restarting it.

## GitHub Pages

Use these settings:

```text
Source: Deploy from a branch
Branch: main
Folder: /root
```

`index.html` redirects to `surveyors-toolbox.html`, so the app opens correctly from GitHub Pages.

## Supabase Team Sync

1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL editor.
3. Open CFMA TASKA.
4. Click `Team Sync`.
5. Enter the Supabase project URL, anon/public key, workspace id, and your name.

If `cfma-public-config.js` has the Supabase project URL, publishable key, and workspace id filled in, users only need to enter their display name when they click `Team Sync`.

Important: the current Supabase schema is fine for a private prototype. Before public real-world use, it should be locked down with Supabase Auth and stricter Row Level Security.

## Login

Run `supabase/schema.sql`, then follow `docs/LOGIN_SETUP.md` to create the first owner login.

After the first owner exists, use `Add User` in the app to create new users and their logins.

## Gmail

Gmail is optional per user.

If a user wants Gmail scanning:

1. Create a Google Apps Script project.
2. Copy in `gmail-scanner-apps-script.js`.
3. Use `gmail-scanner-appsscript-manifest.json` as the manifest settings.
4. Deploy as a web app.
5. Paste the deployment URL into the Gmail tab in CFMA TASKA.

If `Invalid Gmail scanner token` appears, re-save the latest Apps Script deployment URL/token in the Gmail tab.

## Local Features

These features still need the local server running:

```text
Outlook desktop scanning
Opening local Outlook attachments
Local backup writing
Local PowerShell AI helper endpoints
```

When users launch from the `CFMA TASKA` shortcut, that local server is started hidden automatically, so they do not need to keep a terminal window open.
