/* ===========================================================================
   CloudCart — shared client utilities, loaded on every page.
   Handles: API calls, auth session (localStorage), cart + wishlist state,
   the navbar, theme (light / control-room dark), toasts, and a small helper
   for live-pinging the six backend microservices. Keeping this in one place
   is what makes the four pages (Home, Login, Signup, Dashboard) feel like
   one connected app instead of four disconnected demos.
=========================================================================== */

const CloudCart = (() => {
  const AUTH_KEY = "cloudcart_session";
  const CART_KEY = "cloudcart_cart";
  const GUEST_KEY = "cloudcart_guest_id";
  const WISHLIST_KEY = "cloudcart_wishlist";
  const THEME_KEY = "cloudcart_theme";

  // The six backend microservices, reachable through the frontend's own
  // /api/* proxy (same origin, so no CORS setup needed on the client).
  const SERVICES = [
    { key: "product", label: "product-service", path: "/api/products/health", icon: "🛍️" },
    { key: "inventory", label: "inventory-service", path: "/api/inventory/health", icon: "📦" },
    { key: "cart", label: "cart-service", path: "/api/cart/health", icon: "🧺" },
    { key: "order", label: "order-service", path: "/api/orders/health", icon: "🧾" },
    { key: "payment", label: "payment-service", path: "/api/payments/health", icon: "💳" },
    { key: "auth", label: "auth-service", path: "/api/auth/health", icon: "🔐" }
  ];

  // ---- fetch helper -------------------------------------------------------
  async function api(path, options = {}) {
    const session = getSession();
    const headers = Object.assign({ "Content-Type": "application/json" }, options.headers || {});
    if (session && session.token) headers.Authorization = "Bearer " + session.token;
    const res = await fetch(path, Object.assign({}, options, { headers }));
    const text = await res.text();
    let data;
    try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
    if (!res.ok) {
      const message = (data && (data.error || data.detail)) || `Request failed (${res.status})`;
      throw new Error(message);
    }
    return data;
  }

  // ---- money ---------------------------------------------------------------
  function money(n) {
    return "₹" + Number(n || 0).toLocaleString("en-IN");
  }

  // ---- session / auth --------------------------------------------------------
  function getSession() {
    try { return JSON.parse(localStorage.getItem(AUTH_KEY) || "null"); } catch { return null; }
  }
  function setSession(token, user) {
    localStorage.setItem(AUTH_KEY, JSON.stringify({ token, user }));
  }
  function clearSession() {
    localStorage.removeItem(AUTH_KEY);
  }
  function isLoggedIn() { return !!getSession(); }

  // Every shopper — guest or signed in — gets a stable id so cart/orders work
  // before they ever create an account.
  function currentUserId() {
    const session = getSession();
    if (session && session.user) return session.user.userId;
    let guestId = localStorage.getItem(GUEST_KEY);
    if (!guestId) {
      guestId = "guest-" + Math.random().toString(36).slice(2, 10);
      localStorage.setItem(GUEST_KEY, guestId);
    }
    return guestId;
  }

  // ---- cart (client-side, per browser) ----------------------------------------
  function getCart() {
    try { return JSON.parse(localStorage.getItem(CART_KEY) || "[]"); } catch { return []; }
  }
  function saveCart(items) {
    localStorage.setItem(CART_KEY, JSON.stringify(items));
    updateCartBadge();
  }
  function addToCart(product, qty = 1) {
    const cart = getCart();
    const existing = cart.find(i => i.id === product.id);
    if (existing) existing.qty += qty;
    else cart.push({ id: product.id, name: product.name, price: product.price, icon: product.icon || "🛍️", qty });
    saveCart(cart);
    return cart;
  }
  function setQty(productId, qty) {
    let cart = getCart();
    if (qty <= 0) cart = cart.filter(i => i.id !== productId);
    else cart = cart.map(i => (i.id === productId ? Object.assign({}, i, { qty }) : i));
    saveCart(cart);
    return cart;
  }
  function removeFromCart(productId) {
    const cart = getCart().filter(i => i.id !== productId);
    saveCart(cart);
    return cart;
  }
  function clearCart() { saveCart([]); }
  function cartCount() { return getCart().reduce((sum, i) => sum + i.qty, 0); }
  function cartTotal() { return getCart().reduce((sum, i) => sum + i.qty * i.price, 0); }

  function updateCartBadge() {
    document.querySelectorAll("[data-cart-count]").forEach(el => {
      const count = cartCount();
      el.textContent = count;
      el.style.display = count > 0 ? "flex" : "none";
    });
  }

  // ---- wishlist (client-side, per browser) ------------------------------------
  function getWishlist() {
    try { return JSON.parse(localStorage.getItem(WISHLIST_KEY) || "[]"); } catch { return []; }
  }
  function isWishlisted(productId) { return getWishlist().includes(productId); }
  function toggleWishlist(productId) {
    let list = getWishlist();
    if (list.includes(productId)) list = list.filter(id => id !== productId);
    else list = [...list, productId];
    localStorage.setItem(WISHLIST_KEY, JSON.stringify(list));
    return list.includes(productId);
  }

  // ---- theme (light storefront / control-room dark) ---------------------------
  function getTheme() {
    return localStorage.getItem(THEME_KEY) || "light";
  }
  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    document.querySelectorAll("[data-theme-toggle]").forEach(btn => {
      btn.textContent = theme === "dark" ? "☀️" : "🌙";
      btn.setAttribute("aria-label", theme === "dark" ? "Switch to light mode" : "Switch to dark mode");
    });
  }
  function setTheme(theme) {
    localStorage.setItem(THEME_KEY, theme);
    applyTheme(theme);
  }
  function toggleTheme() {
    const next = getTheme() === "dark" ? "light" : "dark";
    setTheme(next);
    return next;
  }
  // Applied immediately (before navbar renders) so there's no flash of the wrong theme.
  applyTheme(getTheme());

  // ---- live microservice health ------------------------------------------------
  // Pings every backend service's own /health route through the frontend's
  // same-origin proxy and times the round trip. Used by the architecture strip
  // on the homepage and the cluster health panel on the dashboard.
  async function pingServices(onEach) {
    const results = await Promise.all(SERVICES.map(async (svc) => {
      const start = performance.now();
      try {
        const res = await fetch(svc.path, { cache: "no-store" });
        const ms = Math.round(performance.now() - start);
        const ok = res.ok;
        const result = { ...svc, status: ok ? "up" : "down", ms, httpStatus: res.status };
        if (onEach) onEach(result);
        return result;
      } catch (e) {
        const result = { ...svc, status: "down", ms: null, httpStatus: null };
        if (onEach) onEach(result);
        return result;
      }
    }));
    return results;
  }

  // ---- animated counters -------------------------------------------------------
  // Counts a number element up from its current value to `target` — used on the
  // dashboard KPI cards so a refresh reads as a live feed rather than a page swap.
  function countUp(el, target, opts = {}) {
    const format = opts.format || (n => Math.round(n).toLocaleString("en-IN"));
    const duration = opts.duration || 700;
    const start = 0;
    const startTime = performance.now();
    function frame(now) {
      const p = Math.min(1, (now - startTime) / duration);
      const eased = 1 - Math.pow(1 - p, 3);
      el.textContent = (opts.prefix || "") + format(start + (target - start) * eased);
      if (p < 1) requestAnimationFrame(frame);
      else el.textContent = (opts.prefix || "") + format(target);
    }
    requestAnimationFrame(frame);
  }

  // ---- toasts ---------------------------------------------------------------
  function toast(message, type = "") {
    let stack = document.getElementById("toast-stack");
    if (!stack) {
      stack = document.createElement("div");
      stack.id = "toast-stack";
      document.body.appendChild(stack);
    }
    const el = document.createElement("div");
    el.className = "toast" + (type ? " " + type : "");
    el.textContent = message;
    stack.appendChild(el);
    setTimeout(() => el.remove(), 3200);
  }

  // ---- navbar -----------------------------------------------------------------
  function renderNavbar(activePath) {
    const mount = document.getElementById("site-header");
    if (!mount) return;
    const session = getSession();

    const authArea = session
      ? `<div class="user-chip" id="user-chip">
           <span class="avatar">${(session.user.name || "U").charAt(0).toUpperCase()}</span>
           <span>${escapeHtml((session.user.name || "").split(" ")[0] || "Account")}</span>
         </div>`
      : `<a href="/login" class="btn btn-ghost btn-sm">Log in</a>
         <a href="/signup" class="btn btn-primary btn-sm">Sign up</a>`;

    mount.innerHTML = `
      <nav class="navbar">
        <div class="container">
          <button class="hamburger" id="hamburger-btn" aria-label="Menu">☰</button>
          <a href="/" class="brand"><span class="logo-mark">☁️</span> CloudCart</a>
          <div class="nav-links" id="nav-links">
            <a href="/" data-path="/">Catalogue</a>
            <a href="/dashboard" data-path="/dashboard">Dashboard</a>
          </div>
          <div class="nav-right">
            <button class="icon-btn" id="theme-toggle" data-theme-toggle aria-label="Toggle theme">🌙</button>
            <button class="icon-btn" id="cart-toggle" aria-label="Cart">
              🛒<span class="cart-badge" data-cart-count style="display:none">0</span>
            </button>
            ${authArea}
          </div>
        </div>
      </nav>`;

    mount.querySelectorAll(`[data-path="${activePath}"]`).forEach(a => a.classList.add("active"));
    applyTheme(getTheme());

    const hamburger = document.getElementById("hamburger-btn");
    const navLinks = document.getElementById("nav-links");
    if (hamburger) hamburger.onclick = () => navLinks.classList.toggle("mobile-open");

    const themeBtn = document.getElementById("theme-toggle");
    if (themeBtn) themeBtn.onclick = () => toggleTheme();

    const chip = document.getElementById("user-chip");
    if (chip) chip.onclick = () => {
      if (confirm("Log out of CloudCart?")) {
        clearSession();
        toast("Signed out", "success");
        setTimeout(() => (window.location.href = "/"), 400);
      }
    };

    updateCartBadge();
    return { cartToggleEl: document.getElementById("cart-toggle") };
  }

  function escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, m => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[m]));
  }

  function requireAuth(redirectTo) {
    if (!isLoggedIn()) {
      window.location.href = "/login?redirect=" + encodeURIComponent(redirectTo || "/dashboard");
      return false;
    }
    return true;
  }

  return {
    api, money, escapeHtml, SERVICES,
    getSession, setSession, clearSession, isLoggedIn, currentUserId, requireAuth,
    getCart, addToCart, setQty, removeFromCart, clearCart, cartCount, cartTotal,
    getWishlist, isWishlisted, toggleWishlist,
    getTheme, setTheme, toggleTheme,
    pingServices, countUp,
    toast, renderNavbar
  };
})();
