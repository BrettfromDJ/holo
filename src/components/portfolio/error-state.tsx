"use client";

import { AlertCircle } from "lucide-react";

export function ErrorState({ message }: { message: string | null }) {
  return (
    <div className="flex flex-col items-center py-24 text-center">
      <AlertCircle className="size-6 text-down" />
      <p className="mt-3 font-medium">Couldn&apos;t load your collection</p>
      <p className="mt-1 max-w-sm text-sm text-muted">{message ?? "Please try again."}</p>
      <button onClick={() => location.reload()} className="mt-4 text-sm font-medium underline-offset-4 hover:underline">
        Retry
      </button>
    </div>
  );
}
