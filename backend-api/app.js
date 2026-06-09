const express = require('express');
const cors = require('cors');
const redis = require('redis');
const mysql = require('mysql2/promise');
const app = express();
app.use(cors());

const client = redis.createClient({
    url: 'redis://redis-service:6379'
});

const db = mysql.createPool({
    host: 'mysql-service',
    user: 'root',
    password: 'rootpassword',
    database: 'ecommerce'
});

client.connect();

client.on('error', (err) => {
    console.log('Redis Error:', err);
});

const PORT = 3000;


app.get('/', (req, res) => {
    res.send('Backend API running 🚀');
});

app.get('/health', (req, res) => {
    res.json({
        status: 'UP'
    });
});


app.get('/products', async (req, res) => {

    try {

        const [rows] =
            await db.query('SELECT * FROM products');

        res.send(rows);

    } catch (err) {

        console.log(err);

        res.status(500).send('Database error');
    }
});

app.post('/cart', async (req, res) => {

    const product = req.query.product;

    let cart = await client.get('cart');

    cart = cart ? JSON.parse(cart) : [];

    cart.push(product);

    await client.set('cart', JSON.stringify(cart));

    res.send({
        message: 'Product added to cart',
        cart
    });
});

app.get('/cart', async (req, res) => {

    let cart = await client.get('cart');

    cart = cart ? JSON.parse(cart) : [];

    res.send(cart);
});


app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
