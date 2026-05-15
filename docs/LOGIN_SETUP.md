# Login Setup

CFMA TASKA now has a Supabase-backed login screen.

Do not put passwords in GitHub, `surveyors-toolbox.html`, or `cfma-public-config.js`.

## 1. Run The Schema

In Supabase:

```text
SQL Editor -> run supabase/schema.sql
```

This creates the login tables and functions.

## 2. Create The First Owner Login

After running the schema, create the first owner login from the Supabase SQL editor:

```sql
select public.cfma_taska_bootstrap_owner(
  'cfma',
  'lachlan',
  'REPLACE_WITH_OWNER_PASSWORD',
  'Lachlan'
);
```

Replace `REPLACE_WITH_OWNER_PASSWORD` with the owner password when you run the command. Do not save that password in the repo.

The bootstrap function only works while the workspace has no existing login. After the first owner exists, new users should be created from inside the app.

## 3. User Workflow

Users open the CFMA TASKA URL and sign in with:

```text
username
password
```

Once signed in, their user id, display name, role, and session token are saved in that browser.

## 4. Creating New Users

Sign in as an owner or admin, then click `Add User`.

The app asks for:

```text
display name
email
role
username
temporary password
```

It creates both:

```text
organisation user
login account
```

Give the new user the app URL, username, and temporary password.

