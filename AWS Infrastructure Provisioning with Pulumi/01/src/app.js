const express = require('express');
const mysql = require('mysql2');
const app = express();

const dbPrivateIp = process.env.DB_PRIVATE_IP;

if (!dbPrivateIp) {
  console.error("Error: DB_PRIVATE_IP environment variable is not set.");
  process.exit(1);
}

const pool = mysql.createPool({
  host: dbPrivateIp,
  user: 'app_user',
  password: 'Password123#',
  database: 'app_db',
  waitForConnections: true,
  connectionLimit: 10,
});

app.get('/', (req, res) => {
  pool.query('SELECT 1', (err, results) => {
    if (err) {
      console.error("Database connection error:", err);
      res.status(500).send('Database connection failed');
      return;
    }
    res.send('Application is running!');
  });
});

app.listen(3000, () => {
  console.log('Server running on port 3000');
});