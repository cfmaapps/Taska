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
  supabase: {
    url: 'https://yuacwrehzltupcwiucoc.supabase.co',
    publishableKey: 'sb_publishable_xJiw1uj3RfQL9tPttB8KYQ_pYXdqU1Z',
    workspaceId: 'cfma',
    autoLoad: true
  }
};
