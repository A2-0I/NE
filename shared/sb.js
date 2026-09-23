(function () {
  window.aiProcessor = window.aiProcessor || {};

  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    console.error('[AI PROCESSOR] supabase-js not loaded. Include supabase.min.js before shared/sb.js');
    return;
  }

  const url = window.AI_PROCESSOR_SUPABASE_URL;
  const key = window.AI_PROCESSOR_SUPABASE_ANON_KEY;

  if (!url || !key) {
    console.error('[AI PROCESSOR] Missing AI_PROCESSOR_SUPABASE_URL / AI_PROCESSOR_SUPABASE_ANON_KEY in shared/config.js');
    return;
  }

  const client = window.supabase.createClient(url, key, {
    auth: { persistSession: false },
    realtime: { params: { eventsPerSecond: 10 } },
  });

  window.aiProcessor.sb = function () {
    return client;
  };

  console.log('[AI PROCESSOR] Supabase client ready:', url);
})();
