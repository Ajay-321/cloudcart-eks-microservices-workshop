const express = require("express"); const cors = require("cors");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, PutCommand, UpdateCommand, ScanCommand } = require("@aws-sdk/lib-dynamodb");
const app = express(); app.use(cors()); app.use(express.json());
const port = process.env.PORT || 3000, useDynamo = process.env.USE_DYNAMODB === "true", table = process.env.DYNAMODB_TABLE || "cloudcart-inventory";
const db = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION }));
// Mirrors the product-service seed (id -> stock) so /products and /inventory agree.
const seed = [
  { productId: "P001", quantity: 15 }, { productId: "P002", quantity: 8 }, { productId: "P003", quantity: 22 },
  { productId: "P004", quantity: 30 }, { productId: "P005", quantity: 45 }, { productId: "P006", quantity: 18 },
  { productId: "P007", quantity: 20 }, { productId: "P008", quantity: 12 }, { productId: "P009", quantity: 40 },
  { productId: "P010", quantity: 25 }, { productId: "P011", quantity: 14 }, { productId: "P012", quantity: 7 },
  { productId: "P013", quantity: 17 }, { productId: "P014", quantity: 33 }, { productId: "P015", quantity: 11 },
  { productId: "P016", quantity: 60 }, { productId: "P017", quantity: 16 }, { productId: "P018", quantity: 21 },
  { productId: "P019", quantity: 19 }, { productId: "P020", quantity: 27 }, { productId: "P021", quantity: 38 },
  { productId: "P022", quantity: 24 }, { productId: "P023", quantity: 13 }, { productId: "P024", quantity: 9 }
];
app.get("/health", (_, r) => r.json({ service: "inventory-service", status: "ok" }));
app.get("/inventory", async (_, r) => { try { if (!useDynamo) return r.json(seed); r.json((await db.send(new ScanCommand({ TableName: table }))).Items || []) } catch (e) { r.status(500).json({ error: e.message }) } });
app.get("/inventory/:productId", async (q, r) => { try { if (!useDynamo) { const x = seed.find(i => i.productId === q.params.productId); return x ? r.json(x) : r.status(404).json({ error: "Not found" }) } const x = await db.send(new GetCommand({ TableName: table, Key: { productId: q.params.productId } })); x.Item ? r.json(x.Item) : r.status(404).json({ error: "Not found" }) } catch (e) { r.status(500).json({ error: e.message }) } });
app.post("/inventory/reserve", async (q, r) => { const { productId, quantity } = q.body; try { if (!useDynamo) { const x = seed.find(i => i.productId === productId); if (!x || x.quantity < quantity) return r.status(409).json({ error: "Insufficient stock" }); x.quantity -= quantity; return r.json(x) } await db.send(new UpdateCommand({ TableName: table, Key: { productId }, UpdateExpression: "SET #q=#q-:n", ExpressionAttributeNames: { "#q": "quantity" }, ExpressionAttributeValues: { ":n": quantity } })); r.json({ productId, quantityReserved: quantity }) } catch (e) { r.status(500).json({ error: e.message }) } });
app.listen(port, () => console.log(`inventory-service listening on ${port}`));
