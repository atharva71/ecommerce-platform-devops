const express = require('express');
const cors = require('cors');
const redis = require('redis');
const mysql = require('mysql2/promise');
const promClient = require('prom-client');

const app = express();
app.use(cors());

// --------------------
// Prometheus Metrics
// --------------------

promClient.collectDefaultMetrics();

const productsRequests = new promClient.Counter({
    name: 'products_api_requests_total',
    help: 'Total product API requests'
});

// --------------------
// Redis
// --------------------

const redisClient = redis.createClient({
    url: 'redis://redis-service:6379'
});

redisClient.connect();

redisClient.on('error', (err) => {
    console.log('Redis Error:', err);
});

// --------------------
// MySQL
// --------------------

const db = mysql.createPool({
    host: 'mysql-service',
    user: 'root',
    password: 'rootpassword',
    database: 'ecommerce'
});

const PORT = 3000;

// --------------------
// Routes
// --------------------

app.get('/', (req, res) => {
    res.send('Backend API running 🚀');
});

app.get('/health', (req, res) => {
    res.json({
        status: 'UP'
    });
});

// Prometheus Metrics Endpoint

app.get('/metrics', async (req, res) => {
    res.set('Content-Type', promClient.register.contentType);
    res.end(await promClient.register.metrics());
});

// Products

app.get('/products', async (req, res) => {

    productsRequests.inc();

    try {

        const [rows] = await db.query(
            'SELECT * FROM products'
        );

        res.send(rows);

    } catch (err) {

        console.log(err);

        res.status(500).send('Database error');
    }
});

// Cart Add

app.post('/cart', async (req, res) => {

    const product = req.query.product;

    let cart = await redisClient.get('cart');

    cart = cart ? JSON.parse(cart) : [];

    cart.push(product);

    await redisClient.set(
        'cart',
        JSON.stringify(cart)
    );

    res.send({
        message: 'Product added to cart',
        cart
    });
});

// Cart View

app.get('/cart', async (req, res) => {

    let cart = await redisClient.get('cart');

    cart = cart ? JSON.parse(cart) : [];

    res.send(cart);
});

app.delete('/cart', async (req,res)=>{

    await redisClient.del('cart');

    res.json({
        message:'Cart cleared'
    });
});

// --------------------
// Start Server
// --------------------

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
