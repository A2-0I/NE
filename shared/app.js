// shared/app.js
// 목적: 공통 유틸만 제공하고, shared/sb.js가 만든 window.aiProcessor / window.aiProcessor.sb()를 절대 덮어쓰지 않습니다.

(function () {
  // ✅ 기존 네임스페이스 보존
  window.aiProcessor = window.aiProcessor || {};

  // ✅ sb.js가 이미 aiProcessor.sb()를 제공하므로, 여기서는 절대 재정의하지 않음
  // (혹시 sb.js가 누락된 경우를 대비한 최소 안전장치만 둠)
  if (typeof window.aiProcessor.sb !== "function") {
    console.warn("[AI PROCESSOR] shared/sb.js 가 로드되지 않았습니다. (aiProcessor.sb 없음)");
  }

  // ---------- Common helpers ----------
  window.aiProcessor.formatMoney = function (n) {
    const num = Number(n || 0);
    return num.toLocaleString("ko-KR");
  };

  window.aiProcessor.todayKey = function (d = new Date()) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  };

  // ---------- Auth / storage helpers ----------
  const KEY_LOGIN = "ai_processor_user_logged_in";
  const KEY_USER  = "ai_processor_current_user";

  window.aiProcessor.getStoredUser = function () {
    try {
      const raw = localStorage.getItem(KEY_USER);
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      return null;
    }
  };

  window.aiProcessor.setStoredUser = function (userObj) {
    if (!userObj) return;
    localStorage.setItem(KEY_LOGIN, "true");
    localStorage.setItem(KEY_USER, JSON.stringify(userObj));
  };

  window.aiProcessor.clearStoredUser = function () {
    localStorage.removeItem(KEY_LOGIN);
    localStorage.removeItem(KEY_USER);
  };

  window.aiProcessor.requireLogin = function (redirectTo = "index.html") {
    const ok = localStorage.getItem(KEY_LOGIN) === "true";
    if (!ok) {
      window.location.href = redirectTo;
      return false;
    }
    return true;
  };

  window.aiProcessor.logout = function (redirectTo = "index.html") {
    window.aiProcessor.clearStoredUser();
    window.location.href = redirectTo;
  };
})();
