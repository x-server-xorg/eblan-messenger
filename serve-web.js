const http = require('http');
const fs = require('fs');
const path = require('path');
const net = require('net');

const WEB_DIR = path.join(__dirname, 'client', 'build', 'web');
const API_HOST = 'localhost';
const API_PORT = 3000;
const DESIRED_PORT = parseInt(process.env.PORT, 10) || 80;
const FALLBACK_PORT = 8080;

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
};

function handleRequest(req, res) {
  if (req.url.startsWith('/api/') || req.url.startsWith('/socket.io/')) {
    const options = {
      hostname: API_HOST,
      port: API_PORT,
      path: req.url,
      method: req.method,
      headers: { ...req.headers },
    };
    const proxyReq = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });
    proxyReq.on('error', () => {
      res.writeHead(502, { 'Content-Type': 'text/plain' });
      res.end('Server unavailable');
    });
    req.pipe(proxyReq);
    return;
  }

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
}

function handleUpgrade(req, socket, head) {
  if (!req.url.startsWith('/socket.io/') && !req.url.startsWith('/api/')) {
    socket.destroy();
    return;
  }

  let headerStr = `${req.method} ${req.url} HTTP/1.1\r\n`;
  for (let i = 0; i < (req.rawHeaders || []).length; i += 2) {
    headerStr += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
  }
  headerStr += '\r\n';

  const proxySocket = net.connect(API_PORT, API_HOST, () => {
    proxySocket.write(headerStr);
    if (head && head.length > 0) proxySocket.write(head);
    proxySocket.pipe(socket);
    socket.pipe(proxySocket);
  });
  proxySocket.on('error', () => socket.destroy());
  socket.on('error', () => proxySocket.destroy());
}

function createAndListen(port) {
  const srv = http.createServer(handleRequest);
  srv.on('upgrade', handleUpgrade);
  srv.on('error', (err) => {
    if (err.code === 'EACCES' && port === DESIRED_PORT) {
      console.log(`Port ${DESIRED_PORT} needs root, switching to ${FALLBACK_PORT}...`);
      createAndListen(FALLBACK_PORT);
    } else {
      console.error('Server error:', err.message);
      process.exit(1);
    }
  });
  srv.listen(port, () => {
    if (process.getuid && process.getuid() === 0) {
      try { process.setgid('nogroup'); process.setuid('nobody'); } catch (_) {}
    }
    console.log(`Web server running on http://localhost:${port}`);
    console.log(`Proxying /api/* and /socket.io/* to http://${API_HOST}:${API_PORT}`);
  });
}

createAndListen(DESIRED_PORT);
