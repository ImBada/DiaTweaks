const ports = new Map();
const reply = (id, response) => window.postMessage({ diaTweaksPasskey: 'response', id, response }, '*');

window.addEventListener('message', (event) => {
  if (event.source !== window) return;
  const { diaTweaksPasskey: type, id, kind, options } = event.data ?? {};
  if (type === 'cancel') {
    ports.get(id)?.disconnect();
    ports.delete(id);
    return;
  }
  if (type !== 'request') return;
  const port = chrome.runtime.connect();
  ports.set(id, port);
  port.onMessage.addListener((response) => {
    ports.delete(id);
    port.disconnect();
    reply(id, response);
  });
  port.onDisconnect.addListener(() => {
    const noWorker = chrome.runtime.lastError;
    if (!ports.delete(id)) return;
    // A worker from before ports existed answers messages only, and can't be cancelled.
    if (noWorker) chrome.runtime.sendMessage({ kind, options }, (response) => reply(id, response));
    else reply(id);
  });
  port.postMessage({ kind, options });
});
