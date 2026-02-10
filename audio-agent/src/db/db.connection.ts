import dns from "node:dns";
import pg from "pg";

// Some networks return synthesized IPv6 (DNS64/NAT64) entries ahead of IPv4.
// node-postgres will then attempt IPv6 first and can hang until timeout.
// Prefer IPv4 to make Supabase pooler connections reliable.
try {
  dns.setDefaultResultOrder("ipv4first");
} catch {
  // ignore (older Node versions)
}

export function createDbPool(databaseUrl: string) {
  const ssl = inferSsl(databaseUrl);
  const password = inferPassword(databaseUrl);

  const config: pg.PoolConfig = {
    connectionString: databaseUrl,
    ssl,
    max: 20,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000
  };

  if (password) config.password = password;

  return new pg.Pool(config);
}

function inferPassword(databaseUrl: string): string | undefined {
  const raw = (process.env.DB_PASSWORD ?? process.env.SUPABASE_DB_PASSWORD ?? "").trim();
  if (!raw) return undefined;

  try {
    const u = new URL(databaseUrl);
    // If the URL already contains a password, don't override it.
    if (u.password) return undefined;
    return raw;
  } catch {
    return raw;
  }
}

function inferSsl(databaseUrl: string): pg.PoolConfig["ssl"] | undefined {
  const explicit = (process.env.DB_SSL ?? "").trim().toLowerCase();
  if (["0", "false", "disable", "disabled", "off", "no"].includes(explicit)) return undefined;
  if (["1", "true", "require", "required", "on", "yes"].includes(explicit)) return { rejectUnauthorized: false };

  const sslMode = (process.env.PGSSLMODE ?? "").trim().toLowerCase();
  if (["require", "verify-ca", "verify-full"].includes(sslMode)) return { rejectUnauthorized: false };

  try {
    const u = new URL(databaseUrl);
    const host = u.hostname.toLowerCase();
    if (host === "localhost" || host === "127.0.0.1") return undefined;
    // Supabase Postgres (direct or pooler) requires TLS.
    if (host.endsWith(".supabase.co") || host.endsWith(".pooler.supabase.com")) return { rejectUnauthorized: false };
    // Default to TLS for non-local hosts to avoid common managed-DB connection failures.
    return { rejectUnauthorized: false };
  } catch {
    return undefined;
  }
}

export type DbPool = pg.Pool;
