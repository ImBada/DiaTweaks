// Mock Chromium WebAuthn surface for page.js, one fresh JavaScriptCore context per scenario.
// The driver evaluates this file, then the real page.js, then __harness.run(name).
const __harness = (() => {
  const state = { requests: [], cancels: [], listeners: [], manager: [], native: [], respond: null, env: null, result: null };

  // Chromium's WebAuthn operations stringify as [native code]; page.js tells them apart from a manager's.
  const nativeFns = new WeakSet();
  const realToString = Function.prototype.toString;
  const markNative = (fn) => {
    nativeFns.add(fn);
    return fn;
  };
  Function.prototype.toString = function () {
    return nativeFns.has(this) ? 'function ' + (this.name || '') + '() { [native code] }' : realToString.call(this);
  };

  const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const btoa = (input) => {
    const text = String(input);
    let out = '';
    for (let i = 0; i < text.length; i += 3) {
      const a = text.charCodeAt(i);
      const b = i + 1 < text.length ? text.charCodeAt(i + 1) : NaN;
      const c = i + 2 < text.length ? text.charCodeAt(i + 2) : NaN;
      const n = (a << 16) | ((b || 0) << 8) | (c || 0);
      out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + (isNaN(b) ? '=' : B64[(n >> 6) & 63]) + (isNaN(c) ? '=' : B64[n & 63]);
    }
    return out;
  };
  const atob = (input) => {
    const text = String(input).replace(/=+$/, '');
    let out = '';
    for (let i = 0; i < text.length; i += 4) {
      const chunk = text.slice(i, i + 4);
      const n = (B64.indexOf(chunk[0]) << 18) | (B64.indexOf(chunk[1]) << 12) | ((chunk.length > 2 ? B64.indexOf(chunk[2]) : 0) << 6) | (chunk.length > 3 ? B64.indexOf(chunk[3]) : 0);
      out += String.fromCharCode((n >> 16) & 255);
      if (chunk.length > 2) out += String.fromCharCode((n >> 8) & 255);
      if (chunk.length > 3) out += String.fromCharCode(n & 255);
    }
    return out;
  };

  class DOMException extends Error {
    constructor(message, name) {
      super(message);
      this.name = name || 'Error';
    }
  }

  const credentialJSON = (kind) =>
    kind === 'create'
      ? {
          id: 'helper-created',
          rawId: btoa('raw-created'),
          type: 'public-key',
          response: { clientDataJSON: btoa('cdj'), attestationObject: btoa('att'), authenticatorData: btoa('ad'), publicKey: btoa('pk'), publicKeyAlgorithm: -7, transports: ['internal'] },
          clientExtensionResults: {},
        }
      : {
          id: 'helper-signed',
          rawId: btoa('raw-signed'),
          type: 'public-key',
          response: { clientDataJSON: btoa('cdj'), authenticatorData: btoa('ad'), signature: btoa('sig'), userHandle: btoa('uh') },
          clientExtensionResults: {},
        };

  const deliver = (message) => {
    for (const listener of state.listeners.slice()) listener({ source: window, data: message });
  };

  const window = {
    addEventListener(type, fn) {
      if (type === 'message') state.listeners.push(fn);
    },
    removeEventListener(type, fn) {
      const i = state.listeners.indexOf(fn);
      if (i >= 0) state.listeners.splice(i, 1);
    },
    postMessage(data) {
      if (data?.diaTweaksPasskey === 'cancel') return void state.cancels.push(data);
      if (data?.diaTweaksPasskey !== 'request') return;
      state.requests.push(data);
      const response = (state.respond || ((request) => ({ credential: credentialJSON(request.kind) })))(data);
      if (response) deliver({ diaTweaksPasskey: 'response', id: data.id, response });
    },
  };

  function AuthenticatorAttestationResponse() {}
  function AuthenticatorAssertionResponse() {}

  const install = () => {
    function CredentialsContainer() {}
    const proto = CredentialsContainer.prototype;
    const nativeGet = markNative(function get(options) {
      state.native.push(['get', options]);
      return Promise.resolve({ id: 'native-get' });
    });
    const nativeCreate = markNative(function create(options) {
      state.native.push(['create', options]);
      return Promise.resolve({ id: 'native-create' });
    });
    Object.defineProperty(proto, 'get', { value: nativeGet, writable: true, enumerable: true, configurable: true });
    Object.defineProperty(proto, 'create', { value: nativeCreate, writable: true, enumerable: true, configurable: true });

    function PublicKeyCredential() {}
    PublicKeyCredential.isConditionalMediationAvailable = markNative(function isConditionalMediationAvailable() {
      state.native.push(['isConditional']);
      return Promise.resolve(true);
    });
    PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = markNative(function isUserVerifyingPlatformAuthenticatorAvailable() {
      state.native.push(['isUVPAA']);
      return Promise.resolve(false);
    });

    globalThis.CredentialsContainer = CredentialsContainer;
    globalThis.PublicKeyCredential = PublicKeyCredential;
    globalThis.AuthenticatorAttestationResponse = AuthenticatorAttestationResponse;
    globalThis.AuthenticatorAssertionResponse = AuthenticatorAssertionResponse;
    globalThis.navigator = { credentials: new CredentialsContainer() };
    globalThis.window = window;
    globalThis.btoa = btoa;
    globalThis.atob = atob;
    globalThis.DOMException = DOMException;

    return { CredentialsContainer, PublicKeyCredential, nativeGet, nativeCreate };
  };

  const assert = (condition, message) => {
    if (!condition) throw new Error(message);
  };

  const managerGet = (options) => {
    state.manager.push(['get', options]);
    return Promise.resolve({ id: 'manager-get' });
  };
  const managerCreate = (options) => {
    state.manager.push(['create', options]);
    return Promise.resolve({ id: 'manager-create' });
  };

  const scenarios = {
    // 1. Untouched Chromium: the tweak intercepts get/create and reports autofill off.
    vanilla: {
      async check(env) {
        const credentials = navigator.credentials;
        assert(!Object.prototype.hasOwnProperty.call(credentials, 'get'), 'page.js must not shadow navigator.credentials.get');
        assert(!Object.prototype.hasOwnProperty.call(credentials, 'create'), 'page.js must not shadow navigator.credentials.create');
        assert(env.CredentialsContainer.prototype.get !== env.nativeGet, 'page.js patches CredentialsContainer.prototype.get');
        assert(env.CredentialsContainer.prototype.create !== env.nativeCreate, 'page.js patches CredentialsContainer.prototype.create');

        const signed = await credentials.get({ publicKey: { challenge: new Uint8Array([1]) } });
        assert(signed.id === 'helper-signed', 'non-conditional get goes to the helper: ' + signed.id);
        assert(state.requests.length === 1 && state.requests[0].kind === 'get', 'one helper get request');
        assert(state.requests[0].options.challenge === 'AQ', 'options serialized as base64url: ' + state.requests[0].options.challenge);
        assert(signed.response.signature instanceof ArrayBuffer && signed.response.signature.byteLength === 3, 'signature decoded to an ArrayBuffer');
        assert(signed.type === 'public-key' && signed.rawId instanceof ArrayBuffer, 'credential shape');

        const created = await credentials.create({ publicKey: { challenge: new Uint8Array([2]) } });
        assert(created.id === 'helper-created', 'create goes to the helper: ' + created.id);
        assert(state.requests.length === 2 && state.requests[1].kind === 'create', 'one helper create request');

        const conditional = await credentials.get({ publicKey: { challenge: new Uint8Array([3]) }, mediation: 'conditional' });
        assert(conditional.id === 'native-get', 'conditional get passes through to Chromium');
        const password = await credentials.get({ password: true });
        assert(password.id === 'native-get', 'non-publicKey get passes through to Chromium');
        assert(state.native.filter(([name]) => name === 'get').length === 2, 'native get called twice');

        assert((await PublicKeyCredential.isConditionalMediationAvailable()) === false, 'autofill reported off');
        assert((await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()) === true, 'platform authenticator reported on');
      },
    },

    // 2. Manager before page.js, own properties on navigator.credentials: the tweak steps aside.
    managerBeforeOwnProperty: {
      setup(env) {
        navigator.credentials.get = managerGet;
        navigator.credentials.create = managerCreate;
      },
      async check(env) {
        const credentials = navigator.credentials;
        assert(credentials.get === managerGet, 'manager own get kept');
        assert(credentials.create === managerCreate, 'manager own create kept');
        assert(env.CredentialsContainer.prototype.get === env.nativeGet, 'prototype get untouched');
        assert(env.CredentialsContainer.prototype.create === env.nativeCreate, 'prototype create untouched');
        assert((await PublicKeyCredential.isConditionalMediationAvailable()) === true, 'manager autofill left on');
        assert((await credentials.get({ publicKey: {} })).id === 'manager-get', 'manager handles get');
        assert((await credentials.create({ publicKey: {} })).id === 'manager-create', 'manager handles create');
        assert(state.requests.length === 0, 'helper never asked');
      },
    },

    // 3. Manager before page.js, CredentialsContainer.prototype assigned: the tweak steps aside.
    managerBeforePrototype: {
      setup(env) {
        env.CredentialsContainer.prototype.get = managerGet;
        env.CredentialsContainer.prototype.create = managerCreate;
      },
      async check(env) {
        assert(env.CredentialsContainer.prototype.get === managerGet, 'manager prototype get kept');
        assert(env.CredentialsContainer.prototype.create === managerCreate, 'manager prototype create kept');
        assert(!Object.prototype.hasOwnProperty.call(navigator.credentials, 'get'), 'no own get installed over the manager');
        assert((await PublicKeyCredential.isConditionalMediationAvailable()) === true, 'manager autofill left on');
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'manager-get', 'manager handles get');
        assert((await navigator.credentials.create({ publicKey: {} })).id === 'manager-create', 'manager handles create');
        assert(state.requests.length === 0, 'helper never asked');
      },
    },

    // 4. Same, installed with Object.defineProperty.
    managerBeforePrototypeDefineProperty: {
      setup(env) {
        Object.defineProperty(env.CredentialsContainer.prototype, 'get', { value: managerGet, writable: true, configurable: true });
        Object.defineProperty(env.CredentialsContainer.prototype, 'create', { value: managerCreate, writable: true, configurable: true });
      },
      async check(env) {
        assert(env.CredentialsContainer.prototype.get === managerGet, 'manager prototype get kept');
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'manager-get', 'manager handles get');
        assert(state.requests.length === 0, 'helper never asked');
      },
    },

    // 5. Manager before page.js that hooked only create: the tweak still steps aside entirely.
    managerBeforeCreateOnly: {
      setup() {
        navigator.credentials.create = managerCreate;
      },
      async check(env) {
        assert(navigator.credentials.create === managerCreate, 'manager own create kept');
        assert(env.CredentialsContainer.prototype.get === env.nativeGet, 'prototype get untouched');
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'native-get', 'get left to Chromium');
        assert(state.requests.length === 0, 'helper never asked');
      },
    },

    // 6. Manager after page.js wrapping navigator.credentials: it runs outermost and delegates.
    managerAfterOwnProperty: {
      async check() {
        const credentials = navigator.credentials;
        const innerGet = credentials.get;
        const innerCreate = credentials.create;
        credentials.get = (options) => {
          state.manager.push(['get', options]);
          return innerGet(options);
        };
        credentials.create = (options) => {
          state.manager.push(['create', options]);
          return innerCreate(options);
        };
        assert((await credentials.get({ publicKey: {} })).id === 'helper-signed', 'manager delegates to the helper');
        assert((await credentials.create({ publicKey: {} })).id === 'helper-created', 'manager delegates create to the helper');
        assert(state.manager.length === 2, 'manager ran outermost');
        assert((await PublicKeyCredential.isConditionalMediationAvailable()) === true, 'manager autofill on');
      },
    },

    // 7. Manager after page.js patching CredentialsContainer.prototype: not shadowed, it runs.
    managerAfterPrototype: {
      async check(env) {
        const proto = env.CredentialsContainer.prototype;
        const innerGet = proto.get;
        const innerCreate = proto.create;
        proto.get = (options) => {
          state.manager.push(['get', options]);
          return innerGet(options);
        };
        proto.create = (options) => {
          state.manager.push(['create', options]);
          return innerCreate(options);
        };
        assert(!Object.prototype.hasOwnProperty.call(navigator.credentials, 'get'), 'no own property shadows the prototype');
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'helper-signed', 'manager prototype hook reached and delegates');
        assert((await navigator.credentials.create({ publicKey: {} })).id === 'helper-created', 'manager prototype create hook reached');
        assert(state.manager.length === 2, 'manager ran');
        assert((await PublicKeyCredential.isConditionalMediationAvailable()) === true, 'manager autofill on');
      },
    },

    // 8. Manager after page.js that answers on the prototype itself: its result wins.
    managerAfterPrototypeOwn: {
      async check(env) {
        env.CredentialsContainer.prototype.get = () => Promise.resolve({ id: 'manager-get' });
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'manager-get', 'manager result wins');
        assert(state.requests.length === 0, 'helper not asked');
        assert((await PublicKeyCredential.isConditionalMediationAvailable()) === true, 'manager autofill on');
      },
    },

    // 9. Manager after page.js that answers on navigator.credentials itself: its result wins.
    managerAfterOwnPropertyOwn: {
      async check() {
        navigator.credentials.get = () => Promise.resolve({ id: 'manager-get' });
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'manager-get', 'manager result wins');
        assert(state.requests.length === 0, 'helper not asked');
        assert((await PublicKeyCredential.isConditionalMediationAvailable()) === true, 'manager autofill on');
      },
    },

    // 10. page.js injected twice: the second run steps aside instead of wrapping itself.
    pageTwice: {
      repeat: 1,
      async check(env) {
        const patched = env.CredentialsContainer.prototype.get;
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'helper-signed', 'still one helper hop');
        assert(state.requests.length === 1, 'exactly one helper request: ' + state.requests.length);
        assert(env.CredentialsContainer.prototype.get === patched, 'second run left the first patch in place');
      },
    },

    // 11. Manager before page.js that only advertises conditional mediation: passkeys still work.
    managerBeforeConditionalOnly: {
      setup() {
        PublicKeyCredential.isConditionalMediationAvailable = () => Promise.resolve(true);
      },
      async check(env) {
        assert(env.CredentialsContainer.prototype.get !== env.nativeGet, 'page.js still activates');
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'helper-signed', 'get goes to the helper');
        assert((await PublicKeyCredential.isConditionalMediationAvailable()) === false, 'autofill off while the tweak is outermost');
      },
    },

    // 12. A prototype page.js cannot write to: it bails without a partial patch.
    frozenPrototype: {
      setup(env) {
        Object.defineProperty(env.CredentialsContainer.prototype, 'get', { value: env.nativeGet, writable: false, configurable: false });
      },
      async check(env) {
        assert(env.CredentialsContainer.prototype.get === env.nativeGet, 'get left alone');
        assert(env.CredentialsContainer.prototype.create === env.nativeCreate, 'create left alone');
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'native-get', 'get left to Chromium');
        assert(state.requests.length === 0, 'helper never asked');
      },
    },

    // 13. No CredentialsContainer global: page.js returns quietly.
    missingGlobals: {
      setup() {
        delete globalThis.CredentialsContainer;
      },
      async check(env) {
        assert(env.CredentialsContainer.prototype.get === env.nativeGet, 'get left alone');
        assert((await navigator.credentials.get({ publicKey: {} })).id === 'native-get', 'get left to Chromium');
        assert(state.requests.length === 0, 'helper never asked');
      },
    },

    // 14. No navigator.credentials (a non-secure context): page.js returns quietly.
    missingCredentials: {
      setup() {
        delete navigator.credentials;
      },
      async check(env) {
        assert(env.CredentialsContainer.prototype.get === env.nativeGet, 'get left alone');
        assert(env.CredentialsContainer.prototype.create === env.nativeCreate, 'create left alone');
        assert(state.requests.length === 0, 'helper never asked');
      },
    },
  };

  const setup = (name) => {
    const scenario = scenarios[name];
    if (!scenario) throw new Error('unknown scenario ' + name);
    state.env = install();
    if (scenario.setup) scenario.setup(state.env);
    return scenario.repeat || 0;
  };

  const run = (name) => {
    const scenario = scenarios[name];
    state.result = { ok: false, error: 'not run' };
    return (async () => {
      try {
        await scenario.check(state.env);
        state.result = { ok: true, error: '' };
      } catch (error) {
        state.result = { ok: false, error: String((error && error.message) || error) };
      }
    })();
  };

  return {
    names: () => Object.keys(scenarios).join(','),
    setup,
    run,
    result: () => JSON.stringify(state.result),
  };
})();
