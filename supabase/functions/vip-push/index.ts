import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-vip-push-secret",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const secret = Deno.env.get("VIP_PUSH_HOOK_SECRET") ?? "";
  if (!secret || req.headers.get("x-vip-push-secret") !== secret) {
    return new Response("unauthorized", { status: 401, headers: cors });
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const vapidPublic = Deno.env.get("VAPID_PUBLIC_KEY")!;
  const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY")!;
  const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@example.com";

  webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);
  const supabase = createClient(url, serviceKey);

  const body = await req.json();
  const row = body.record ?? body;
  if (!row?.id || !row?.target_role) {
    return new Response("missing notification record", { status: 400, headers: cors });
  }

  let q = supabase.from("vip_push_subscriptions")
    .select("*")
    .eq("enabled", true)
    .eq("target_role", row.target_role);

  if (row.target_role === "user") q = q.eq("target_user_id", row.target_user_id);

  const { data: subs, error } = await q;
  if (error) return new Response(error.message, { status: 500, headers: cors });

  const payload = JSON.stringify({
    id: row.id,
    title: row.title,
    body: row.body,
    target_url: row.target_url || "vip/index.html",
    tag: "vip-" + row.id,
  });

  const results = await Promise.allSettled((subs ?? []).map(async (s) => {
    try {
      await webpush.sendNotification({
        endpoint: s.endpoint,
        keys: { p256dh: s.p256dh, auth: s.auth },
      }, payload);
    } catch (e) {
      const status = (e as any)?.statusCode;
      if (status === 404 || status === 410) {
        await supabase.from("vip_push_subscriptions")
          .update({ enabled: false })
          .eq("id", s.id);
      }
      throw e;
    }
  }));

  const sent = results.filter(r => r.status === "fulfilled").length;
  return new Response(JSON.stringify({ ok: true, sent, total: results.length }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
