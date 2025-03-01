const express = require('express');
const mysql = require('mysql2');
const app = express();

const pool = mysql.createPool({
    host: '<PRIVATE IP OF DB SERVER>',  // Replace with your DB private IP
    user: 'app_user',
    password: 'your_secure_password',
    database: 'app_db',
    waitForConnections: true,
    connectionLimit: 10
});

app.get('/', (req, res) => {
    pool.query('SELECT 1', (err, results) => {
        if (err) {
            res.status(500).send('Database connection failed');
            return;
        }
        res.send('Application is running!');
    });
});

app.listen(3000, () => {
    console.log('Server running on port 3000');
});