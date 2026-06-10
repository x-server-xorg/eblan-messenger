import express from 'express';
import cors from 'cors';
import http from 'http';
import { Server as SocketIOServer } from 'socket.io';
import path from 'path';
import fs from 'fs';
import { config } from './config';
import authRoutes from './routes/auth';
import userRoutes from './routes/users';
import messageRoutes from './routes/messages';
import fileRoutes from './routes/files';
import { setupWebSocket } from './websocket/handler';

const app = express();
const server = http.createServer(app);
const io = new SocketIOServer(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
});

app.use(cors());
app.use(express.json());

if (!fs.existsSync(config.uploadDir)) {
  fs.mkdirSync(config.uploadDir, { recursive: true });
}

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/files', fileRoutes);

setupWebSocket(io);

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', version: '1.0.0' });
});

const webBuildPath = path.join(__dirname, '../../client/build/web');
if (fs.existsSync(webBuildPath)) {
  app.use(express.static(webBuildPath));
  app.use((req, res, next) => {
    if (req.method === 'GET' && !req.path.startsWith('/api/') && !req.path.startsWith('/socket.io/')) {
      res.sendFile(path.join(webBuildPath, 'index.html'));
    } else {
      next();
    }
  });
} else {
  app.get('/', (_req, res) => {
    res.json({
      name: 'Eblan-Messenger',
      version: '1.0.0',
      status: 'running',
      endpoints: {
        health: 'GET /api/health',
        register: 'POST /api/auth/register',
        login: 'POST /api/auth/login',
        me: 'GET /api/auth/me',
        search: 'GET /api/users/search?q=',
        messages: 'GET /api/messages/:userId',
        upload: 'POST /api/files/upload',
      },
    });
  });
}

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

server.listen(config.port, '0.0.0.0', () => {
  console.log(`Eblan-Messenger server running on http://0.0.0.0:${config.port}`);
});
