(function () {
  if (!document || !document.body) return;
  if (document.getElementById('ob-video-tip')) return;
  var videos = document.querySelectorAll('video');
  if (!videos || videos.length === 0) return;
  var tip = document.createElement('div');
  tip.id = 'ob-video-tip';
  tip.textContent = 'OBrowser tip: Space=Play/Pause, F=Fullscreen';
  tip.style.position = 'fixed';
  tip.style.right = '14px';
  tip.style.bottom = '14px';
  tip.style.background = 'rgba(10,10,10,0.75)';
  tip.style.color = '#fff';
  tip.style.padding = '8px 10px';
  tip.style.borderRadius = '8px';
  tip.style.zIndex = '2147483647';
  document.body.appendChild(tip);
  setTimeout(function(){ if (tip.parentNode) tip.parentNode.removeChild(tip); }, 5000);
})();
