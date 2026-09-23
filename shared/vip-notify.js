
(function(){
  window.AIVIPNotify = window.AIVIPNotify || {};
  const N=window.AIVIPNotify;
  let started=false, channel=null, timer=null, actor=null, sb=null, profile=null;
  let seen=new Set(), lastPoll=new Date(Date.now()-15000).toISOString(), audioCtx=null;

  function currentActor(){
    const admin = localStorage.getItem('ai_processor_admin_login')==='true';
    if(admin) return {role:'admin',userId:null};
    try{
      const u=JSON.parse(localStorage.getItem('ai_processor_current_user')||'null');
      if(u?.id) return {role:'user',userId:u.id};
    }catch(e){}
    return null;
  }
  async function regSW(){
    if(!('serviceWorker' in navigator)) return null;
    try{return await navigator.serviceWorker.register('../sw.js?v=20260923-1',{scope:'../'});}
    catch(e){console.warn('[VIP] service worker',e);return null}
  }
  function shouldHandle(row){
    if(!actor||!row||row.target_role!==actor.role)return false;
    if(actor.role==='user' && row.target_user_id!==actor.userId)return false;
    if(actor.role==='user' && profile){
      if((row.type==='event'||row.type==='broadcast') && profile.notify_events===false)return false;
      if(row.type==='support' && profile.notify_support===false)return false;
    }
    return true;
  }
  function beep(type){
    if(actor?.role!=='admin' || type!=='support')return;
    if(localStorage.getItem('vip_sound_enabled')!=='true')return;
    try{
      audioCtx=audioCtx||new (window.AudioContext||window.webkitAudioContext)();
      if(audioCtx.state==='suspended')audioCtx.resume();
      [0,0.22].forEach((delay,idx)=>{
        const o=audioCtx.createOscillator(),g=audioCtx.createGain();
        o.frequency.value=idx?880:740;g.gain.value=.06;
        o.connect(g);g.connect(audioCtx.destination);
        const t=audioCtx.currentTime+delay;o.start(t);o.stop(t+.14);
      });
    }catch(e){}
  }
  async function show(row){
    if(!shouldHandle(row)||seen.has(row.id))return;
    seen.add(row.id); if(seen.size>300)seen=new Set([...seen].slice(-150));
    beep(row.type);
    window.dispatchEvent(new CustomEvent('vip-notification',{detail:row}));
    if(Notification.permission!=='granted')return;
    const r=await navigator.serviceWorker.ready.catch(()=>null);
    if(!r)return;
    await r.showNotification(row.title||'AI 프로세스 VIP',{
      body:row.body||'새 알림이 도착했습니다.',
      tag:'vip-'+row.id,
      renotify:false,
      icon:'../assets/favicon.svg',
      badge:'../assets/favicon.svg',
      data:{url:row.target_url||'vip/index.html',notificationId:row.id}
    }).catch(()=>{});
  }
  async function poll(){
    if(!sb||!actor)return;
    let q=sb.from('vip_notifications').select('*').eq('target_role',actor.role).gt('created_at',lastPoll).order('created_at',{ascending:true}).limit(100);
    if(actor.role==='user')q=q.eq('target_user_id',actor.userId);
    const {data,error}=await q;
    if(error){console.warn('[VIP notify poll]',error);return}
    const rows=data||[]; for(const r of rows)await show(r);
    if(rows.length)lastPoll=rows[rows.length-1].created_at;
  }
  function subscribe(){
    if(!sb?.channel)return;
    channel=sb.channel('vip-global-notify-'+actor.role+'-'+(actor.userId||'admin'))
      .on('postgres_changes',{event:'INSERT',schema:'public',table:'vip_notifications'},p=>show(p.new))
      .subscribe();
  }
  function b64ToUint8(s){
    const pad='='.repeat((4-s.length%4)%4),b64=(s+pad).replace(/-/g,'+').replace(/_/g,'/');
    const raw=atob(b64);return Uint8Array.from([...raw].map(c=>c.charCodeAt(0)));
  }
  async function ensurePushSubscription(){
    const key=window.AI_PROCESS_VAPID_PUBLIC_KEY||'';
    if(!key||Notification.permission!=='granted'||!('PushManager' in window))return;
    const reg=await navigator.serviceWorker.ready;
    let sub=await reg.pushManager.getSubscription();
    if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:b64ToUint8(key)});
    const j=sub.toJSON();
    const payload={
      endpoint:j.endpoint,p256dh:j.keys?.p256dh||'',auth:j.keys?.auth||'',
      target_role:actor.role,target_user_id:actor.userId,user_agent:navigator.userAgent,enabled:true
    };
    await sb.from('vip_push_subscriptions').upsert(payload,{onConflict:'endpoint'});
  }
  N.requestPermission=async function(){
    await regSW();
    if(!('Notification' in window))return 'unsupported';
    const p=await Notification.requestPermission();
    if(p==='granted')await ensurePushSubscription().catch(console.warn);
    return p;
  };
  N.enableSound=function(){
    localStorage.setItem('vip_sound_enabled','true');
    try{audioCtx=audioCtx||new (window.AudioContext||window.webkitAudioContext)();audioCtx.resume();}catch(e){}
  };
  N.start=async function(){
    if(started)return; actor=currentActor(); if(!actor)return;
    sb=(window.aiProcessor&&typeof window.aiProcessor.sb==='function')?window.aiProcessor.sb():null;
    if(!sb)return; started=true; await regSW();
    if(actor.role==='user'){
      const r=await sb.from('vip_profiles').select('notify_events,notify_support').eq('user_id',actor.userId).maybeSingle();
      profile=r.data||null;
    }
    subscribe(); await poll(); timer=setInterval(poll,30000);
    if(Notification.permission==='granted')ensurePushSubscription().catch(()=>{});
  };
  window.addEventListener('click',()=>{if(localStorage.getItem('vip_sound_enabled')==='true'&&audioCtx?.state==='suspended')audioCtx.resume().catch(()=>{})},{once:false});
  document.addEventListener('DOMContentLoaded',()=>N.start().catch(console.warn));
})();
