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
  "DB_BOOTSTRAP_PASSWORD",
  "DB_APP_USER",
];
const missing = required.filter((name) => !process.env[name]);
if (missing.length) {
  throw new Error(`Missing required bootstrap settings: ${missing.join(", ")}`);
}

const bootstrapUser = process.env.DB_BOOTSTRAP_USER;
const appUser = process.env.DB_APP_USER;
// This script supports password-authenticated local PostgreSQL development.
// Azure VMSS deployments use bootstrap-managed-identity.js instead.
const appPassword = process.env.DB_APP_PASSWORD || process.env.DB_PASSWORD;
const databaseName = process.env.DB_NAME;
if (!appPassword) {
  throw new Error("Missing required bootstrap setting: DB_APP_PASSWORD or DB_PASSWORD.");
}
if (!/^[A-Za-z_][A-Za-z0-9_]{0,62}$/.test(appUser)) {
  throw new Error("DB_APP_USER must be a valid PostgreSQL role name (max 63 characters).");
}
if (bootstrapUser === appUser) {
  throw new Error("The API role must be different from the database administrator role.");
}

const quoteIdentifier = (value) => `"${value.replaceAll('"', '""')}"`;
const quoteLiteral = (value) => `'${value.replaceAll("'", "''")}'`;
const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  database: databaseName,
  user: bootstrapUser,
  password: process.env.DB_BOOTSTRAP_PASSWORD,
  ...(process.env.DB_SSL?.toLowerCase() === "true"
    ? { ssl: { rejectUnauthorized: true } }
    : {}),
});

try {
  // Run schema changes as the current owner/admin. The runtime API role gets
  // data access only and must not own tables or perform DDL.
  const schema = await readFile(path.join(databaseDirectory, "schema.sql"), "utf8");
  await pool.query(schema);

  const roleExists = await pool.query("SELECT 1 FROM pg_roles WHERE rolname = $1", [appUser]);
  if (roleExists.rowCount) {
    await pool.query(
      `ALTER ROLE ${quoteIdentifier(appUser)} WITH LOGIN PASSWORD ${quoteLiteral(appPassword)}`,
    );
  } else {
    await pool.query(
      `CREATE ROLE ${quoteIdentifier(appUser)} WITH LOGIN PASSWORD ${quoteLiteral(appPassword)}`,
    );
  }

  const quotedDatabase = quoteIdentifier(databaseName);
  const quotedAppUser = quoteIdentifier(appUser);
  const quotedBootstrapUser = quoteIdentifier(bootstrapUser);
  await pool.query(`GRANT CONNECT ON DATABASE ${quotedDatabase} TO ${quotedAppUser}`);
  await pool.query(`GRANT USAGE ON SCHEMA public TO ${quotedAppUser}`);
  await pool.query(
    `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${quotedAppUser}`,
  );
  await pool.query(
    `GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ${quotedAppUser}`,
  );
  await pool.query(
    `ALTER DEFAULT PRIVILEGES FOR ROLE ${quotedBootstrapUser} IN SCHEMA public ` +
      `GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${quotedAppUser}`,
  );
  await pool.query(
    `ALTER DEFAULT PRIVILEGES FOR ROLE ${quotedBootstrapUser} IN SCHEMA public ` +
      `GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${quotedAppUser}`,
  );

  console.log(`Schema prepared and least-privilege API role '${appUser}' configured.`);
} catch (error) {
  console.error(
    "Database bootstrap failed. Run this as the owner of existing tables, or use the existing table owner for the schema migration.",
  );
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
