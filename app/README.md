# Student Registration System

A small, compact, and professional full-stack student registration system built with:

- React + Vite
- Node.js + Express
- PostgreSQL
- `pg` (Node.js PostgreSQL client)
- Modern responsive CSS

## Project Structure

```text
student-registration-system/
├── frontend/                 # React + Vite frontend
│   ├── src/
│   │   ├── App.jsx
│   │   ├── main.jsx
│   │   └── ...
│   ├── package.json
│   └── ...
│
├── backend/                  # Node.js + Express backend
│   ├── src/
│   │   ├── config/
│   │   │   └── db.js         # PostgreSQL connection
│   │   └── server.js         # Express API server
│   ├── database/
│   │   └── schema.sql        # PostgreSQL database schema
│   ├── .env                  # Environment variables
│   ├── .env.example
│   ├── package.json
│   └── ...
│
└── README.md
```

## PostgreSQL setup

Create `backend/.env` from `backend/.env.example`, then set either `DATABASE_URL`
or the `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD` values.
The backend checks PostgreSQL with `SELECT 1` before it starts accepting API
requests. It does not run DDL during server startup. Apply
`backend/database/schema.sql` separately with `npm run db:migrate` using the
database/table owner (or a role with the necessary ownership privileges). The
schema also adds a unique index for student roll numbers.

For local development, start your PostgreSQL server and make sure it listens on
the host and port configured in `backend/.env`. For a hosted database, set its
host, credentials, and `DB_SSL=true` when TLS is required. Before starting the
API for the first time, run `npm run db:migrate` from `app/backend` as the
database/table owner. If the table already exists and the migration reports
`must be owner of table students`, run the schema as that table's owner; the
API runtime role should not perform schema changes.

The Azure VMSS deployment sets `DB_AUTH=managed_identity`; in this mode the API
uses its system-assigned identity to fetch short-lived PostgreSQL Entra tokens.
Local development continues to use `DB_PASSWORD` unless you configure another
supported Entra-aware development flow.

For hosted PostgreSQL that requires TLS, set `DB_SSL=true`; certificate
verification remains enabled. Set `VITE_API_URL` at frontend build time when
the API is not running at `http://localhost:5000`. See the repository README
for application details. Azure infrastructure is maintained separately from
this application repository; use the infrastructure project's Terraform
runbook when deploying this app to Azure.
