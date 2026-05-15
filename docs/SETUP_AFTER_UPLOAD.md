# Setup After Upload

After the app is uploaded to GitHub, these are the only setup items to remember.

## Option 1 Workflow For Each User

For the current hybrid setup, each user does this:

1. Open the hosted CFMA TASKA link for normal browser use.
2. If they need Outlook desktop scanning, local attachment opening, or local backups, download/clone the GitHub repo.
3. Double-click `Start Server.bat` on their own Windows computer.
4. Open:

```text
http://localhost:8080/
```

5. Keep the `.bat`/PowerShell window open while using local Outlook or file features.

Supabase handles shared users, autosave snapshots, jobs, tasks, and work calendars. The `.bat` only handles local desktop access that the browser and Supabase cannot access directly.

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

These features still need `Start Server.bat` running locally:

```text
Outlook desktop scanning
Opening local Outlook attachments
Local backup writing
Local PowerShell AI helper endpoints
```
