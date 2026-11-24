// Status-bar colour hand-off. index.html carries page-coloured theme-color tags
// for the moment before Flutter draws. Once it does, Flutter writes its own
// (MaterialApp.color in lib/app.dart, which follows the in-app theme toggle),
// so drop ours: browsers use the first matching tag, and ours come first.
window.addEventListener(
  'flutter-first-frame',
  function () {
    document.querySelectorAll('meta[data-boot-theme]').forEach(function (m) {
      m.remove();
    });
  },
  { once: true },
);
