const express = require('express');
const { Pool } = require('pg');
const app = express();
app.use(express.json());

// Verbindung zur PostgreSQL über Umgebungsvariablen [cite: 45, 50]
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 5432
});

app.get('/api/messages', async (req, res) => {
  try {
    const result = await pool.query('SELECT content FROM messages');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/messages', async (req, res) => {
  try {
    const { text } = req.body;
    await pool.query('INSERT INTO messages (content) VALUES ($1)', [text]);
    res.sendStatus(201);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Healthcheck für Docker Compose [cite: 56]
app.get('/health', (req, res) => res.sendStatus(200));

app.listen(3000, () => console.log('Backend listening on port 3000'));