const http = require('http');
const fs = require('fs');
const path = require('path');
const httpProxy = require('http-proxy');

const WEB_DIR = path.join(__dirname, 'client', 'build', 'web');
const API_PORT = 3000;
const WEB_PORT = parseInt(process.env.PORT, 10) || 80;

const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.map': 'application/json',
};

const proxy = httpProxy.createProxyServer({
  target: `http://localhost:${API_PORT}`,
  ws: true,
});

const server = http.createServer((req, res) => {
  // Proxy API and WebSocket requests
  if (req.url.startsWith('/api/') || req.url.startsWith('/socket.io/')) {
    proxy.web(req, res, { target: `http://localhost:${API_PORT}` }, (err) => {
      res.writeHead(502, { 'Content-Type': 'text/plain' });
      res.end('Bad Gateway');
    });
    return;
  }

  // Serve static files
  let filePath = path.join(WEB_DIR, req.url === '/' ? 'index.html' : req.url);

  if (!fs.existsSync(filePath)) {
    filePath = path.join(WEB_DIR, 'index.html');
  }

  const ext = path.extname(filePath);
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(500);
      res.end('Internal Server Error');
      return;
    }
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
});

// WebSocket proxy for Socket.IO
server.on('upgrade', (req, socket, head) => {
  if (req.url.startsWith('/socket.io/')) {
    proxy.ws(req, socket, head);
  } else {
    socket.destroy();
  }
});

server.listen(WEB_PORT, () => {
  console.log(`Web server running on http://localhost:${WEB_PORT}`);
  console.log(`Proxying /api/* and /socket.io/* to http://localhost:${API_PORT}`);
});
