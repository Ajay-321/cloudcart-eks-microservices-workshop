const express = require("express");
const cors = require("cors");
const path = require("path");

const app = express();
app.use(cors());
app.use(express.json());

const port = process.env.PORT || 3000;
const publicDir = path.join(__dirname, "../public");

const services = {
  product: process.env.PRODUCT_SERVICE_URL || "http://product-service:3000",
  inventory: process.env.INVENTORY_SERVICE_URL || "http://inventory-service:3000",
  cart: process.env.CART_SERVICE_URL || "http://cart-service:3000",
  order: process.env.ORDER_SERVICE_URL || "http://order-service:3000",
  payment: process.env.PAYMENT_SERVICE_URL || "http://payment-service:3000",
  auth: process.env.AUTH_SERVICE_URL || "http://auth-service:3000"
};

async function proxy(serviceUrl, req, res) {
  const url = serviceUrl + req.originalUrl.replace(/^\/api\/[^/]+/, "");
  const options = {
    method: req.method,
    headers: { "Content-Type": "application/json" }
  };
  // Forward the caller's bearer token, if any, so backends could check it later.
  if (req.headers.authorization) options.headers.authorization = req.headers.authorization;
  if (!["GET", "HEAD"].includes(req.method)) options.body = JSON.stringify(req.body);
  try {
    const response = await fetch(url, options);
    const body = await response.text();
    res.status(response.status).type(response.headers.get("content-type") || "application/json").send(body);
  } catch (err) {
    res.status(502).json({ error: "Upstream service unavailable", detail: err.message });
  }
}

app.use("/api/products", (req, res) => proxy(services.product, req, res));
app.use("/api/inventory", (req, res) => proxy(services.inventory, req, res));
app.use("/api/cart", (req, res) => proxy(services.cart, req, res));
app.use("/api/orders", (req, res) => proxy(services.order, req, res));
app.use("/api/payments", (req, res) => proxy(services.payment, req, res));
app.use("/api/auth", (req, res) => proxy(services.auth, req, res));

app.get("/health", (_, res) => res.json({ service: "frontend", status: "ok" }));

app.use(express.static(publicDir));

// Clean, extension-less paths for the multi-page storefront.
app.get("/", (_, res) => res.sendFile(path.join(publicDir, "index.html")));
app.get("/login", (_, res) => res.sendFile(path.join(publicDir, "login.html")));
app.get("/signup", (_, res) => res.sendFile(path.join(publicDir, "signup.html")));
app.get("/dashboard", (_, res) => res.sendFile(path.join(publicDir, "dashboard.html")));

app.listen(port, () => console.log(`CloudCart frontend listening on ${port}`));
