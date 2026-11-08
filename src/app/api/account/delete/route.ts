import { NextResponse } from "next/server";
import { getAdminSupabase, getRequestUser } from "@/lib/supabase/server";

/**
 * Delete the signed-in account and everything in it (Apple requires apps with sign-in to offer
 * this). Every table that holds a user's data references the account with `on delete cascade`,
 * so removing the account removes the collection, lists, deals and settings with it. Deal
 * photos live in storage under "<user id>/", so they're removed first.
 */
export async function POST() {
  const user = await getRequestUser();
  if (!user) return NextResponse.json({ error: { code: "unauthorized", message: "Sign in first." } }, { status: 401 });
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { code: "not_configured", message: "Accounts aren't set up on this server." } }, { status: 503 });

  // Photos first (storage isn't covered by the cascade). Best effort: a failure here doesn't
  // keep the account alive.
  try {
    const bucket = admin.storage.from("deal-photos");
    const { data: files } = await bucket.list(user.id, { limit: 1000 });
    if (files?.length) await bucket.remove(files.map((f) => `${user.id}/${f.name}`));
  } catch (err) {
    console.error("account delete: photos", err);
  }

  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) {
    console.error("account delete", error.message);
    return NextResponse.json({ error: { code: "delete_failed", message: "Couldn't delete the account. Try again." } }, { status: 500 });
  }
  return NextResponse.json({ deleted: true });
}
