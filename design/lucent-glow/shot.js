const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1420, height: 980 }, deviceScaleFactor: 2 });
  await p.goto('file://' + __dirname + '/mock.html');
  await p.waitForTimeout(800);
  await p.screenshot({ path: __dirname + '/lucent-glow-mockups.png' });
  await b.close();
})();
