// CFMA TASKA public deployment config.
//
// Only browser-safe values belong here:
// - Supabase project URL
// - Supabase publishable/anon key
// - Workspace id
//
// Never put a Supabase secret key or service role key in this file.
window.CFMA_TASKA_CONFIG = {
  appUrl: 'https://cfmaapps.github.io/Taska/',
  appVersion: '2026.06.23.02',
  updateCheckUrl: 'https://cfmaapps.github.io/Taska/version.json',
  downloadUrl: 'https://github.com/cfmaapps/Taska',
  desktopUpdateUrl: 'https://github.com/cfmaapps/Taska/archive/refs/heads/main.zip',
  aiKeyOwner: 'Lachlan',
  supabase: {
    url: 'https://yuacwrehzltupcwiucoc.supabase.co',
    publishableKey: 'sb_publishable_xJiw1uj3RfQL9tPttB8KYQ_pYXdqU1Z',
    workspaceId: 'cfma',
    autoLoad: true
  }
};
