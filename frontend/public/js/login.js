(() => {
  CloudCart.renderNavbar("/login");
  if (CloudCart.isLoggedIn()) window.location.href = "/dashboard";

  const form = document.getElementById("login-form");
  const errorBox = document.getElementById("form-error");
  const submitBtn = document.getElementById("submit-btn");

  function params() { return new URLSearchParams(window.location.search); }

  const passInput = document.getElementById("password");
  const passToggle = document.getElementById("pass-toggle");
  passToggle.onclick = () => {
    const show = passInput.type === "password";
    passInput.type = show ? "text" : "password";
    passToggle.textContent = show ? "🙈" : "👁️";
    passToggle.setAttribute("aria-label", show ? "Hide password" : "Show password");
  };

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    errorBox.classList.remove("show");
    submitBtn.disabled = true;
    submitBtn.textContent = "Logging in…";
    try {
      const email = document.getElementById("email").value.trim();
      const password = document.getElementById("password").value;
      const data = await CloudCart.api("/api/auth/login", {
        method: "POST",
        body: JSON.stringify({ email, password })
      });
      CloudCart.setSession(data.token, data.user);
      CloudCart.toast(`Welcome back, ${data.user.name.split(" ")[0]}!`, "success");
      const redirect = params().get("redirect") || "/dashboard";
      setTimeout(() => (window.location.href = redirect), 300);
    } catch (e) {
      errorBox.textContent = e.message;
      errorBox.classList.add("show");
      submitBtn.disabled = false;
      submitBtn.textContent = "Log in";
    }
  });
})();
