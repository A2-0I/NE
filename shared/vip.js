
(function(){
  window.AIVIP = window.AIVIP || {};
  const A = window.AIVIP;
  A.avatars = ["🐱", "🐶", "🐰", "🐹", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🦄", "🐔", "🐧", "🐦", "🐤", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦓", "🦒", "🐘", "🦏", "🦛", "🐭", "🐿️", "🦔", "🦦", "🦥", "🐇", "🦝", "🦨", "🐢", "🐳", "🐬", "🦭", "🐟", "🐠", "🐡", "🦈", "🐙", "🦑", "🦀", "🦞", "🦐", "🐚", "🍎", "🍓", "🍒", "🍑", "🍊", "🍋", "🍉", "🍇", "🥝", "🍍", "🥑", "🍔", "🍕", "🍩", "🍪", "🍰", "🧁", "🍮", "🍯", "☕", "🤖", "👑", "💎", "🎧", "📷", "🎮", "🧸", "🎲", "🎯", "🏆", "⚽", "🏀", "🚀", "🛸", "🌙", "⭐", "☀️", "☁️", "🌈", "🔥", "🍀", "🌵", "🌲", "🌻", "🎁", "💡", "⌚"];
  A.sb = function() {
    return (window.aiProcessor && typeof window.aiProcessor.sb === 'function')
      ? window.aiProcessor.sb() : null;
  };
  A.user = function() {
    try { return JSON.parse(localStorage.getItem('ai_processor_current_user') || 'null'); }
    catch(e) { return null; }
  };
  A.admin = function() {
    if(localStorage.getItem('ai_processor_admin_login') !== 'true') return null;
    try { return JSON.parse(localStorage.getItem('ai_processor_admin') || 'null') || {role:'admin'}; }
    catch(e) { return {role:'admin'}; }
  };
  A.requireUser = function() {
    const u=A.user();
    if(!u){ location.href='../user/index.html'; return null; }
    return u;
  };
  A.requireAdmin = function() {
    const a=A.admin();
    if(!a){ location.href='login.html'; return null; }
    return a;
  };
  A.money = n => Number(n||0).toLocaleString('ko-KR')+' 원';
  A.escape = v => String(v??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  A.time = function(v) {
    if(!v)return '-'; const d=new Date(v); if(Number.isNaN(d.getTime()))return '-';
    const p=new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false}).formatToParts(d);
    const g=t=>p.find(x=>x.type===t)?.value||'';
    return `${g('month')}.${g('day')} ${g('hour')}:${g('minute')}`;
  };
  A.date = function(v) {
    if(!v)return '-'; const d=new Date(v); if(Number.isNaN(d.getTime()))return '-';
    return new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(d);
  };
  A.ensureProfile = async function(user) {
    const sb=A.sb(); if(!sb||!user)return null;
    let {data,error}=await sb.from('vip_profiles').select('*').eq('user_id',user.id).maybeSingle();
    if(error) throw error;
    if(data) return data;
    const payload={user_id:user.id,nickname:user.name||user.username||'VIP',avatar_key:'🐼'};
    const res=await sb.from('vip_profiles').insert(payload).select('*').single();
    if(res.error) throw res.error; return res.data;
  };
  A.uploadImage = async function(file, folder) {
    const sb=A.sb(); if(!file) return null;
    if(!/^image\//.test(file.type)) throw new Error('이미지 파일만 첨부할 수 있습니다.');
    if(file.size > 8*1024*1024) throw new Error('사진은 8MB 이하만 첨부할 수 있습니다.');
    const ext=(file.name.split('.').pop()||'jpg').replace(/[^a-zA-Z0-9]/g,'').slice(0,6) || 'jpg';
    const path=`${folder||'chat'}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
    const up=await sb.storage.from('vip-media').upload(path,file,{cacheControl:'3600',upsert:false,contentType:file.type});
    if(up.error) throw up.error;
    const pub=sb.storage.from('vip-media').getPublicUrl(path);
    return pub.data.publicUrl;
  };
  A.avatar = function(profile, cls='vip-avatar') {
    return `<div class="${cls}">${A.escape(profile?.avatar_key||'🐼')}</div>`;
  };
})();
