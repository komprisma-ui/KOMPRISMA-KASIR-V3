import { createClient } from "@supabase/supabase-js";

const json = (status, body) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json", "Cache-Control": "no-store" }
});

export default async function handler(request) {
  if (request.method !== "POST") return json(405, { error: "Method not allowed." });
  const url = process.env.VITE_SUPABASE_URL;
  const anonKey = process.env.VITE_SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anonKey || !serviceKey) return json(503, { error: "Fitur undangan belum aktif. Konfigurasikan SUPABASE_SERVICE_ROLE_KEY pada environment server Vercel." });

  const authHeader = request.headers.get("authorization") || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json(401, { error: "Sesi login diperlukan." });

  let body;
  try { body = await request.json(); } catch { return json(400, { error: "Format permintaan tidak valid." }); }
  const email = String(body.email || "").trim().toLowerCase();
  const password = String(body.password || "");
  const role = String(body.role || "cashier");
  const businessId = String(body.businessId || "");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(400, { error: "Email tidak valid." });
  if (password.length < 12) return json(400, { error: "Kata sandi awal minimal 12 karakter." });
  if (!businessId) return json(400, { error: "Bisnis aktif tidak ditemukan." });
  if (!["manager", "cashier", "warehouse", "staff"].includes(role)) return json(400, { error: "Peran tidak diizinkan." });

  const authClient = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: callerData, error: callerError } = await authClient.auth.getUser(token);
  if (callerError || !callerData?.user?.id) return json(401, { error: "Sesi login tidak valid atau sudah kedaluwarsa." });

  const { data: membership, error: membershipError } = await admin.from("memberships")
    .select("role,business_id").eq("business_id", businessId).eq("user_id", callerData.user.id).maybeSingle();
  if (membershipError) return json(500, { error: "Gagal memeriksa hak akses pengelola." });
  if (!membership || membership.role !== "owner") return json(403, { error: "Hanya owner bisnis yang boleh menambahkan pengguna." });

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { invited_by: callerData.user.id }
  });
  if (createError) return json(400, { error: createError.message });

  const { error: insertError } = await admin.from("memberships").insert({
    business_id: businessId, user_id: created.user.id, role
  });
  if (insertError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return json(500, { error: "Akun tidak dapat ditautkan ke bisnis; pembuatan akun dibatalkan. " + insertError.message });
  }
  return json(201, { ok: true, user: { id: created.user.id, email: created.user.email, role } });
}
