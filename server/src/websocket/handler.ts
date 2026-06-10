import { Server as SocketIOServer, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { JwtPayload } from '../types';
import db from '../db';

interface AuthenticatedSocket extends Socket {
  userId?: number;
  username?: string;
}

export function setupWebSocket(io: SocketIOServer) {
  io.use((socket: AuthenticatedSocket, next) => {
    const token = socket.handshake.auth.token;
    if (!token) {
      return next(new Error('Authentication required'));
    }

    try {
      const decoded = jwt.verify(token, config.jwtSecret) as JwtPayload;
      socket.userId = decoded.userId;
      socket.username = decoded.username;
      next();
    } catch {
      next(new Error('Invalid token'));
    }
  });

  io.on('connection', (socket: AuthenticatedSocket) => {
    const userId = socket.userId!;
    const username = socket.username!;

    socket.join(`user:${userId}`);
    socket.broadcast.emit('user:online', { userId, username });

    socket.on('message:send', (data) => {
      const { receiverId, text, file_path, file_type, file_name, file_size } = data;

      const result = db.prepare(
        `INSERT INTO messages (sender_id, receiver_id, text, file_path, file_type, file_name, file_size)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      ).run(userId, receiverId, text || '', file_path || null, file_type || null, file_name || null, file_size || null);

      const message = {
        id: result.lastInsertRowid,
        sender_id: userId,
        receiver_id: receiverId,
        sender_username: username,
        text: text || '',
        file_path: file_path || null,
        file_type: file_type || null,
        file_name: file_name || null,
        file_size: file_size || null,
        created_at: new Date().toISOString(),
      };

      io.to(`user:${receiverId}`).emit('message:received', message);
      socket.emit('message:received', message);
    });

    socket.on('user:typing', (data) => {
      const { receiverId } = data;
      io.to(`user:${receiverId}`).emit('user:typing', { userId, username });
    });

    socket.on('user:stop_typing', (data) => {
      const { receiverId } = data;
      io.to(`user:${receiverId}`).emit('user:stop_typing', { userId });
    });

    socket.on('user:recording_audio', (data) => {
      const { receiverId } = data;
      io.to(`user:${receiverId}`).emit('user:recording_audio', { userId, username });
    });

    socket.on('user:stop_recording_audio', (data) => {
      const { receiverId } = data;
      io.to(`user:${receiverId}`).emit('user:stop_recording_audio', { userId });
    });

    socket.on('disconnect', () => {
      socket.broadcast.emit('user:offline', { userId, username });
    });
  });
}
