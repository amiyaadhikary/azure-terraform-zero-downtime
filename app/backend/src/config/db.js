import pg from "pg";
import dotenv from "dotenv";
import path from "path";
import { fileURLToPath } from "url";

const { Pool } = pg;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load backend/.env
dotenv.config({
  path: path.resolve(__dirname, "../../.env"),
});

const connectionString = process.env.DATABASE_URL?.trim();
const managedIdentityAuth = process.env.DB_AUTH === "managed_identity";
const requiredVariables = [
  "DB_HOST",
  "DB_NAME",
  "DB_USER",
  ...(managedIdentityAuth ? [] : ["DB_PASSWORD"]),
];

let cachedToken;
let cachedTokenExpiry = 0;
async function getManagedIdentityToken() {
  if (cachedToken && cachedTokenExpiry - Date.now() > 5 * 60 * 1000) {
    return cachedToken;
  }

  const tokenUrl = new URL(
    "http://169.254.169.254/metadata/identity/oauth2/token",
  );
  tokenUrl.search = new URLSearchParams({
    "api-version": "2018-02-01",
    resource: "https://ossrdbms-aad.database.windows.net",
  });
  const response = await fetch(tokenUrl, {
    headers: { Metadata: "true" },
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) {
    throw new Error(`Managed Identity token request failed (${response.status}).`);
  }
  const tokenResponse = await response.json();
  if (!tokenResponse.access_token || !tokenResponse.expires_on) {
    throw new Error("Managed Identity endpoint returned an incomplete token.");
  }
  cachedToken = tokenResponse.access_token;
  cachedTokenExpiry = Number(tokenResponse.expires_on) * 1000;
  return cachedToken;
}

if (!connectionString) {
  const missingVariables = requiredVariables.filter(
    (name) => !process.env[name]?.trim(),
  );

  if (missingVariables.length > 0) {
    throw new Error(
      `Missing PostgreSQL configuration: ${missingVariables.join(", ")}. ` +
        "Set DATABASE_URL or all required DB_* variables.",
    );
  }
}

const sslEnabled = process.env.DB_SSL?.toLowerCase() === "true";
const pool = new Pool({
  ...(connectionString
    ? { connectionString }
    : {
        host: process.env.DB_HOST,
        port: Number(process.env.DB_PORT || 5432),
        database: process.env.DB_NAME,
        user: process.env.DB_USER,
        password: managedIdentityAuth
          ? getManagedIdentityToken
          : process.env.DB_PASSWORD,
      }),
  ...(sslEnabled ? { ssl: { rejectUnauthorized: true } } : {}),
  max: Number(process.env.DB_POOL_MAX || 10),
  connectionTimeoutMillis: Number(process.env.DB_CONNECTION_TIMEOUT_MS || 5000),
  idleTimeoutMillis: Number(process.env.DB_IDLE_TIMEOUT_MS || 30000),
  allowExitOnIdle: false,
});

pool.on("connect", () => {
  console.log("PostgreSQL connected");
});

pool.on("error", (error) => {
  console.error("Unexpected PostgreSQL pool error:", error.message);
});

export default pool;
