import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/supabase/config";

/** Keeps the Supabase auth session fresh. No-op when Supabase isn't configured. */
export async function middleware(request: NextRequest) {
  const url = SUPABASE_URL;
  const key = SUPABASE_ANON_KEY;
  let response = NextResponse.next({ request });
  if (!url || !key) return response;

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (list) => {
        for (const { name, value } of list) request.cookies.set(name, value);
        response = NextResponse.next({ request });
        for (const { name, value, options } of list) response.cookies.set(name, value, options);
      },
    },
  });
  // If Supabase didn't accept our /auth/callback redirect URL it falls back to
  // the Site URL, so the sign-in code can land on any page. Finish it here.
  const code = request.nextUrl.searchParams.get("code");
  if (code && !request.nextUrl.pathname.startsWith("/auth/") && !request.nextUrl.pathname.startsWith("/api/")) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    const target = request.nextUrl.clone();
    target.searchParams.delete("code");
    if (error) {
      target.pathname = "/login";
      target.search = `?error=${encodeURIComponent(error.message)}`;
    }
    const redirect = NextResponse.redirect(target);
    for (const c of response.cookies.getAll()) redirect.cookies.set(c);
    return redirect;
  }

  await supabase.auth.getUser();
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|api/cron|.*\\.(?:png|jpg|jpeg|svg|webp)$).*)"],
};
