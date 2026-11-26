import { redirect } from "next/navigation";

/** Gains now lives inside Analytics (Winners & losers), like the app. Old links land there. */
export default function GainsRedirect() {
  redirect("/analytics");
}
