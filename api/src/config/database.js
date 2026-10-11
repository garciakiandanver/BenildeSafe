const { Pool } = require('pg');
if (process.env.NODE_ENV !== 'production' && !process.env.VERCEL) {
  require('dotenv').config();
}

const isProduction = process.env.NODE_ENV === 'production' || !!process.env.VERCEL;

const pool = isProduction
  ? new Pool({
      // ☁️ CLOUD (Vercel) — uses Neon
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: false },
      max:1,
    })
  : new Pool({
      // 💻 LOCAL — uses your laptop's Postgres
      host: process.env.DB_HOST,
      port: process.env.DB_PORT,
      database: process.env.DB_NAME,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
    });

pool.query('SELECT 1')
  .then(() => console.log(`✅ DB connected (${isProduction ? 'CLOUD' : 'LOCAL'})`))
  .catch(err => console.error('❌ DB connection failed:', err.message));
module.exports = pool;