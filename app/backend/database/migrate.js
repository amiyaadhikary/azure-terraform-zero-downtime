import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pool from "../src/config/db.js";

const databaseDirectory = path.dirname(fileURLToPath(import.meta.url));

try {
  const schema = await readFile(path.join(databaseDirectory, "schema.sql"), "utf8");
  await pool.query(schema);
  console.log("Database schema migration completed.");
} catch (error) {
  console.error(
    "Database schema migration failed. Run it with the table owner or a role that owns the students table and can create its index.",
  );
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
