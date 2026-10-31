"use client";
/* eslint-disable @next/next/no-img-element -- private photos come from signed storage URLs */

import { ImagePlus, Loader2, Trash2, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { useStore } from "@/lib/store/collection-store";
import { getBrowserSupabase } from "@/lib/supabase/client";
import { cn } from "@/lib/utils";

/**
 * Photos that document a deal, shared with the app: stored privately under your account in the
 * `deal-photos` bucket ("<user id>/<file>.jpg"). Photos the app keeps on the phone (a demo,
 * "local:…") can't be shown here.
 */
const BUCKET = "deal-photos";
const MAX_SIDE = 1600;

/** A photo's signed address, cached for the session. */
const urls = new Map<string, string>();

async function signedUrl(path: string): Promise<string | null> {
  if (path.startsWith("local:")) return null;
  const hit = urls.get(path);
  if (hit) return hit;
  const supabase = getBrowserSupabase();
  if (!supabase) return null;
  const { data } = await supabase.storage.from(BUCKET).createSignedUrl(path, 60 * 60);
  if (data?.signedUrl) urls.set(path, data.signedUrl);
  return data?.signedUrl ?? null;
}

/** Shrink to at most 1600px on the long side and encode as JPEG, like the app. */
async function shrink(file: File): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, MAX_SIDE / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  return new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("Couldn't read the photo."))), "image/jpeg", 0.72));
}

export async function deleteDealPhoto(path: string) {
  if (path.startsWith("local:")) return;
  await getBrowserSupabase()?.storage.from(BUCKET).remove([path]);
}

export function DealPhoto({ path, className, onClick }: { path: string; className?: string; onClick?: () => void }) {
  const [src, setSrc] = useState<string | null>(null);
  useEffect(() => {
    let cancelled = false;
    void signedUrl(path).then((u) => !cancelled && setSrc(u));
    return () => {
      cancelled = true;
    };
  }, [path]);
  const Tag = onClick ? "button" : "div";
  return (
    <Tag type={onClick ? "button" : undefined} onClick={onClick} className={cn("relative overflow-hidden rounded-xl bg-surface-2 ring-1 ring-inset ring-border", className)}>
      {src ? <img src={src} alt="Deal photo" className="size-full object-cover" /> : <span className="flex size-full items-center justify-center text-[11px] text-subtle">{path.startsWith("local:") ? "On phone" : <Loader2 className="size-4 animate-spin" />}</span>}
    </Tag>
  );
}

/** A deal's photos with a button to attach more; click one to see it big and delete it. */
export function DealPhotos({ photos, onChange, className }: { photos: string[]; onChange: (photos: string[]) => void; className?: string }) {
  const { user } = useStore();
  const input = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [viewing, setViewing] = useState<string | null>(null);

  const add = async (files: FileList | null) => {
    const supabase = getBrowserSupabase();
    if (!files?.length || !supabase || !user) return;
    setError(null);
    setUploading(files.length);
    const saved: string[] = [];
    for (const file of Array.from(files)) {
      try {
        const blob = await shrink(file);
        const path = `${user.id}/${crypto.randomUUID()}.jpg`;
        const { error: upErr } = await supabase.storage.from(BUCKET).upload(path, blob, { contentType: "image/jpeg" });
        if (upErr) throw upErr;
        saved.push(path);
      } catch {
        setError("A photo couldn't be saved. Check your connection and try again.");
      }
      setUploading((n) => n - 1);
    }
    if (saved.length) onChange([...photos, ...saved]);
  };

  return (
    <div className={className}>
      <div className="flex flex-wrap gap-2.5">
        {photos.map((p) => (
          <DealPhoto key={p} path={p} className="size-[84px]" onClick={() => setViewing(p)} />
        ))}
        {Array.from({ length: uploading }).map((_, i) => (
          <div key={i} className="flex size-[84px] items-center justify-center rounded-xl bg-surface-2">
            <Loader2 className="size-4 animate-spin text-muted" />
          </div>
        ))}
      </div>
      {user ? (
        <>
          <button type="button" onClick={() => input.current?.click()} className="btn-3d btn-3d-dark mt-3 inline-flex h-11 w-full items-center justify-center gap-2 rounded-full bg-surface-2 text-[14px] font-medium hover:bg-surface-3">
            <ImagePlus className="size-4" /> {photos.length ? "Add more photos" : "Add photos"}
          </button>
          <input ref={input} type="file" accept="image/*" multiple className="hidden" onChange={(e) => void add(e.target.files).finally(() => (e.target.value = ""))} />
        </>
      ) : (
        <p className="mt-2 text-[12px] text-subtle">Sign in to attach photos.</p>
      )}
      {error && <p className="mt-2 text-[12px] text-amber-300">{error}</p>}

      <Dialog open={viewing !== null} onOpenChange={(o) => !o && setViewing(null)}>
        <DialogContent className="sm:max-w-[720px]" hideClose aria-describedby={undefined}>
          <DialogTitle className="sr-only">Deal photo</DialogTitle>
          {viewing && <DealPhoto path={viewing} className="aspect-[4/3] w-full rounded-none ring-0" />}
          <div className="flex items-center justify-between p-3">
            <button type="button" onClick={() => setViewing(null)} className="inline-flex items-center gap-1.5 rounded-full px-3 py-2 text-[14px] text-muted hover:bg-surface-2">
              <X className="size-4" /> Close
            </button>
            <button
              type="button"
              onClick={() => {
                if (!viewing) return;
                void deleteDealPhoto(viewing);
                onChange(photos.filter((p) => p !== viewing));
                setViewing(null);
              }}
              className="inline-flex items-center gap-1.5 rounded-full px-3 py-2 text-[14px] text-down hover:bg-surface-2"
            >
              <Trash2 className="size-4" /> Delete photo
            </button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
