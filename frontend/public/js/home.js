(() => {
  CloudCart.renderNavbar("/");

  const productsEl = document.getElementById("products");
  const chipsEl = document.getElementById("category-chips");
  const searchInput = document.getElementById("search-input");
  const resultCount = document.getElementById("result-count");
  const sortSelect = document.getElementById("sort-select");

  let allCategories = [];
  let activeCategory = "All";
  let searchTerm = "";
  let searchTimer = null;
  let wishlistOnly = false;
  let lastProducts = [];

  async function init() {
    try {
      const categories = await CloudCart.api("/api/products/categories");
      allCategories = ["All", ...categories];
      renderChips();
    } catch (e) {
      allCategories = ["All"];
    }
    await loadProducts();
    renderArchStrip();
  }

  function renderChips() {
    const categoryChips = allCategories.map(c =>
      `<button class="chip ${c === activeCategory ? "active" : ""}" data-cat="${CloudCart.escapeHtml(c)}">${CloudCart.escapeHtml(c)}</button>`
    ).join("");
    const wishlistChip = `<button class="chip wishlist-chip ${wishlistOnly ? "active" : ""}" id="wishlist-chip" title="Show only wishlisted items">♥ Wishlist</button>`;
    chipsEl.innerHTML = categoryChips + wishlistChip;
    chipsEl.querySelectorAll(".chip[data-cat]").forEach(btn => {
      btn.onclick = () => {
        activeCategory = btn.dataset.cat;
        renderChips();
        loadProducts();
      };
    });
    document.getElementById("wishlist-chip").onclick = () => {
      wishlistOnly = !wishlistOnly;
      renderChips();
      renderProducts(applyClientView(lastProducts));
    };
  }

  async function loadProducts() {
    const params = new URLSearchParams();
    if (activeCategory && activeCategory !== "All") params.set("category", activeCategory);
    if (searchTerm) params.set("q", searchTerm);
    productsEl.innerHTML = Array.from({ length: 4 }).map(() => `<div class="card skeleton" style="height:270px"></div>`).join("");
    try {
      const products = await CloudCart.api("/api/products/products?" + params.toString());
      lastProducts = products;
      renderProducts(applyClientView(lastProducts));
      document.getElementById("stat-categories").textContent = allCategories.length ? allCategories.length - 1 : "—";
      if (activeCategory === "All" && !searchTerm) {
        document.getElementById("stat-products").textContent = products.length;
      }
    } catch (e) {
      productsEl.innerHTML = `<div class="empty-state" style="grid-column:1/-1"><div class="glyph">⚠️</div><p>Could not load products.<br/>${CloudCart.escapeHtml(e.message)}</p></div>`;
    }
  }

  // Sorting and the wishlist filter are both client-side, so switching them
  // never needs a round trip back to product-service.
  function applyClientView(products) {
    let list = wishlistOnly ? products.filter(p => CloudCart.isWishlisted(p.id)) : [...products];
    const sortBy = sortSelect.value;
    if (sortBy === "price-asc") list.sort((a, b) => a.price - b.price);
    else if (sortBy === "price-desc") list.sort((a, b) => b.price - a.price);
    else if (sortBy === "rating") list.sort((a, b) => (b.rating || 0) - (a.rating || 0));
    else if (sortBy === "stock") list.sort((a, b) => (b.stock || 0) - (a.stock || 0));
    return list;
  }
  sortSelect.addEventListener("change", () => renderProducts(applyClientView(lastProducts)));

  function renderProducts(products) {
    resultCount.textContent = `${products.length} product${products.length === 1 ? "" : "s"} found`;
    if (!products.length) {
      productsEl.innerHTML = wishlistOnly
        ? `<div class="empty-state" style="grid-column:1/-1"><div class="glyph">♡</div><p>Nothing wishlisted yet.<br/>Tap the heart on a product to save it here.</p></div>`
        : `<div class="empty-state" style="grid-column:1/-1"><div class="glyph">🔍</div><p>No products match your search.</p></div>`;
      return;
    }
    productsEl.innerHTML = products.map(p => {
      const lowStock = Number(p.stock) > 0 && Number(p.stock) <= 10;
      const wished = CloudCart.isWishlisted(p.id);
      return `
      <article class="card" data-view="${p.id}" tabindex="0">
        <div class="card-media">
          <span class="card-tag">${CloudCart.escapeHtml(p.category || "")}</span>
          ${lowStock ? `<span class="card-stock-warn">Only ${p.stock} left</span>` : ""}
          ${p.icon || "🛍️"}
          <button class="wishlist-btn ${wished ? "active" : ""}" data-wish="${p.id}" title="${wished ? "Remove from wishlist" : "Add to wishlist"}">${wished ? "♥" : "♡"}</button>
        </div>
        <h3>${CloudCart.escapeHtml(p.name)}</h3>
        <p class="desc">${CloudCart.escapeHtml(p.description || "")}</p>
        <p class="rating">★ ${p.rating || "4.5"} <span class="count">rating</span></p>
        <div class="card-footer">
          <span class="price">${CloudCart.money(p.price)}</span>
          <button class="add-btn" data-add="${p.id}" title="Add to cart">＋</button>
        </div>
      </article>`;
    }).join("");

    productsEl.querySelectorAll("[data-add]").forEach(btn => {
      btn.onclick = (e) => {
        e.stopPropagation();
        const product = products.find(p => p.id === btn.dataset.add);
        CloudCart.addToCart(product, 1);
        CloudCart.toast(`Added ${product.name} to cart`, "success");
        renderCartDrawer();
      };
    });
    productsEl.querySelectorAll("[data-wish]").forEach(btn => {
      btn.onclick = (e) => {
        e.stopPropagation();
        const nowActive = CloudCart.toggleWishlist(btn.dataset.wish);
        btn.classList.toggle("active", nowActive);
        btn.textContent = nowActive ? "♥" : "♡";
        if (wishlistOnly && !nowActive) renderProducts(applyClientView(lastProducts));
      };
    });
    productsEl.querySelectorAll("[data-view]").forEach(card => {
      const open = () => openQuickView(products.find(p => p.id === card.dataset.view));
      card.addEventListener("click", open);
      card.addEventListener("keydown", (e) => { if (e.key === "Enter") open(); });
    });
  }

  searchInput.addEventListener("input", () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      searchTerm = searchInput.value.trim();
      loadProducts();
    }, 300);
  });

  // ---- Architecture strip (hero) — live status of the six services behind this page --
  function renderArchStrip() {
    const row = document.getElementById("arch-row");
    const nodes = CloudCart.SERVICES.map((svc, i) => `
      ${i > 0 ? '<div class="arch-connector"></div>' : ""}
      <div class="arch-node">
        <div class="glyph">${svc.icon}<span class="ping" data-ping="${svc.key}"></span></div>
        <span class="name">${svc.label.replace("-service", "")}</span>
      </div>`).join("");
    row.innerHTML = nodes;

    let upCount = 0, checked = 0;
    CloudCart.pingServices((result) => {
      checked++;
      const dot = row.querySelector(`[data-ping="${result.key}"]`);
      if (dot) dot.classList.add(result.status);
      if (result.status === "up") upCount++;
      updateLiveBadge(upCount, checked);
    });
  }

  function updateLiveBadge(upCount, checked) {
    const dot = document.getElementById("live-dot");
    const text = document.getElementById("live-text");
    const total = CloudCart.SERVICES.length;
    if (checked < total) { text.textContent = `Checking cluster… (${checked}/${total})`; return; }
    if (upCount === total) {
      dot.className = "live-dot up";
      text.textContent = `${upCount}/${total} services healthy · live from your cluster`;
    } else if (upCount === 0) {
      dot.className = "live-dot down";
      text.textContent = `Services unreachable — is docker compose up (or the pods) running?`;
    } else {
      dot.className = "live-dot degraded";
      text.textContent = `${upCount}/${total} services reachable`;
    }
  }

  // ---- Quick view modal ----------------------------------------------------------
  const quickviewModal = document.getElementById("quickview-modal");
  const quickviewBody = document.getElementById("quickview-body");

  function openQuickView(product) {
    if (!product) return;
    let qty = 1;
    const lowStock = Number(product.stock) > 0 && Number(product.stock) <= 10;
    const outOfStock = Number(product.stock) === 0;
    quickviewBody.innerHTML = `
      <button class="icon-btn quickview-close" id="qv-close" style="color:var(--text);border-color:var(--border)">✕</button>
      <div class="quickview-media">${product.icon || "🛍️"}</div>
      <div class="quickview-body">
        <span class="card-tag">${CloudCart.escapeHtml(product.category || "")}</span>
        <h3>${CloudCart.escapeHtml(product.name)}</h3>
        <p class="desc">${CloudCart.escapeHtml(product.description || "")}</p>
        <div class="quickview-meta">
          <span class="rating">★ ${product.rating || "4.5"}</span>
          <span>${outOfStock ? "Out of stock" : lowStock ? `Only ${product.stock} left` : `${product.stock} in stock`}</span>
        </div>
        <div class="quickview-foot">
          <span class="price">${CloudCart.money(product.price)}</span>
          <div style="display:flex;align-items:center;gap:10px">
            <div class="qty-stepper">
              <button id="qv-dec">−</button><span id="qv-qty">1</span><button id="qv-inc">＋</button>
            </div>
            <button class="btn btn-primary" id="qv-add" ${outOfStock ? "disabled" : ""}>Add to cart</button>
          </div>
        </div>
      </div>`;
    quickviewModal.classList.add("show");

    const qtyEl = document.getElementById("qv-qty");
    document.getElementById("qv-inc").onclick = () => { qty = Math.min(qty + 1, Number(product.stock) || 99); qtyEl.textContent = qty; };
    document.getElementById("qv-dec").onclick = () => { qty = Math.max(1, qty - 1); qtyEl.textContent = qty; };
    document.getElementById("qv-add").onclick = () => {
      CloudCart.addToCart(product, qty);
      CloudCart.toast(`Added ${qty} × ${product.name} to cart`, "success");
      renderCartDrawer();
      closeQuickView();
    };
    document.getElementById("qv-close").onclick = closeQuickView;
  }
  function closeQuickView() { quickviewModal.classList.remove("show"); }
  quickviewModal.addEventListener("click", (e) => { if (e.target === quickviewModal) closeQuickView(); });

  // ---- Cart drawer ------------------------------------------------------------
  const overlay = document.getElementById("cart-overlay");
  const drawer = document.getElementById("cart-drawer");
  const cartBody = document.getElementById("cart-body");

  function openDrawer() {
    renderCartDrawer();
    overlay.classList.add("show");
    drawer.classList.add("show");
  }
  function closeDrawer() {
    overlay.classList.remove("show");
    drawer.classList.remove("show");
  }
  document.getElementById("cart-close").onclick = closeDrawer;
  overlay.onclick = closeDrawer;

  function renderCartDrawer() {
    const cart = CloudCart.getCart();
    if (!cart.length) {
      cartBody.innerHTML = `<div class="empty-state"><div class="glyph">🛒</div><p>Your cart is empty.<br/>Add something from the catalogue.</p></div>`;
    } else {
      cartBody.innerHTML = cart.map(i => `
        <div class="cart-row">
          <div class="thumb">${i.icon}</div>
          <div class="info">
            <h4>${CloudCart.escapeHtml(i.name)}</h4>
            <div class="line-price">${CloudCart.money(i.price)} × ${i.qty} = ${CloudCart.money(i.price * i.qty)}</div>
          </div>
          <div class="qty-stepper">
            <button data-dec="${i.id}">−</button>
            <span>${i.qty}</span>
            <button data-inc="${i.id}">＋</button>
          </div>
        </div>`).join("");
      cartBody.querySelectorAll("[data-inc]").forEach(b => b.onclick = () => {
        const item = CloudCart.getCart().find(x => x.id === b.dataset.inc);
        CloudCart.setQty(b.dataset.inc, item.qty + 1);
        renderCartDrawer();
      });
      cartBody.querySelectorAll("[data-dec]").forEach(b => b.onclick = () => {
        const item = CloudCart.getCart().find(x => x.id === b.dataset.dec);
        CloudCart.setQty(b.dataset.dec, item.qty - 1);
        renderCartDrawer();
      });
    }
    document.getElementById("cart-subtotal").textContent = CloudCart.money(CloudCart.cartTotal());
    document.getElementById("cart-total").textContent = CloudCart.money(CloudCart.cartTotal());
    document.getElementById("checkout-btn").disabled = cart.length === 0;
  }

  // ---- Checkout: order-flow visualizer -------------------------------------------
  // The real order goes through one POST — order-service then calls inventory and
  // payment internally. Since that's genuinely the call sequence, we stage the four
  // steps as the request is in flight (with a short minimum dwell per step so the
  // flow is visible) rather than inventing data: the final result is always whatever
  // the API actually returned.
  const orderModal = document.getElementById("order-modal");
  const flowSteps = Array.from(document.querySelectorAll(".flow-step"));
  const flowTrack = document.getElementById("flow-track");

  function setFlow(activeIndex, doneUpTo, errored) {
    flowSteps.forEach((el, i) => {
      el.classList.toggle("done", i <= doneUpTo && !errored);
      el.classList.toggle("active", i === activeIndex && !errored);
      el.classList.toggle("error", errored && i === activeIndex);
    });
    flowTrack.style.width = `${(Math.max(0, doneUpTo) / (flowSteps.length - 1)) * 100}%`;
    flowTrack.classList.toggle("error", !!errored);
  }
  function wait(ms) { return new Promise(r => setTimeout(r, ms)); }

  document.getElementById("checkout-btn").onclick = async () => {
    const cart = CloudCart.getCart();
    if (!cart.length) return;
    const btn = document.getElementById("checkout-btn");
    btn.disabled = true;
    btn.textContent = "Placing order…";

    document.getElementById("order-modal-title").textContent = "Placing your order…";
    document.getElementById("order-modal-sub").textContent = "Watch it move through the order, inventory and payment services.";
    document.getElementById("order-modal-glyph").textContent = "📦";
    document.getElementById("order-meta").style.display = "none";
    document.getElementById("order-modal-close").style.display = "none";
    setFlow(1, 0, false);
    closeDrawer();
    orderModal.classList.add("show");

    const items = cart.map(i => ({ productId: i.id, quantity: i.qty, price: i.price }));
    const apiCall = CloudCart.api("/api/orders/orders", {
      method: "POST",
      body: JSON.stringify({ userId: CloudCart.currentUserId(), items })
    });

    try {
      await wait(450);
      setFlow(2, 1, false);
      await wait(450);
      setFlow(3, 2, false);
      const order = await apiCall;
      setFlow(3, 3, false);

      document.getElementById("order-modal-glyph").textContent = "✅";
      document.getElementById("order-modal-title").textContent = "Order confirmed!";
      document.getElementById("order-modal-sub").textContent = "Your demo order went through inventory + payment services successfully.";
      document.getElementById("order-meta").innerHTML = `
        <div><span>Order ID</span><b>${CloudCart.escapeHtml(order.orderId)}</b></div>
        <div><span>Payment ID</span><b>${CloudCart.escapeHtml(order.paymentId || "—")}</b></div>
        <div><span>Items</span><b>${cart.reduce((s, i) => s + i.qty, 0)}</b></div>
        <div><span>Total</span><b>${CloudCart.money(order.totalAmount)}</b></div>
        <div><span>Status</span><b>${CloudCart.escapeHtml(order.status || "CONFIRMED")}</b></div>`;
      document.getElementById("order-meta").style.display = "block";
      document.getElementById("order-modal-close").textContent = "Keep shopping";
      document.getElementById("order-modal-close").style.display = "block";
      CloudCart.clearCart();
    } catch (e) {
      setFlow(2, 1, true);
      document.getElementById("order-modal-glyph").textContent = "⚠️";
      document.getElementById("order-modal-title").textContent = "Checkout failed";
      document.getElementById("order-modal-sub").textContent = e.message;
      document.getElementById("order-modal-close").textContent = "Close";
      document.getElementById("order-modal-close").style.display = "block";
      CloudCart.toast("Checkout failed: " + e.message, "error");
    } finally {
      btn.disabled = false;
      btn.textContent = "Checkout";
    }
  };
  document.getElementById("order-modal-close").onclick = () => orderModal.classList.remove("show");

  document.addEventListener("click", (e) => {
    if (e.target.closest("#cart-toggle")) openDrawer();
  });

  init();
})();
