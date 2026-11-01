"use client";

import { toast } from "sonner";

/** How long Undo stays on offer (the app's undo toast also lasts 6 seconds). */
export const UNDO_MS = 6000;

/**
 * The bottom-right toast with an Undo button, like the app's undo toast after a delete,
 * removal or sale. Undo runs once; a failure says so in its own toast.
 */
export function undoToast(message: string, undo: () => Promise<unknown>, opts?: { description?: string }) {
  let done = false;
  return toast(message, {
    description: opts?.description,
    duration: UNDO_MS,
    action: {
      label: "Undo",
      onClick: () => {
        if (done) return;
        done = true;
        void undo().catch((err) => toast.error("Couldn't undo", { description: err instanceof Error ? err.message : undefined }));
      },
    },
  });
}
