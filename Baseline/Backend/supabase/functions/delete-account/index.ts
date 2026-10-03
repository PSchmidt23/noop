// Baseline Friends: account deletion (FRIENDS_SPEC.md §4.1).
//
// POST /functions/v1/delete-account with the user's JWT and an optional body {"authorizationCode": "<fresh Apple code>"}.
//   1. Verify the caller's JWT (getUser). 401 if invalid.
//   2. If a code was sent: build the ES256 client secret, exchange the code at Apple for a refresh token and revoke it,
//      so "Sign in with Apple" for Baseline disappears from the person's Apple ID. A failure here is logged and NEVER
//      blocks step 3.
//   3. ALWAYS delete the auth user (auth.admin.deleteUser), which cascades every row in public.*.
//   4. Return {deleted: true, revoked: boolean}. No Apple token is ever stored.
//
// Secrets (supabase secrets set …): APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_CLIENT_ID (= the bundle id), APPLE_PRIVATE_KEY
// (the contents of a NEW Sign in with Apple .p8 created for Baseline). SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY are injected by Supabase; the service-role key exists only here, never in the app or repo.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function appleClientSecret(): Promise<string | null> {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const clientId = Deno.env.get("APPLE_CLIENT_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!teamId || !keyId || !clientId || !privateKey) return null;
  const key = await importPKCS8(privateKey.replace(/\\n/g, "\n"), "ES256");
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt(now)
    .setExpirationTime(now + 300)
    .setAudience("https://appleid.apple.com")
    .setSubject(clientId)
    .sign(key);
}

async function revokeApple(authorizationCode: string): Promise<boolean> {
  const clientId = Deno.env.get("APPLE_CLIENT_ID");
  const secret = await appleClientSecret();
  if (!clientId || !secret) {
    console.warn("delete-account: Apple secrets not set; skipping revoke");
    return false;
  }
  const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: secret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
  });
  if (!tokenResponse.ok) {
    console.warn("delete-account: Apple token exchange failed", tokenResponse.status);
    return false;
  }
  const tokens = await tokenResponse.json();
  const refreshToken: string | undefined = tokens.refresh_token;
  if (!refreshToken) return false;
  const revokeResponse = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: secret,
      token: refreshToken,
      token_type_hint: "refresh_token",
    }),
  });
  if (!revokeResponse.ok) console.warn("delete-account: Apple revoke failed", revokeResponse.status);
  return revokeResponse.ok;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { error: "not_signed_in" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData?.user) return json(401, { error: "not_signed_in" });
  const uid = userData.user.id;

  let authorizationCode: string | undefined;
  try {
    const body = await req.json();
    if (typeof body?.authorizationCode === "string" && body.authorizationCode.length > 0) {
      authorizationCode = body.authorizationCode;
    }
  } catch {
    // An empty body is fine: delete without revoking.
  }

  let revoked = false;
  if (authorizationCode) {
    try {
      revoked = await revokeApple(authorizationCode);
    } catch (e) {
      console.warn("delete-account: revoke threw", e instanceof Error ? e.message : String(e));
      revoked = false;
    }
  }

  // ALWAYS delete, whatever happened above. Cascades profiles and every public.* row.
  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    console.error("delete-account: deleteUser failed", deleteError.message);
    return json(500, { deleted: false, revoked });
  }
  return json(200, { deleted: true, revoked });
});
