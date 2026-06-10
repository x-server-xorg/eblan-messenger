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
  const userSockets = new Map<number, AuthenticatedSocket>();

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

    userSockets.set(userId, socket);
    socket.join(`user:${userId}`);
    socket.broadcast.emit('user:online', { userId, username });

    socket.on('message:send', (data) => {
      const { receiverId, chatId, text, file_path, file_type, file_name, file_size } = data;

      const isBlocked = db.prepare(
        'SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?'
      ).get(receiverId, userId);
      if (isBlocked) {
        socket.emit('message:error', { error: 'You are blocked by this user' });
        return;
      }

      if (chatId) {
        const chat = db.prepare('SELECT admins_only FROM chats WHERE id = ?').get(chatId) as any;
        if (chat?.admins_only) {
          const role = db.prepare('SELECT role FROM chat_members WHERE chat_id = ? AND user_id = ?').get(chatId, userId) as any;
          if (!role || (role.role !== 'admin' && role.role !== 'creator')) {
            socket.emit('message:error', { error: 'Only admins can send messages in this chat' });
            return;
          }
        }
      }

      let mentions: number[] = [];
      if (text && chatId) {
        const mentionRegex = /@(\w+)/g;
        let match;
        while ((match = mentionRegex.exec(text)) !== null) {
          const mentionedUser = db.prepare('SELECT id FROM users WHERE username = ?').get(`@${match[1]}`) as any;
          if (mentionedUser) {
            const isInChat = db.prepare(
              'SELECT * FROM chat_members WHERE chat_id = ? AND user_id = ?'
            ).get(chatId, mentionedUser.id);
            if (isInChat) mentions.push(mentionedUser.id);
          }
        }
      }

      const result = db.prepare(
        `INSERT INTO messages (sender_id, receiver_id, chat_id, text, file_path, file_type, file_name, file_size, mentions)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(userId, receiverId, chatId || null, text || '', file_path || null, file_type || null, file_name || null, file_size || null, mentions.length > 0 ? JSON.stringify(mentions) : null);

      const message = {
        id: result.lastInsertRowid,
        sender_id: userId,
        receiver_id: receiverId,
        chat_id: chatId || null,
        sender_username: username,
        text: text || '',
        file_path: file_path || null,
        file_type: file_type || null,
        file_name: file_name || null,
        file_size: file_size || null,
        mentions: mentions.length > 0 ? mentions : null,
        created_at: new Date().toISOString(),
      };

      if (chatId) {
        io.to(`chat:${chatId}`).emit('message:received', message);
      }
      io.to(`user:${receiverId}`).emit('message:received', message);
      socket.emit('message:received', message);
    });

    socket.on('message:delete', (data) => {
      const { messageId, forAll } = data;
      const message = db.prepare('SELECT * FROM messages WHERE id = ?').get(messageId) as any;
      if (!message || message.sender_id !== userId) return;

      if (forAll) {
        if (message.file_path) {
          const path = require('path');
          const fs = require('fs');
          const { config } = require('../config');
          const filePath = path.join(config.uploadDir, message.file_path);
          if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
        }
        db.prepare('DELETE FROM messages WHERE id = ?').run(messageId);
        io.emit('message:deleted', { messageId, chatId: message.chat_id });
      } else {
        db.prepare('UPDATE messages SET is_deleted = 1, text = \'\', file_path = NULL, file_type = NULL, file_name = NULL, file_size = NULL WHERE id = ?').run(messageId);
        socket.emit('message:deleted', { messageId });
      }
    });

    socket.on('user:typing', (data) => {
      const { receiverId, chatId } = data;
      if (chatId) io.to(`chat:${chatId}`).emit('user:typing', { userId, username });
      io.to(`user:${receiverId}`).emit('user:typing', { userId, username });
    });

    socket.on('user:stop_typing', (data) => {
      const { receiverId, chatId } = data;
      if (chatId) io.to(`chat:${chatId}`).emit('user:stop_typing', { userId });
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

    socket.on('chat:join', (data) => {
      const { chatId } = data;
      socket.join(`chat:${chatId}`);
    });

    socket.on('chat:leave', (data) => {
      const { chatId } = data;
      socket.leave(`chat:${chatId}`);
    });

    socket.on('disconnect', () => {
      userSockets.delete(userId);
      socket.broadcast.emit('user:offline', { userId, username });
    });
  });
}
