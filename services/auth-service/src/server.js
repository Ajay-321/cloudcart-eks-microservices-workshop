const express = require("express");
const cors = require("cors");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");

const app = express();
app.use(cors());
app.use(express.json());

const port = process.env.PORT || 3000;
const useDynamo = process.env.USE_DYNAMODB === "true";
const table = process.env.DYNAMODB_TABLE || "cloudcart-users";
const JWT_SECRET = process.env.JWT_SECRET || "cloudcart-dev-secret-change-me";
const TOKEN_TTL = "12h";

const client = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION }));

// In-memory store, keyed by lowercase email. Fine for the workshop's local mode.
const users = new Map();

function publicUser(u) {
  return { userId: u.userId, name: u.name, email: u.email, createdAt: u.createdAt };
}

async function findUser(email) {
  const key = email.toLowerCase();
  if (!useDynamo) return users.get(key) || null;
  const data = await client.send(new GetCommand({ TableName: table, Key: { email: key } }));
  return data.Item || null;
}

async function saveUser(user) {
  if (useDynamo) {
    await client.send(new PutCommand({ TableName: table, Item: user }));
  } else {
    users.set(user.email, user);
  }
}

function issueToken(user) {
  return jwt.sign({ sub: user.userId, email: user.email, name: user.name }, JWT_SECRET, { expiresIn: TOKEN_TTL });
}

app.get("/health", (_, res) => res.json({ service: "auth-service", status: "ok" }));

app.post("/signup", async (req, res) => {
  try {
    const { name, email, password } = req.body || {};
    if (!name || !email || !password) {
      return res.status(400).json({ error: "name, email and password are required" });
    }
    if (password.length < 6) {
      return res.status(400).json({ error: "Password must be at least 6 characters" });
    }
    const normalizedEmail = String(email).toLowerCase().trim();
    const existing = await findUser(normalizedEmail);
    if (existing) return res.status(409).json({ error: "An account with this email already exists" });

    const passwordHash = await bcrypt.hash(password, 10);
    const user = {
      userId: "USR-" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      name: String(name).trim(),
      email: normalizedEmail,
      passwordHash,
      createdAt: new Date().toISOString()
    };
    await saveUser(user);
    res.status(201).json({ token: issueToken(user), user: publicUser(user) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: "email and password are required" });

    const user = await findUser(String(email).toLowerCase().trim());
    if (!user) return res.status(401).json({ error: "Invalid email or password" });

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) return res.status(401).json({ error: "Invalid email or password" });

    res.json({ token: issueToken(user), user: publicUser(user) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get("/me", async (req, res) => {
  try {
    const header = req.headers.authorization || "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : null;
    if (!token) return res.status(401).json({ error: "Missing token" });

    const decoded = jwt.verify(token, JWT_SECRET);
    res.json({ userId: decoded.sub, email: decoded.email, name: decoded.name });
  } catch (e) {
    res.status(401).json({ error: "Invalid or expired token" });
  }
});

app.listen(port, () => console.log(`auth-service listening on ${port}`));
