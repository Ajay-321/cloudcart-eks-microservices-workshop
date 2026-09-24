const express = require("express");
const cors = require("cors");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, ScanCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const app = express(); app.use(cors()); app.use(express.json());
const port = process.env.PORT || 3000;
const useDynamo = process.env.USE_DYNAMODB === "true";
const table = process.env.DYNAMODB_TABLE || "cloudcart-products";
const client = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION }));

// Bigger, more realistic catalogue spanning several categories. "icon" is an
// emoji glyph so the storefront looks good with zero external image hosting.
const seed = [
  { id: "P001", name: "Cloud Laptop 14\"", category: "Laptops", price: 99999, stock: 15, icon: "💻", rating: 4.6, description: "14-inch ultrabook, 16GB RAM, all-day battery for builds on the go." },
  { id: "P002", name: "Cluster Laptop Pro 16\"", category: "Laptops", price: 154999, stock: 8, icon: "💻", rating: 4.8, description: "16-inch workstation-class laptop for running local Kubernetes clusters." },
  { id: "P003", name: "Node Notebook Air", category: "Laptops", price: 74999, stock: 22, icon: "💻", rating: 4.3, description: "Lightweight everyday laptop, great for docs and dashboards." },
  { id: "P004", name: "K8s Headphones", category: "Audio", price: 4999, stock: 30, icon: "🎧", rating: 4.5, description: "Over-ear ANC headphones, tuned for long pairing sessions." },
  { id: "P005", name: "Pod Earbuds", category: "Audio", price: 2999, stock: 45, icon: "🎧", rating: 4.2, description: "True-wireless earbuds with a pocket-sized charging pod." },
  { id: "P006", name: "Container Speaker", category: "Audio", price: 3499, stock: 18, icon: "🔊", rating: 4.4, description: "Portable Bluetooth speaker, splash-resistant, 12-hour battery." },
  { id: "P007", name: "DevOps Backpack", category: "Accessories", price: 2499, stock: 20, icon: "🎒", rating: 4.7, description: "Padded 17-inch laptop compartment plus a dedicated cable pocket." },
  { id: "P008", name: "Platform Keyboard", category: "Accessories", price: 6999, stock: 12, icon: "⌨️", rating: 4.6, description: "Mechanical keyboard with hot-swappable switches." },
  { id: "P009", name: "Deploy Mouse", category: "Accessories", price: 1999, stock: 40, icon: "🖱️", rating: 4.1, description: "Ergonomic wireless mouse with a silent click." },
  { id: "P010", name: "Webhook Webcam", category: "Accessories", price: 3999, stock: 25, icon: "📷", rating: 4.3, description: "1080p webcam with auto low-light correction for standups." },
  { id: "P011", name: "Scale-Out Monitor 27\"", category: "Monitors", price: 22999, stock: 14, icon: "🖥️", rating: 4.5, description: "27-inch QHD IPS monitor with USB-C 90W passthrough." },
  { id: "P012", name: "Dual-Zone Monitor 32\" Curved", category: "Monitors", price: 34999, stock: 7, icon: "🖥️", rating: 4.7, description: "32-inch curved 4K display, perfect for dashboards and grafana boards." },
  { id: "P013", name: "Portable Monitor 15\"", category: "Monitors", price: 12999, stock: 17, icon: "🖥️", rating: 4.0, description: "USB-C powered travel monitor, slips into any backpack." },
  { id: "P014", name: "Replica SSD 1TB", category: "Storage", price: 8999, stock: 33, icon: "💾", rating: 4.6, description: "NVMe external SSD, 1TB, rated for 1000+ read/write cycles." },
  { id: "P015", name: "Persistent Volume Drive 4TB", category: "Storage", price: 15999, stock: 11, icon: "🗄️", rating: 4.4, description: "4TB desktop drive for backups and datasets." },
  { id: "P016", name: "EdgeCache USB 128GB", category: "Storage", price: 1499, stock: 60, icon: "🔌", rating: 3.9, description: "Fast USB 3.2 flash drive, 128GB." },
  { id: "P017", name: "Mesh Router X6", category: "Networking", price: 11999, stock: 16, icon: "📶", rating: 4.5, description: "Tri-band mesh router, covers up to 6 nodes across your home." },
  { id: "P018", name: "Load Balancer Switch 8-Port", category: "Networking", price: 5499, stock: 21, icon: "🔀", rating: 4.2, description: "Unmanaged 8-port gigabit switch for a tidy home lab." },
  { id: "P019", name: "Ingress Access Point", category: "Networking", price: 6499, stock: 19, icon: "📡", rating: 4.3, description: "Ceiling-mount Wi-Fi 6 access point for larger spaces." },
  { id: "P020", name: "Pulse Smartwatch", category: "Wearables", price: 9999, stock: 27, icon: "⌚", rating: 4.4, description: "Fitness + notifications smartwatch, 7-day battery." },
  { id: "P021", name: "Sentinel Fitness Band", category: "Wearables", price: 3499, stock: 38, icon: "⌚", rating: 4.0, description: "Lightweight fitness band with heart-rate tracking." },
  { id: "P022", name: "Raid Mechanical Gamepad", category: "Gaming", price: 4499, stock: 24, icon: "🎮", rating: 4.5, description: "Wireless gamepad with programmable back paddles." },
  { id: "P023", name: "Render Farm GPU Riser Kit", category: "Gaming", price: 2999, stock: 13, icon: "🎮", rating: 4.1, description: "GPU riser + cable kit for compact builds." },
  { id: "P024", name: "Latency-Zero Gaming Chair", category: "Gaming", price: 18999, stock: 9, icon: "🪑", rating: 4.6, description: "Ergonomic gaming/office chair with 4D armrests." }
];

app.get("/health", (_, res) => res.json({ service: "product-service", status: "ok" }));

app.get("/categories", (_, res) => {
  res.json([...new Set(seed.map(p => p.category))].sort());
});

app.get("/products", async (req, res) => {
  try {
    let items;
    if (!useDynamo) {
      items = seed;
    } else {
      const data = await client.send(new ScanCommand({ TableName: table }));
      items = data.Items || [];
    }
    const { category, q } = req.query;
    if (category && category !== "All") items = items.filter(p => p.category === category);
    if (q) {
      const needle = String(q).toLowerCase();
      items = items.filter(p =>
        p.name.toLowerCase().includes(needle) ||
        (p.category || "").toLowerCase().includes(needle) ||
        (p.description || "").toLowerCase().includes(needle)
      );
    }
    res.json(items);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get("/products/:id", async (req, res) => {
  try {
    if (!useDynamo) return res.json(seed.find(x => x.id === req.params.id) || { error: "Not found" });
    const data = await client.send(new GetCommand({ TableName: table, Key: { id: req.params.id } }));
    if (!data.Item) return res.status(404).json({ error: "Not found" });
    res.json(data.Item);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post("/products", async (req, res) => {
  const item = req.body;
  try {
    if (useDynamo) await client.send(new PutCommand({ TableName: table, Item: item }));
    res.status(201).json(item);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.listen(port, () => console.log(`product-service listening on ${port}`));
