const http = require('http');
const port = process.env.PORT || 8080;

http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify({
    status: 'ok',
    service: 'claude-code-env',
    timestamp: new Date().toISOString()
  }));
}).listen(port, () => {
  console.log(`Claude Code environment health check listening on :${port}`);
});
