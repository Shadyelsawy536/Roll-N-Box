import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json(401, { error: "سجّل الدخول أولًا." });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json(500, { error: "إعدادات خدمة الدعوات غير مكتملة على الخادم." });
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userResult, error: userError } = await callerClient.auth.getUser();
  const caller = userResult.user;
  if (userError || !caller) return json(401, { error: "انتهت الجلسة؛ سجّل الدخول مجددًا." });

  let payload: { email?: unknown };
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "بيانات الدعوة غير صحيحة." });
  }

  const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : "";
  const emailParts = email.split("@");
  if (emailParts.length !== 2 || !emailParts[0] || !emailParts[1].includes(".")) {
    return json(400, { error: "اكتب بريدًا إلكترونيًا صحيحًا." });
  }
  if (email === (caller.email ?? "").toLowerCase()) {
    return json(400, { error: "لا يمكنك إرسال دعوة إلى بريد حسابك الحالي." });
  }

  const { data: membership, error: membershipError } = await admin
    .from("workspace_memberships")
    .select("workspace_owner_id")
    .eq("user_id", caller.id)
    .maybeSingle();

  if (membershipError || !membership) {
    return json(403, { error: "حسابك غير مرتبط بنشاط مصرح له بإرسال الدعوات." });
  }

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo: "https://shadyelsawy536.github.io/inv-management/",
    data: { pack_master_password_setup: true },
  });
  if (inviteError || !invited.user) {
    return json(400, {
      error: inviteError?.message ?? "تعذر إنشاء حساب للمستخدم المدعو. تأكد أن البريد غير مسجل بالفعل.",
    });
  }

  const { error: insertError } = await admin.from("workspace_memberships").insert({
    user_id: invited.user.id,
    workspace_owner_id: membership.workspace_owner_id,
    invited_by: caller.id,
    invited_email: email,
  });

  if (insertError) {
    await admin.auth.admin.deleteUser(invited.user.id);
    return json(500, { error: "تم إلغاء الدعوة بسبب تعذر ربط الحساب بالنشاط. حاول مرة أخرى." });
  }

  return json(200, { success: true, email });
});
