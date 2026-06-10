import { Router, Request, Response } from 'express';
import db from '../db';
import { authMiddleware } from '../middleware/auth';
import fs from 'fs';
import path from 'path';
import { config } from '../config';

const router = Router();

router.get('/', authMiddleware, (req: Request, res: Response) => {
  const myId = req.user!.userId;

  const dialogs = db.prepare(`
    SELECT
      'dialog' as type,
      CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END as peer_id,
      u.id as user_id, u.username, u.avatar_path, u.bio,
      MAX(m.created_at) as last_message_at,
      (SELECT text FROM messages m2 WHERE (m2.sender_id = ? AND m2.receiver_id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END) OR (m2.receiver_id = ? AND m2.sender_id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END) AND m2.is_deleted = 0 ORDER BY m2.created_at DESC LIMIT 1) as last_message_text
    FROM messages m
    JOIN users u ON u.id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END
    WHERE (m.sender_id = ? OR m.receiver_id = ?) AND m.is_deleted = 0
    GROUP BY peer_id
  `).all(myId, myId, myId, myId, myId, myId, myId, myId);

  const groups = db.prepare(`
    SELECT c.id, c.name, c.username, c.type, c.avatar_path, c.created_at,
      (SELECT text FROM messages m WHERE m.chat_id = c.id AND m.is_deleted = 0 ORDER BY m.created_at DESC LIMIT 1) as last_message_text,
      (SELECT MAX(m.created_at) FROM messages m WHERE m.chat_id = c.id AND m.is_deleted = 0) as last_message_at
    FROM chats c
    JOIN chat_members cm ON cm.chat_id = c.id
    WHERE cm.user_id = ? AND c.type = 'group'
  `).all(myId);

  res.json({ chats: [...dialogs, ...groups] });
});

router.get('/search', authMiddleware, (req: Request, res: Response) => {
  const q = req.query.q as string;
  const myId = req.user!.userId;
  if (!q) {
    return res.status(400).json({ error: 'Query parameter q is required' });
  }

  const users = db.prepare(
    `SELECT id, username, bio, avatar_path, 'user' as type FROM users
     WHERE username LIKE ? AND id != ? LIMIT 20`
  ).all(`%${q}%`, myId);

  const groups = db.prepare(`
    SELECT c.id, c.name, c.username, c.avatar_path, 'group' as type
    FROM chats c
    JOIN chat_members cm ON cm.chat_id = c.id
    WHERE cm.user_id = ? AND (c.name LIKE ? OR c.username LIKE ?) LIMIT 20
  `).all(myId, `%${q}%`, `%${q}%`);

  res.json({ results: [...users, ...groups] });
});

router.post('/', authMiddleware, (req: Request, res: Response) => {
  const { name, username, members } = req.body;
  const myId = req.user!.userId;

  if (!name || !username) {
    return res.status(400).json({ error: 'Name and username required' });
  }

  if (!username.startsWith('@')) {
    return res.status(400).json({ error: 'Username must start with @' });
  }

  const existing = db.prepare('SELECT id FROM chats WHERE username = ?').get(username);
  if (existing) {
    return res.status(409).json({ error: 'Chat username already taken' });
  }

  const result = db.prepare(
    'INSERT INTO chats (name, username, type, creator_id) VALUES (?, ?, \'group\', ?)'
  ).run(name, username, myId);

  const chatId = result.lastInsertRowid;

  db.prepare('INSERT INTO chat_members (chat_id, user_id) VALUES (?, ?)').run(chatId, myId);

  if (Array.isArray(members)) {
    for (const userId of members) {
      if (userId !== myId) {
        const privacy = db.prepare('SELECT group_invite_privacy FROM user_settings WHERE user_id = ?').get(userId) as any;
        if (privacy) {
          if (privacy.group_invite_privacy === 'nobody') continue;
          if (privacy.group_invite_privacy === 'contacts') {
            const haveDialog = db.prepare(
              'SELECT id FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) LIMIT 1'
            ).get(myId, userId, userId, myId);
            if (!haveDialog) continue;
          }
        }
        const isBlocked = db.prepare(
          'SELECT id FROM blocks WHERE blocker_id = ? AND blocked_id = ?'
        ).get(userId, myId);
        if (isBlocked) continue;
        db.prepare('INSERT OR IGNORE INTO chat_members (chat_id, user_id) VALUES (?, ?)').run(chatId, userId);
      }
    }
  }

  const membersList = db.prepare(`
    SELECT u.id, u.username, u.avatar_path FROM chat_members cm
    JOIN users u ON u.id = cm.user_id WHERE cm.chat_id = ?
  `).all(chatId);

  const chat = db.prepare('SELECT * FROM chats WHERE id = ?').get(chatId) as any;

  res.status(201).json({ chat: { ...chat, members: membersList } });
});

router.get('/:id', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const myId = req.user!.userId;

  const chat = db.prepare(`
    SELECT c.* FROM chats c
    JOIN chat_members cm ON cm.chat_id = c.id
    WHERE c.id = ? AND cm.user_id = ?
  `).get(chatId, myId) as any;

  if (!chat) {
    return res.status(404).json({ error: 'Chat not found' });
  }

  const members = db.prepare(`
    SELECT u.id, u.username, u.avatar_path FROM chat_members cm
    JOIN users u ON u.id = cm.user_id WHERE cm.chat_id = ?
  `).all(chatId);

  res.json({ chat: { ...chat, members } });
});

router.delete('/:id', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const myId = req.user!.userId;

  const chat = db.prepare('SELECT * FROM chats WHERE id = ?').get(chatId) as any;
  if (!chat) {
    return res.status(404).json({ error: 'Chat not found' });
  }

  if (chat.type === 'group') {
    const member = db.prepare(
      'SELECT * FROM chat_members WHERE chat_id = ? AND user_id = ?'
    ).get(chatId, myId);
    if (!member) {
      return res.status(403).json({ error: 'Not a member of this chat' });
    }
  }

  const messages = db.prepare(
    'SELECT file_path, file_type FROM messages WHERE chat_id = ? AND file_path IS NOT NULL'
  ).all(chatId) as any[];

  for (const msg of messages) {
    if (msg.file_path) {
      const filePath = path.join(config.uploadDir, msg.file_path);
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
    }
  }

  db.prepare('DELETE FROM messages WHERE chat_id = ?').run(chatId);
  db.prepare('DELETE FROM chat_members WHERE chat_id = ?').run(chatId);
  db.prepare('DELETE FROM chats WHERE id = ?').run(chatId);

  res.json({ message: 'Chat deleted' });
});

router.post('/:id/invite', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const { userId } = req.body;
  const myId = req.user!.userId;

  if (!userId) {
    return res.status(400).json({ error: 'userId required' });
  }

  const chat = db.prepare('SELECT * FROM chats WHERE id = ? AND type = \'group\'').get(chatId) as any;
  if (!chat) {
    return res.status(404).json({ error: 'Group chat not found' });
  }

  const isMember = db.prepare(
    'SELECT * FROM chat_members WHERE chat_id = ? AND user_id = ?'
  ).get(chatId, myId);
  if (!isMember) {
    return res.status(403).json({ error: 'Not a member of this chat' });
  }

  const isBlocked = db.prepare(
    'SELECT id FROM blocks WHERE blocker_id = ? AND blocked_id = ?'
  ).get(userId, myId);
  if (isBlocked) {
    return res.status(403).json({ error: 'This user blocked you' });
  }

  const privacy = db.prepare('SELECT group_invite_privacy FROM user_settings WHERE user_id = ?').get(userId) as any;
  if (privacy) {
    if (privacy.group_invite_privacy === 'nobody') {
      return res.status(403).json({ error: 'User does not accept group invites' });
    }
    if (privacy.group_invite_privacy === 'contacts') {
      const haveDialog = db.prepare(
        'SELECT id FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) LIMIT 1'
      ).get(myId, userId, userId, myId);
      if (!haveDialog) {
        return res.status(403).json({ error: 'User only accepts invites from contacts' });
      }
    }
  }

  const alreadyMember = db.prepare(
    'SELECT * FROM chat_members WHERE chat_id = ? AND user_id = ?'
  ).get(chatId, userId);
  if (alreadyMember) {
    return res.status(409).json({ error: 'User already in chat' });
  }

  db.prepare('INSERT INTO chat_members (chat_id, user_id) VALUES (?, ?)').run(chatId, userId);

  res.json({ message: 'User invited' });
});

router.get('/:id/messages', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const myId = req.user!.userId;

  const isMember = db.prepare(
    'SELECT * FROM chat_members WHERE chat_id = ? AND user_id = ?'
  ).get(chatId, myId);
  if (!isMember && !db.prepare('SELECT id FROM chats WHERE id = ? AND type = \'dialog\'').get(chatId)) {
    return res.status(403).json({ error: 'Not a member of this chat' });
  }

  const messages = db.prepare(`
    SELECT m.*, u.username as sender_username
    FROM messages m
    JOIN users u ON m.sender_id = u.id
    WHERE m.chat_id = ? AND m.is_deleted = 0
    ORDER BY m.created_at ASC LIMIT 200
  `).all(chatId);

  res.json({ messages });
});

export default router;
