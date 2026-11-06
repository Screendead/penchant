// mockshot.mjs's [js] for the sweep state: stubs the mock-up's frame clock, steps back a day and holds the frame
// 500 ms in (the 200 ms contract, then half the 600 ms sweep), matching the app's render of the same moment.
(async () => {
  let vt = performance.now();
  const q = [];
  window.requestAnimationFrame = f => { q.push(f); return q.length; };
  performance.now = () => vt;
  const s = [...document.querySelectorAll('.screen')].find(e => e.childElementCount);
  s.querySelector('[aria-label="Previous day"]').click();
  const end = vt + 500;
  while (vt < end) {
    vt = Math.min(end, vt + 1000 / 60);
    q.splice(0).forEach(f => f(vt));
    await new Promise(r => setTimeout(r, 5));
  }
  q.splice(0).forEach(f => f(vt));
})()
