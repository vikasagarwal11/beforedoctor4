import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnv } from "../src/config/env.config.js";
import { createDbPool } from "../src/db/db.connection.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  const env = loadEnv();
  const databaseUrl = env.DIRECT_URL || env.DATABASE_URL;
  const pool = createDbPool(databaseUrl);

  try {
    const migrationsDir = path.resolve(__dirname, "../src/db/migrations");
    const files = (await fs.readdir(migrationsDir)).filter((f) => f.endsWith(".sql")).sort();

    await pool.query("CREATE TABLE IF NOT EXISTS public._migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())");

    for (const file of files) {
      const already = await pool.query("SELECT 1 FROM public._migrations WHERE name=$1", [file]);
      if (already.rowCount) continue;

      const sql = await fs.readFile(path.join(migrationsDir, file), "utf8");
      await pool.query("BEGIN");
      await pool.query(sql);
      await pool.query("INSERT INTO public._migrations (name) VALUES ($1)", [file]);
      await pool.query("COMMIT");
      // eslint-disable-next-line no-console
      console.log(`Applied migration ${file}`);
    }
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err);
  process.exit(1);
});
