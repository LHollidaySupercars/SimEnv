// ============================================================
// SMP_AUTH.JS — V8SC Pit Wall
// Microsoft Entra ID authentication via MSAL.js
// Replaces the PIN screen with a proper Entra ID login.
//
// Requires MSAL.js loaded in index.html before this file:
//   <script src="https://alcdn.msauth.net/browser/2.38.3/js/msal-browser.min.js"></script>
//
// Users must have a supercars.com Microsoft account.
// Single tenant — no external accounts permitted.
// ============================================================

const SMP_AUTH = (() => {

  // ── MSAL CONFIG ───────────────────────────────────────────
  // Replace placeholders with your actual values from smp_config.js
  const msalConfig = {
    auth: {
      clientId:    SMP_CONFIG.AUTH.CLIENT_ID,
      authority:   'https://login.microsoftonline.com/' + SMP_CONFIG.AUTH.TENANT_ID,
      redirectUri: window.location.origin,
    },
    cache: {
      cacheLocation:        'sessionStorage',
      storeAuthStateInCookie: false,
    },
  };

  // Scope targeting your own Function App
  // api://<clientId>/user_impersonation issues a token for YOUR app
  const loginRequest = {
    scopes: ['api://' + SMP_CONFIG.AUTH.CLIENT_ID + '/user_impersonation'],
  };

  let _msalInstance = null;
  let _account      = null;
  let _token        = null;

  // ── INIT ─────────────────────────────────────────────────
  async function init() {
    _msalInstance = new msal.PublicClientApplication(msalConfig);
    await _msalInstance.initialize();

    // Check if returning from redirect login
    const response = await _msalInstance.handleRedirectPromise();
    if (response) {
      _account = response.account;
      _token   = response.accessToken;
    }

    // Check for existing cached account
    if (!_account) {
      const accounts = _msalInstance.getAllAccounts();
      if (accounts.length > 0) {
        _account = accounts[0];
        await refreshToken();
      }
    }

    return _account !== null;
  }

  // ── LOGIN — uses popup to avoid iframe redirect issues ────
  async function login() {
    try {
      const result = await _msalInstance.loginPopup(loginRequest);
      _account = result.account;
      _token   = result.accessToken;
      return true;
    } catch(e) {
      console.error('Login failed:', e);
      throw e;
    }
  }

  // ── REFRESH TOKEN ─────────────────────────────────────────
  async function refreshToken() {
    if (!_account) return null;
    try {
      const result = await _msalInstance.acquireTokenSilent({
        ...loginRequest,
        account: _account,
      });
      _token = result.accessToken;
      return _token;
    } catch(e) {
      try {
        const result = await _msalInstance.acquireTokenPopup({
          ...loginRequest,
          account: _account,
        });
        _token = result.accessToken;
        return _token;
      } catch(e2) {
        console.error('Token refresh failed:', e2);
        return null;
      }
    }
  }

  // ── LOGOUT ────────────────────────────────────────────────
  function logout() {
    if (_msalInstance && _account) {
      _msalInstance.logoutRedirect({ account: _account });
    }
  }

  // ── ACCESSORS ─────────────────────────────────────────────
  function getToken()   { return _token; }
  function getAccount() { return _account; }
  function isLoggedIn() { return _account !== null; }

  function getDisplayName() {
    if (!_account) return '';
    return _account.name || _account.username || '';
  }

  return { init, login, logout, getToken, getAccount, isLoggedIn, getDisplayName, refreshToken };
})();