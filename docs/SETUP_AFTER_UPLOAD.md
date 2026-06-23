# Setup After Upload

After the app is uploaded to GitHub, these are the only setup items to remember.

## Option 1 Workflow For Each User

For the current hybrid setup, each user does this:

1. Open the hosted CFMA TASKA link for normal browser use.
2. If they need Outlook desktop scanning, local attachment opening, local backups, useful documents, or the RC analyser AI proxy, download/clone the GitHub repo.
3. Double-click `Install Taska App.bat` once.
4. Open `CFMA TASKA` from the Desktop or Start Menu shortcut.

The `CFMA TASKA` shortcut starts the local server hidden and opens an app-style browser window at:

```text
http://localhost:8080/
```

No visible terminal needs to stay open for normal use.

For a proper Taska taskbar icon instead of an Edge-grouped window:

1. Double-click `Install Taska Taskbar App.bat`.
2. In the Edge tab that opens, click the app/install icon, or use `... > Apps > Install this site as an app`.
3. Name it `CFMA TASKA`.
4. Pin the Taska app window to the taskbar.
5. Unpin the old Edge-looking Taska shortcut.

That taskbar setup also creates a user Startup shortcut for the hidden local server so the pinned Taska app can open after Windows sign-in. The normal `CFMA TASKA` launcher detects the installed Taska web app and uses it automatically.

If the app icon changes later, run `Install Taska App.bat` again to refresh the Desktop and Start Menu shortcuts. The desktop updater also refreshes these shortcuts after it installs a newer copy.

## Updates

The app checks the hosted `version.json` file from `cfma-public-config.js`. If the hosted version is newer than the local copy, users see an update popup after the app starts.

On the local desktop app, the popup's `Update now` button downloads the latest GitHub source archive, replaces Taska app files, keeps local/private folders, refreshes shortcuts, and reloads the page. If the local server itself changed, close and reopen `CFMA TASKA` after the update so the hidden server uses the new script.

## Mobile App

The hosted URL can be installed on mobile as a Progressive Web App.

- On Android/Chrome, the app can show an install prompt after the user opens the hosted URL.
- On iPhone/iPad, Safari does not allow a custom one-tap install prompt, so Taska shows Add to Home Screen instructions instead.

The mobile layout hides the right sidebar and uses three bottom tabs: `Calendar`, `Today`, and `Tasks`. Calendar views open to the current day and show day-by-day cards instead of week grids so long task text is easier to read on a phone. Each weekday card has a small `+` button beside the date to add a reminder for that day, and the mobile `Tasks` tab also has an `Add Reminder` button above `+ Add Job`. It also hides desktop-only local file/server actions such as job folders, Outlook email saving/opening, Useful Documents, and the local RM analyser.

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
