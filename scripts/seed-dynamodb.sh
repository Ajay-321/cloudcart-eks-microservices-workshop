#!/usr/bin/env bash
# ===========================================================================
# seed-dynamodb.sh
#
# Seeds the CloudCart DynamoDB tables with the SAME catalogue data the app
# serves in in-memory mode, so the DynamoDB deployment shows the same 24
# products and matching stock as the no-DynamoDB demo.
#
# Seeds two tables:
#   - cloudcart-products  (partition key: id)        — 24 products
#   - cloudcart-inventory (partition key: productId) — 24 stock rows
#
# Idempotent: safe to re-run. It uses put-item, which overwrites the item
# with the same key, so re-running simply resets the catalogue/stock.
#
# IMPORTANT: these table names must match create-dynamodb-tables.sh and the
# DYNAMODB_TABLE env values in k8s/aws/*-deployment.yaml.
#
# Usage: AWS_REGION=us-east-1 ./scripts/seed-dynamodb.sh
# ===========================================================================
set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"

# ---------------------------------------------------------------------------
# Preflight: the products table must already exist. Guarded with `if ! ...`
# so its non-zero exit doesn't trip set -e before we can print guidance.
# ---------------------------------------------------------------------------
if ! aws dynamodb describe-table --table-name cloudcart-products --region "$REGION" >/dev/null 2>&1; then
  echo "ERROR: table 'cloudcart-products' not found in region '$REGION'."
  echo "Create the tables first:  ./scripts/create-dynamodb-tables.sh"
  exit 1
fi

# Single reusable temp file for building each item's JSON, cleaned on exit.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

SEEDED_PRODUCTS=0
SEEDED_INVENTORY=0

# ---------------------------------------------------------------------------
# put_product id name category price stock icon rating description
#
# Writes a product item to cloudcart-products. The JSON is built into $TMP
# with printf and passed via --item file://$TMP so embedded double-quotes
# (e.g. Cloud Laptop 14") and emoji (UTF-8) are handled safely. Text fields
# are pre-escaped for JSON with escape_json before being written.
# ---------------------------------------------------------------------------
escape_json () {
  # Escape backslashes then double-quotes so the value is valid inside a
  # JSON string. printf %s avoids interpreting backslashes in the input.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

put_product () {
  local id="$1" name="$2" category="$3" price="$4" stock="$5" icon="$6" rating="$7" description="$8"
  local e_id e_name e_category e_icon e_description
  e_id="$(escape_json "$id")"
  e_name="$(escape_json "$name")"
  e_category="$(escape_json "$category")"
  e_icon="$(escape_json "$icon")"
  e_description="$(escape_json "$description")"

  printf '{"id":{"S":"%s"},"name":{"S":"%s"},"category":{"S":"%s"},"price":{"N":"%s"},"stock":{"N":"%s"},"icon":{"S":"%s"},"rating":{"N":"%s"},"description":{"S":"%s"}}' \
    "$e_id" "$e_name" "$e_category" "$price" "$stock" "$e_icon" "$rating" "$e_description" > "$TMP"

  aws dynamodb put-item \
    --table-name cloudcart-products \
    --region "$REGION" \
    --item "file://$TMP" >/dev/null

  SEEDED_PRODUCTS=$((SEEDED_PRODUCTS + 1))
  echo "Seeded product: $id ($SEEDED_PRODUCTS/24)"
}

# ---------------------------------------------------------------------------
# put_inventory productId quantity
#
# Writes a stock row to cloudcart-inventory.
# ---------------------------------------------------------------------------
put_inventory () {
  local product_id="$1" quantity="$2"
  local e_product_id
  e_product_id="$(escape_json "$product_id")"

  printf '{"productId":{"S":"%s"},"quantity":{"N":"%s"}}' \
    "$e_product_id" "$quantity" > "$TMP"

  aws dynamodb put-item \
    --table-name cloudcart-inventory \
    --region "$REGION" \
    --item "file://$TMP" >/dev/null

  SEEDED_INVENTORY=$((SEEDED_INVENTORY + 1))
  echo "Seeded inventory: $product_id ($SEEDED_INVENTORY/24)"
}

echo "Seeding cloudcart-products (region $REGION) ..."
#           id     name                            category      price   stock icon  rating description
put_product P001 "Cloud Laptop 14\""              "Laptops"     99999   15    "💻"  4.6   "14-inch ultrabook, 16GB RAM, all-day battery for builds on the go."
put_product P002 "Cluster Laptop Pro 16\""        "Laptops"     154999  8     "💻"  4.8   "16-inch workstation-class laptop for running local Kubernetes clusters."
put_product P003 "Node Notebook Air"              "Laptops"     74999   22    "💻"  4.3   "Lightweight everyday laptop, great for docs and dashboards."
put_product P004 "K8s Headphones"                 "Audio"       4999    30    "🎧"  4.5   "Over-ear ANC headphones, tuned for long pairing sessions."
put_product P005 "Pod Earbuds"                    "Audio"       2999    45    "🎧"  4.2   "True-wireless earbuds with a pocket-sized charging pod."
put_product P006 "Container Speaker"              "Audio"       3499    18    "🔊"  4.4   "Portable Bluetooth speaker, splash-resistant, 12-hour battery."
put_product P007 "DevOps Backpack"                "Accessories" 2499    20    "🎒"  4.7   "Padded 17-inch laptop compartment plus a dedicated cable pocket."
put_product P008 "Platform Keyboard"              "Accessories" 6999    12    "⌨️"  4.6   "Mechanical keyboard with hot-swappable switches."
put_product P009 "Deploy Mouse"                   "Accessories" 1999    40    "🖱️"  4.1   "Ergonomic wireless mouse with a silent click."
put_product P010 "Webhook Webcam"                 "Accessories" 3999    25    "📷"  4.3   "1080p webcam with auto low-light correction for standups."
put_product P011 "Scale-Out Monitor 27\""        "Monitors"    22999   14    "🖥️"  4.5   "27-inch QHD IPS monitor with USB-C 90W passthrough."
put_product P012 "Dual-Zone Monitor 32\" Curved" "Monitors"    34999   7     "🖥️"  4.7   "32-inch curved 4K display, perfect for dashboards and grafana boards."
put_product P013 "Portable Monitor 15\""         "Monitors"    12999   17    "🖥️"  4.0   "USB-C powered travel monitor, slips into any backpack."
put_product P014 "Replica SSD 1TB"               "Storage"     8999    33    "💾"  4.6   "NVMe external SSD, 1TB, rated for 1000+ read/write cycles."
put_product P015 "Persistent Volume Drive 4TB"   "Storage"     15999   11    "🗄️"  4.4   "4TB desktop drive for backups and datasets."
put_product P016 "EdgeCache USB 128GB"           "Storage"     1499    60    "🔌"  3.9   "Fast USB 3.2 flash drive, 128GB."
put_product P017 "Mesh Router X6"                "Networking"  11999   16    "📶"  4.5   "Tri-band mesh router, covers up to 6 nodes across your home."
put_product P018 "Load Balancer Switch 8-Port"   "Networking"  5499    21    "🔀"  4.2   "Unmanaged 8-port gigabit switch for a tidy home lab."
put_product P019 "Ingress Access Point"          "Networking"  6499    19    "📡"  4.3   "Ceiling-mount Wi-Fi 6 access point for larger spaces."
put_product P020 "Pulse Smartwatch"              "Wearables"   9999    27    "⌚"  4.4   "Fitness + notifications smartwatch, 7-day battery."
put_product P021 "Sentinel Fitness Band"         "Wearables"   3499    38    "⌚"  4.0   "Lightweight fitness band with heart-rate tracking."
put_product P022 "Raid Mechanical Gamepad"       "Gaming"      4499    24    "🎮"  4.5   "Wireless gamepad with programmable back paddles."
put_product P023 "Render Farm GPU Riser Kit"     "Gaming"      2999    13    "🎮"  4.1   "GPU riser + cable kit for compact builds."
put_product P024 "Latency-Zero Gaming Chair"     "Gaming"      18999   9     "🪑"  4.6   "Ergonomic gaming/office chair with 4D armrests."

echo "Seeding cloudcart-inventory (region $REGION) ..."
put_inventory P001 15
put_inventory P002 8
put_inventory P003 22
put_inventory P004 30
put_inventory P005 45
put_inventory P006 18
put_inventory P007 20
put_inventory P008 12
put_inventory P009 40
put_inventory P010 25
put_inventory P011 14
put_inventory P012 7
put_inventory P013 17
put_inventory P014 33
put_inventory P015 11
put_inventory P016 60
put_inventory P017 16
put_inventory P018 21
put_inventory P019 19
put_inventory P020 27
put_inventory P021 38
put_inventory P022 24
put_inventory P023 13
put_inventory P024 9

echo "Seeded 24 products into cloudcart-products and 24 rows into cloudcart-inventory (region $REGION)."
