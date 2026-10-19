import express from "express";
import cors from "cors";
import os from "node:os";
import path from "node:path";
import pool from "./config/db.js";
import studentRoutes from "./routes/studentRoutes.js";

const app = express();

const PORT = process.env.PORT || 5000;
const configuredOrigins = (process.env.CORS_ORIGIN || "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

// Middleware
app.use(
  cors({
    origin(origin, callback) {
      // CORS is only a browser policy, not API authentication. Never use a
      // wildcard origin for the deployed API.
      if (!origin || configuredOrigins.includes(origin)) {
        callback(null, true);
        return;
      }
      callback(null, false);
    },
  }),
);
app.use(express.json());
// In Azure, the versioned release ZIP places the Vite build in ./public so
// the public gateway reaches both the UI and API through the private VMSS.
app.use(express.static(path.resolve(process.env.PUBLIC_DIR || "public")));

// Health check
app.get("/", (req, res) => {
  res.json({
    message: "Student Registration API is running",
    hostname: os.hostname(),
  });
});

app.get("/health", (req, res) => {
  pool.query("SELECT 1").then(
    () => res.status(200).json({ status: "ok", hostname: os.hostname() }),
    () => res.status(503).json({ status: "database_unavailable", hostname: os.hostname() }),
  );
});

app.use("/api/students", studentRoutes);

let server;

const shutdown = (signal) => {
  console.log(`${signal} received; closing server`);
  if (!server) {
    pool.end().finally(() => process.exit(0));
    return;
  }

  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
};

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server listening on port ${PORT}`);
});
server.on("error", async (error) => {
  console.error("Unable to start API server:", error.message);
  await pool.end();
  process.exitCode = 1;
});
