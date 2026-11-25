// Loaded from <head> before Flutter. Two jobs at the edges of the screen:
//
// 1. Status-bar colour hand-off. index.html carries page-coloured theme-color
//    tags for the moment before Flutter draws. Once it does, Flutter writes its
//    own (MaterialApp.color in lib/app.dart, which follows the in-app theme
//    toggle), so drop ours: browsers use the first matching tag, and ours come
//    first.
//
// 2. Safe area. Flutter replaces any viewport tag with its own, without
//    viewport-fit=cover, and without that iOS reports env(safe-area-inset-*)
//    as 0. Add it as soon as Flutter inserts the tag, so the app can read the
//    home-indicator inset (lib/src/design/web_safe_area_web.dart) and keep the
//    tab bar clear of it.
(function () {
  window.addEventListener(
    'flutter-first-frame',
    function () {
      document.querySelectorAll('meta[data-boot-theme]').forEach(function (m) {
        m.remove();
      });
    },
    { once: true },
  );

  function coverViewport() {
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta || /viewport-fit/.test(meta.content)) return;
    meta.content = meta.content + ', viewport-fit=cover';
    // Make Flutter re-measure, so the first screen gets the inset too.
    window.dispatchEvent(new Event('resize'));
  }
  new MutationObserver(coverViewport).observe(document.head, { childList: true });
  coverViewport();
})();
