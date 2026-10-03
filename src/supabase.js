import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL || "";
const key = import.meta.env.VITE_SUPABASE_ANON_KEY || "";

export const supabaseConfigured = Boolean(url && key);
export const supabase = supabaseConfigured
  ? createClient(url, key, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    })
  : null;

export async function getMembership(userId) {
  if (!supabase || !userId) return { membership: null, error: new Error("Supabase belum dikonfigurasi.") };
  const { data, error } = await supabase
    .from("memberships")
    .select("business_id,role,businesses(id,name)")
    .eq("user_id", userId)
    .limit(1)
    .maybeSingle();

  if (error) return { membership: null, error };
  return { membership: data || null, error: null };
}

export async function getActiveOutlet(businessId) {
  if (!supabase || !businessId) return { outlet: null, error: new Error("Business belum tersedia.") };
  const { data, error } = await supabase
    .from("outlets")
    .select("id,name,code,address")
    .eq("business_id", businessId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  return { outlet: data || null, error };
}
