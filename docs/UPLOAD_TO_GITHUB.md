# Upload This To GitHub

Upload these files and folders to GitHub:

```text
.gitignore
README.md
index.html
package.json
cfma-public-config.js
version.json
manifest.webmanifest
service-worker.js
server.ps1
Start Server.bat
Open Taska.bat
Open Taska.ps1
Install Taska App.bat
Install Taska App.ps1
Stop Taska Server.bat
Stop Taska Server.ps1
surveyors-toolbox.html
gmail-analysis-core.js
gmail-analysis-tests.js
gmail-scanner-apps-script.js
gmail-scanner-appsscript-manifest.json
assets/
supabase/
docs/
```

That is the full app source for CFMA TASKA.

## Do Not Upload

Do not upload these:

```text
.timewrap-secrets.json
.env
.env.*
cfma-secret-config.js
Backups/
Job Emails/
RM Sessions/
Useful Documents/
node_modules/
*.log
*.tmp
*.bak
```

These are private, local, generated, or machine-specific files.

When running locally, `server.ps1` keeps these folders beside `Start Server.bat` by default. They are private/local files and are excluded by `.gitignore`.

## Easy Check

Before pushing, run:

```powershell
git status --short
```

Anything you commit should be from the upload list above.

## Suggested First Commit

```powershell
git add .gitignore README.md index.html package.json cfma-public-config.js version.json manifest.webmanifest service-worker.js server.ps1 "Start Server.bat" "Open Taska.bat" "Open Taska.ps1" "Install Taska App.bat" "Install Taska App.ps1" "Stop Taska Server.bat" "Stop Taska Server.ps1" surveyors-toolbox.html gmail-analysis-core.js gmail-analysis-tests.js gmail-scanner-apps-script.js gmail-scanner-appsscript-manifest.json assets supabase docs
git commit -m "Prepare CFMA TASKA for GitHub"
```
