(function () {
  if (!document || !document.body) return;
  if (document.body.dataset.obReaderApplied === '1') return;
  document.body.dataset.obReaderApplied = '1';
  var main = document.querySelector('article') || document.querySelector('main');
  if (!main) return;
  main.style.maxWidth = '840px';
  main.style.margin = '24px auto';
  main.style.lineHeight = '1.75';
})();
