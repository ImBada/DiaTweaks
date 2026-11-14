// Closing the port closes the host's stdin, which is what stops the request.
chrome.runtime.onConnect.addListener((port) => {
  const origin = new URL(port.sender.url).origin;
  port.onMessage.addListener((request) => {
    const host = chrome.runtime.connectNative('com.diapatches.passkeys');
    let answered = false;
    host.onMessage.addListener((response) => {
      answered = true;
      port.postMessage(response);
      host.disconnect();
    });
    host.onDisconnect.addListener(() => {
      if (answered) return;
      port.postMessage({ error: { name: 'NotAllowedError', message: chrome.runtime.lastError?.message ?? 'No reply from diapatch' } });
    });
    port.onDisconnect.addListener(() => host.disconnect());
    host.postMessage({ ...request, origin });
  });
});
