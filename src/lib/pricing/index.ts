import "server-only";
import type { DataSource } from "../types";
import { tcgApiProvider } from "./tcgapi";
import { PricingUnavailableError, type PricingProvider } from "./types";

const providers: Partial<Record<DataSource, PricingProvider>> = {
  tcgapi: tcgApiProvider,
};

export function parseProductId(id: string): { source: DataSource; externalId: string } {
  const i = id.indexOf(":");
  if (i <= 0) throw new PricingUnavailableError(`Invalid product id "${id}".`, "not_found");
  return { source: id.slice(0, i) as DataSource, externalId: id.slice(i + 1) };
}

export function providerFor(productId: string): { provider: PricingProvider; externalId: string } {
  const { source, externalId } = parseProductId(productId);
  const provider = providers[source];
  if (!provider || !/^\d+$/.test(externalId)) {
    throw new PricingUnavailableError(`No pricing source for "${productId}".`, "not_found");
  }
  return { provider, externalId };
}

export { tcgApiProvider };
