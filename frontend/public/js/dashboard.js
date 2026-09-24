(() => {
  if (!CloudCart.requireAuth("/dashboard")) return;
  CloudCart.renderNavbar("/dashboard");

  const session = CloudCart.getSession();
  document.getElementById("dash-title").textContent = `Welcome back, ${session.user.name.split(" ")[0]}`;

  const charts = {};
  const PALETTE = ["#4f46e5", "#06b6d4", "#16a34a", "#d97706", "#dc2626", "#7c3aed", "#0ea5e9", "#db2777"];
  const FULL_REFRESH_SECS = 20;
  const HEALTH_REFRESH_SECS = 7;

  let lastData = { products: [], inventory: [], orders: [] };
  let fullCountdown = FULL_REFRESH_SECS;

  function destroyChart(key) { if (charts[key]) { charts[key].destroy(); delete charts[key]; } }

  function chartColors() {
    const dark = document.documentElement.getAttribute("data-theme") === "dark";
    return { grid: dark ? "rgba(148,163,216,0.14)" : "#eef0f6", text: dark ? "#96a0c4" : "#5b6478" };
  }

  async function load() {
    let products = [], inventory = [], orders = [];
    try {
      [products, inventory, orders] = await Promise.all([
        CloudCart.api("/api/products/products"),
        CloudCart.api("/api/inventory/inventory"),
        CloudCart.api("/api/orders/orders").catch(() => [])
      ]);
    } catch (e) {
      CloudCart.toast("Could not load dashboard data: " + e.message, "error");
    }
    lastData = { products, inventory, orders };
    renderKpis(products, inventory, orders);
    renderRevenueChart(orders);
    renderInventoryChart(products, inventory);
    renderCategoryRevenueChart(products, orders);
    renderCatalogueMixChart(products);
    renderLeaderboard(products, orders);
    renderOrdersTable(orders);
    renderHealthPanel();
    fullCountdown = FULL_REFRESH_SECS;
  }

  function productCategoryMap(products) {
    const map = {};
    products.forEach(p => (map[p.id] = p.category));
    return map;
  }

  function renderKpis(products, inventory, orders) {
    const totalRevenue = orders.reduce((s, o) => s + Number(o.totalAmount || 0), 0);
    const totalOrders = orders.length;
    const avgOrder = totalOrders ? totalRevenue / totalOrders : 0;
    const lowStock = inventory.filter(i => Number(i.quantity) <= 10).length;

    document.getElementById("kpi-grid").innerHTML = `
      <div class="kpi-card">
        <div class="label">Total revenue</div>
        <div class="value" id="kpi-revenue">₹0</div>
        <div class="delta up">From ${totalOrders} order${totalOrders === 1 ? "" : "s"}</div>
      </div>
      <div class="kpi-card">
        <div class="label">Total orders</div>
        <div class="value" id="kpi-orders">0</div>
        <div class="delta up">${totalOrders ? "Live from order-service" : "Place a demo order to see this grow"}</div>
      </div>
      <div class="kpi-card">
        <div class="label">Avg order value</div>
        <div class="value" id="kpi-avg">₹0</div>
        <div class="delta up">Across ${products.length} catalogue items</div>
      </div>
      <div class="kpi-card">
        <div class="label">Low stock alerts</div>
        <div class="value" id="kpi-lowstock" style="${lowStock ? "color:var(--danger)" : ""}">0</div>
        <div class="delta ${lowStock ? "warn" : "up"}">${lowStock ? "Items at 10 units or fewer" : "Inventory looks healthy"}</div>
      </div>`;

    CloudCart.countUp(document.getElementById("kpi-revenue"), totalRevenue, { format: n => CloudCart.money(n) });
    CloudCart.countUp(document.getElementById("kpi-orders"), totalOrders, {});
    CloudCart.countUp(document.getElementById("kpi-avg"), avgOrder, { format: n => CloudCart.money(n) });
    CloudCart.countUp(document.getElementById("kpi-lowstock"), lowStock, {});
  }

  function renderRevenueChart(orders) {
    destroyChart("revenue");
    const ctx = document.getElementById("chart-revenue");
    if (!orders.length) {
      wrapEmpty(ctx, "No orders yet — place one from the catalogue to see revenue here.");
      return;
    }
    const sorted = [...orders].sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
    const labels = sorted.map((o, i) => o.orderId ? o.orderId.replace("ORD-", "#") : `Order ${i + 1}`);
    const values = sorted.map(o => Number(o.totalAmount || 0));
    charts.revenue = new Chart(ctx, {
      type: "line",
      data: {
        labels,
        datasets: [{
          label: "Revenue (₹)",
          data: values,
          borderColor: "#4f46e5",
          backgroundColor: "rgba(79,70,229,0.14)",
          fill: true, tension: 0.35, pointRadius: 4, pointBackgroundColor: "#4f46e5"
        }]
      },
      options: baseOptions({ legend: false })
    });
  }

  function renderInventoryChart(products, inventory) {
    destroyChart("inventory");
    const catMap = productCategoryMap(products);
    const byCategory = {};
    inventory.forEach(i => {
      const cat = catMap[i.productId] || "Other";
      byCategory[cat] = (byCategory[cat] || 0) + Number(i.quantity || 0);
    });
    const labels = Object.keys(byCategory);
    const values = Object.values(byCategory);
    charts.inventory = new Chart(document.getElementById("chart-inventory"), {
      type: "bar",
      data: { labels, datasets: [{ label: "Units in stock", data: values, backgroundColor: labels.map((_, i) => PALETTE[i % PALETTE.length]), borderRadius: 8 }] },
      options: baseOptions({ legend: false })
    });
  }

  function renderCategoryRevenueChart(products, orders) {
    destroyChart("categoryRevenue");
    const ctx = document.getElementById("chart-category-revenue");
    if (!orders.length) { wrapEmpty(ctx, "Revenue by category appears once orders are placed."); return; }
    const catMap = productCategoryMap(products);
    const byCategory = {};
    orders.forEach(o => (o.items || []).forEach(item => {
      const cat = catMap[item.productId] || "Other";
      byCategory[cat] = (byCategory[cat] || 0) + Number(item.price || 0) * Number(item.quantity || 1);
    }));
    const labels = Object.keys(byCategory);
    const values = Object.values(byCategory);
    charts.categoryRevenue = new Chart(ctx, {
      type: "bar",
      data: { labels, datasets: [{ label: "Revenue (₹)", data: values, backgroundColor: labels.map((_, i) => PALETTE[i % PALETTE.length]), borderRadius: 8 }] },
      options: { ...baseOptions({ legend: false }), indexAxis: "y" }
    });
  }

  function renderCatalogueMixChart(products) {
    destroyChart("catalogueMix");
    const { text } = chartColors();
    const byCategory = {};
    products.forEach(p => (byCategory[p.category] = (byCategory[p.category] || 0) + 1));
    const labels = Object.keys(byCategory);
    const values = Object.values(byCategory);
    charts.catalogueMix = new Chart(document.getElementById("chart-catalogue-mix"), {
      type: "doughnut",
      data: { labels, datasets: [{ data: values, backgroundColor: labels.map((_, i) => PALETTE[i % PALETTE.length]), borderWidth: 2, borderColor: getComputedStyle(document.body).getPropertyValue("--surface") || "#fff" }] },
      options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: "right", labels: { boxWidth: 10, font: { size: 11 }, color: text } } } }
    });
  }

  // ---- Top products leaderboard ---------------------------------------------------
  function renderLeaderboard(products, orders) {
    const el = document.getElementById("leaderboard");
    const nameMap = {};
    products.forEach(p => (nameMap[p.id] = p));
    const qtyMap = {};
    orders.forEach(o => (o.items || []).forEach(item => {
      qtyMap[item.productId] = (qtyMap[item.productId] || 0) + Number(item.quantity || 1);
    }));
    const rows = Object.entries(qtyMap)
      .map(([id, qty]) => ({ id, qty, product: nameMap[id] }))
      .filter(r => r.product)
      .sort((a, b) => b.qty - a.qty)
      .slice(0, 6);

    if (!rows.length) {
      el.innerHTML = `<div class="empty-state" style="padding:24px 10px"><div class="glyph">🏆</div><p>Top products appear once orders are placed.</p></div>`;
      return;
    }
    const maxQty = rows[0].qty || 1;
    el.innerHTML = rows.map((r, i) => `
      <li>
        <span class="rank">${i + 1}</span>
        <span class="lb-icon">${r.product.icon || "🛍️"}</span>
        <div class="lb-info">
          <div class="name">${CloudCart.escapeHtml(r.product.name)}</div>
          <div class="lb-bar"><i style="width:${Math.round((r.qty / maxQty) * 100)}%"></i></div>
        </div>
        <span class="lb-units">${r.qty} sold</span>
      </li>`).join("");
  }

  function renderOrdersTable(orders) {
    const body = document.getElementById("orders-body");
    if (!orders.length) {
      body.innerHTML = `<tr><td colspan="6" style="text-align:center;color:var(--text-dim);padding:30px">No orders yet. <a href="/" style="color:var(--brand);font-weight:700">Place a demo order →</a></td></tr>`;
      return;
    }
    const sorted = [...orders].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)).slice(0, 10);
    body.innerHTML = sorted.map(o => `
      <tr>
        <td><b>${CloudCart.escapeHtml(o.orderId || "—")}</b></td>
        <td>${CloudCart.escapeHtml(o.userId || "—")}</td>
        <td>${(o.items || []).reduce((s, i) => s + Number(i.quantity || 1), 0)}</td>
        <td>${CloudCart.money(o.totalAmount)}</td>
        <td><span class="badge ${(o.status || "").toLowerCase() === "confirmed" ? "confirmed" : "pending"}">${CloudCart.escapeHtml(o.status || "PENDING")}</span></td>
        <td class="muted mono-cell">${o.createdAt ? new Date(o.createdAt).toLocaleString() : "—"}</td>
      </tr>`).join("");
  }

  // ---- Cluster health panel --------------------------------------------------------
  function renderHealthPanel() {
    const grid = document.getElementById("health-grid");
    grid.innerHTML = CloudCart.SERVICES.map(svc => `
      <div class="health-chip" id="health-${svc.key}">
        <div class="health-chip-top"><span class="dot pending"></span><span class="svc-name">${svc.icon} ${svc.label}</span></div>
        <span class="svc-meta">pinging…</span>
      </div>`).join("");

    let upCount = 0;
    CloudCart.pingServices((result) => {
      const chip = document.getElementById(`health-${result.key}`);
      if (!chip) return;
      chip.classList.toggle("is-down", result.status !== "up");
      chip.querySelector(".dot").className = "dot " + result.status;
      chip.querySelector(".svc-meta").textContent = result.status === "up" ? `${result.ms} ms · HTTP ${result.httpStatus}` : "unreachable";
      if (result.status === "up") upCount++;
      document.getElementById("health-summary").textContent = `${upCount}/${CloudCart.SERVICES.length} healthy`;
    });
  }

  function baseOptions(opts = {}) {
    const { grid, text } = chartColors();
    return {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { display: !!opts.legend, labels: { color: text } } },
      scales: {
        y: { beginAtZero: true, grid: { color: grid }, ticks: { color: text } },
        x: { grid: { display: false }, ticks: { color: text } }
      }
    };
  }

  function wrapEmpty(canvas, message) {
    const wrap = canvas.parentElement;
    wrap.innerHTML = `<div class="empty-state" style="padding:20px"><div class="glyph">📊</div><p>${message}</p></div>`;
  }

  // Re-render charts (no new API calls) so they pick up the new palette immediately
  // when the theme toggle is used, instead of waiting for the next refresh.
  const themeBtn = document.getElementById("theme-toggle");
  if (themeBtn) themeBtn.addEventListener("click", () => {
    renderRevenueChart(lastData.orders);
    renderInventoryChart(lastData.products, lastData.inventory);
    renderCategoryRevenueChart(lastData.products, lastData.orders);
    renderCatalogueMixChart(lastData.products);
  });

  document.getElementById("refresh-btn").onclick = load;

  // Cluster health pings refresh on a short cycle; the fuller KPI/chart/table
  // reload runs on a longer one so a workshop room watching this page sees
  // new orders (placed from the storefront) show up without hitting refresh.
  let tick = 0;
  setInterval(() => {
    tick++;
    fullCountdown = Math.max(0, fullCountdown - 1);
    document.getElementById("refresh-timer").textContent = `auto-refresh in ${fullCountdown}s`;
    if (tick % HEALTH_REFRESH_SECS === 0) renderHealthPanel();
    if (fullCountdown === 0) load();
  }, 1000);

  load();
})();
