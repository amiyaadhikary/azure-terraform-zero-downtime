import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import pg from "pg";

const { Pool } = pg;
const databaseDirectory = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(databaseDirectory, "../.env") });

const required = [
  "DB_HOST",
  "DB_NAME",
  "DB_BOOTSTRAP_USER",
  "DB_BOOTSTRAP_TOKEN",
  "DB_APP_USER",
  "DB_APP_OBJECT_ID",
];
const missing = required.filter((name) => !process.env[name]);
if (missing.length) {
  throw new Error(`Missing managed-identity bootstrap settings: ${missing.join(", ")}`);
}

const host = process.env.DB_HOST;
const port = Number(process.env.DB_PORT || 5432);
const databaseName = process.env.DB_NAME;
const bootstrapUser = process.env.DB_BOOTSTRAP_USER;
const bootstrapToken = process.env.DB_BOOTSTRAP_TOKEN;
const appUser = process.env.DB_APP_USER;
const appObjectId = process.env.DB_APP_OBJECT_ID;
if (!/^[A-Za-z_][A-Za-z0-9_]{0,62}$/.test(appUser)) {
  throw new Error("DB_APP_USER must be a valid PostgreSQL role name (max 63 characters).");
}

const quoteIdentifier = (value) => `"${value.replaceAll('"', '""')}"`;
const poolFor = (database) => new Pool({
  host,
  port,
  database,
  user: bootstrapUser,
  password: bootstrapToken,
  ssl: { rejectUnauthorized: true },
  connectionTimeoutMillis: 10000,
});

const maintenancePool = poolFor("postgres");
const appPool = poolFor(databaseName);
try {
  const schema = await readFile(path.join(databaseDirectory, "schema.sql"), "utf8");
  await appPool.query(schema);

  const existingPrincipal = await maintenancePool.query(
    `SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = $1`,
    [appUser],
  );
  if (existingPrincipal.rowCount > 0) {
    await appPool.query(`DROP OWNED BY ${quoteIdentifier(appUser)}`);
    await maintenancePool.query(`DROP ROLE ${quoteIdentifier(appUser)}`);
  }

  await maintenancePool.query(
    "SELECT * FROM pg_catalog.pgaadauth_create_principal_with_oid($1, $2, 'service', false, false)",
    [appUser, appObjectId],
  );

  const quotedDatabase = quoteIdentifier(databaseName);
  const quotedAppUser = quoteIdentifier(appUser);
  const quotedBootstrapUser = quoteIdentifier(bootstrapUser);
  await appPool.query(`GRANT CONNECT ON DATABASE ${quotedDatabase} TO ${quotedAppUser}`);
  await appPool.query(`GRANT USAGE ON SCHEMA public TO ${quotedAppUser}`);
  await appPool.query(
    `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${quotedAppUser}`,
  );
  await appPool.query(
    `GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ${quotedAppUser}`,
  );
  await appPool.query(
    `ALTER DEFAULT PRIVILEGES FOR ROLE ${quotedBootstrapUser} IN SCHEMA public ` +
      `GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${quotedAppUser}`,
  );
  await appPool.query(
    `ALTER DEFAULT PRIVILEGES FOR ROLE ${quotedBootstrapUser} IN SCHEMA public ` +
      `GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${quotedAppUser}`,
  );

  console.log(`Schema ready; Entra-linked API role '${appUser}' has data access only.`);
} catch (error) {
  console.error("Managed Identity database bootstrap failed:", error.message);
  process.exitCode = 1;
} finally {
  await Promise.all([maintenancePool.end(), appPool.end()]);
}
