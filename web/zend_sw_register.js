// Registers Zend's offline cache (zend_sw.js). A separate file because the CSP doesn't allow
// inline scripts. After Flutter has loaded its engine and fonts, it tells the worker which files
// this page used, so the next visit with no signal can open.
(function () {
  if (!('serviceWorker' in navigator)) return;
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('zend_sw.js').then(function () {
      return navigator.serviceWorker.ready;
    }).then(function (reg) {
      setTimeout(function () {
        if (!reg.active || !window.performance || !performance.getEntriesByType) return;
        var urls = performance.getEntriesByType('resource')
          .map(function (e) { return e.name; })
          .filter(function (u) { return u.indexOf(location.origin + '/') === 0; });
        reg.active.postMessage({ type: 'zend-cache-urls', urls: urls });
      }, 15000);
    }).catch(function () {});
  });
})();
