
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));

self.addEventListener('push',event=>{
  let data={};
  try{data=event.data?event.data.json():{}}catch(e){data={body:event.data?.text()||''}}
  const title=data.title||'AI 프로세스 VIP';
  event.waitUntil(self.registration.showNotification(title,{
    body:data.body||'새 알림이 도착했습니다.',
    tag:data.tag||('vip-'+(data.id||Date.now())),
    data:{url:data.target_url||data.url||'vip/index.html',notificationId:data.id||null}
  }));
});

self.addEventListener('notificationclick',event=>{
  event.notification.close();
  const rel=event.notification.data?.url||'vip/index.html';
  const target=new URL(rel,self.registration.scope).href;
  event.waitUntil((async()=>{
    const list=await clients.matchAll({type:'window',includeUncontrolled:true});
    for(const c of list){
      if(new URL(c.url).origin===new URL(target).origin){
        try{await c.navigate(target)}catch(e){}
        return c.focus();
      }
    }
    return clients.openWindow(target);
  })());
});
