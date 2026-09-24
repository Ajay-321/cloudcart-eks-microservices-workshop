(() => {
  CloudCart.renderNavbar("/signup");
  if (CloudCart.isLoggedIn()) window.location.href = "/dashboard";

  const form = document.getElementById("signup-form");
  const errorBox = document.getElementById("form-error");
  const submitBtn = document.getElementById("submit-btn");

  const passInput = document.getElementById("password");
  const passToggle = document.getElementById("pass-toggle");
  passToggle.onclick = () => {
    const show = passInput.type === "password";
    passInput.type = show ? "text" : "password";
    passToggle.textContent = show ? "🙈" : "👁️";
    passToggle.setAttribute("aria-label", show ? "Hide password" : "Show password");
  };

  // Simple client-side strength signal only — the real requirement (6+ chars)
  // is enforced by auth-service; this just gives faster feedback while typing.
  const strengthBars = Array.from(document.querySelectorAll("#strength-meter i"));
  const strengthLabel = document.getElementById("strength-label");
  passInput.addEventListener("input", () => {
    const v = passInput.value;
    let score = 0;
    if (v.length >= 6) score++;
    if (v.length >= 10 && /[0-9]/.test(v) && /[a-zA-Z]/.test(v)) score++;
    if (v.length >= 10 && /[^a-zA-Z0-9]/.test(v)) score++;
    const tier = score === 0 ? "" : score === 1 ? "weak" : score === 2 ? "ok" : "strong";
    strengthBars.forEach((bar, i) => {
      bar.className = i < score ? `on ${tier}` : "";
    });
    strengthLabel.textContent = !v.length
      ? "Use 6+ characters. Stored as a bcrypt hash, never in plain text."
      : tier === "weak" ? "Weak — meets the 6-character minimum."
      : tier === "ok" ? "Getting better — mix in numbers and letters."
      : tier === "strong" ? "Strong password."
      : "Keep going — 6 characters minimum.";
  });

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    errorBox.classList.remove("show");
    submitBtn.disabled = true;
    submitBtn.textContent = "Creating account…";
    try {
      const name = document.getElementById("name").value.trim();
      const email = document.getElementById("email").value.trim();
      const password = document.getElementById("password").value;
      const data = await CloudCart.api("/api/auth/signup", {
        method: "POST",
        body: JSON.stringify({ name, email, password })
      });
      CloudCart.setSession(data.token, data.user);
      CloudCart.toast(`Account created — welcome, ${data.user.name.split(" ")[0]}!`, "success");
      setTimeout(() => (window.location.href = "/dashboard"), 300);
    } catch (e) {
      errorBox.textContent = e.message;
      errorBox.classList.add("show");
      submitBtn.disabled = false;
      submitBtn.textContent = "Create account";
    }
  });
})();
