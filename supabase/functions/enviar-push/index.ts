// Envía por FCM (HTTP v1) las notificaciones recién insertadas.
// Secretos: FCM_SERVICE_ACCOUNT (JSON de la cuenta de servicio de Firebase),
// PUSH_WEBHOOK_SECRET (el mismo que en Vault). SUPABASE_URL y
// SUPABASE_SERVICE_ROLE_KEY ya los inyecta Supabase.
import { createClient } from "npm:@supabase/supabase-js@2";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
const secreto = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const b64url = (b: ArrayBuffer | string) => {
  const bytes = typeof b === "string" ? new TextEncoder().encode(b) : new Uint8Array(b);
  let s = "";
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

let cache: { token: string; exp: number } | null = null;
async function accessToken(): Promise<string> {
  const ahora = Math.floor(Date.now() / 1000);
  if (cache && cache.exp - 60 > ahora) return cache.token;
  const pem = (sa.private_key as string)
    .replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const cab = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const cuerpo = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: ahora,
    exp: ahora + 3600,
  }));
  const firma = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${cab}.${cuerpo}`));
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${cab}.${cuerpo}.${b64url(firma)}`,
    }),
  });
  if (!r.ok) throw new Error(`OAuth ${r.status}: ${await r.text()}`);
  const j = await r.json();
  cache = { token: j.access_token, exp: ahora + (j.expires_in ?? 3600) };
  return cache.token;
}

Deno.serve(async (req) => {
  if (req.method !== "POST" || !secreto || req.headers.get("x-push-secret") !== secreto) {
    return new Response("no autorizado", { status: 401 });
  }
  const { ids } = await req.json().catch(() => ({ ids: [] }));
  if (!Array.isArray(ids) || ids.length === 0) return Response.json({ enviados: 0 });

  const { data: notifs, error } = await db
    .from("notificaciones")
    .select("id, id_usuario, tipo, titulo, cuerpo, datos")
    .in("id", ids.slice(0, 500));
  if (error) return new Response(error.message, { status: 500 });
  if (!notifs?.length) return Response.json({ enviados: 0 });

  const usuarios = [...new Set(notifs.map((n) => n.id_usuario))];
  const { data: disp } = await db
    .from("dispositivos_push").select("token, id_usuario").in("id_usuario", usuarios);
  const porUsuario = new Map<string, string[]>();
  for (const d of disp ?? []) {
    porUsuario.set(d.id_usuario, [...(porUsuario.get(d.id_usuario) ?? []), d.token]);
  }

  const bearer = await accessToken();
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  const muertos: string[] = [];
  let enviados = 0;

  const trabajos: Promise<void>[] = [];
  for (const n of notifs) {
    for (const token of porUsuario.get(n.id_usuario) ?? []) {
      trabajos.push((async () => {
        const r = await fetch(url, {
          method: "POST",
          headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: n.titulo, body: n.cuerpo ?? "" },
              data: {
                id: n.id,
                tipo: String(n.tipo),
                datos: JSON.stringify(n.datos ?? {}),
              },
              android: {
                priority: "HIGH",
                notification: { channel_id: "tianguia_avisos" },
              },
            },
          }),
        });
        if (r.ok) { enviados++; return; }
        const t = await r.text();
        if (r.status === 404 || t.includes("UNREGISTERED")) muertos.push(token);
        else console.error("FCM", r.status, t);
      })());
    }
  }
  await Promise.all(trabajos);

  if (muertos.length) await db.from("dispositivos_push").delete().in("token", muertos);
  return Response.json({ enviados, tokens_retirados: muertos.length });
});
