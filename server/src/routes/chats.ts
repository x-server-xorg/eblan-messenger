import { Router, Request, Response } from 'express';
import db from '../db';
import { authMiddleware } from '../middleware/auth';
import fs from 'fs';
import path from 'path';
import { config } from '../config';

const router = Router();

function memberRole(chatId: number, userId: number): string | null {
  const row = db.prepare('SELECT role FROM chat_members WHERE chat_id = ? AND user_id = ?').get(chatId, userId) as any;
  return row?.role || null;
}

function canAdmin(chatId: number, userId: number): boolean {
  const role = memberRole(chatId, userId);
  return role === 'admin' || role === 'creator';
}

router.get('/', authMiddleware, (req: Request, res: Response) => {
  const myId = req.user!.userId;

  const dialogs = db.prepare(`
    SELECT 'dialog' as type,
      CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END as peer_id,
      u.id as user_id, u.username, u.avatar_path, u.bio,
      MAX(m.created_at) as last_message_at,
      (SELECT text FROM messages m2 WHERE ((m2.sender_id = ? AND m2.receiver_id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END) OR (m2.receiver_id = ? AND m2.sender_id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END)) AND m2.is_deleted = 0 ORDER BY m2.created_at DESC LIMIT 1) as last_message_text
    FROM messages m
    JOIN users u ON u.id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END
    WHERE (m.sender_id = ? OR m.receiver_id = ?) AND m.is_deleted = 0
    GROUP BY peer_id
  `).all(myId, myId, myId, myId, myId, myId, myId, myId);

  const groups = db.prepare(`
    SELECT c.id, c.name, c.username, c.type, c.avatar_path, c.description, c.created_at,
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
  if (!q) return res.status(400).json({ error: 'Query parameter q is required' });

  const users = db.prepare(
    `SELECT id, username, bio, avatar_path, 'user' as type FROM users WHERE username LIKE ? AND id != ? LIMIT 20`
  ).all(`%${q}%`, myId);

  const groups = db.prepare(`
    SELECT c.id, c.name, c.username, c.avatar_path, 'group' as type
    FROM chats c JOIN chat_members cm ON cm.chat_id = c.id
    WHERE cm.user_id = ? AND (c.name LIKE ? OR c.username LIKE ?) LIMIT 20
  `).all(myId, `%${q}%`, `%${q}%`);

  res.json({ results: [...users, ...groups] });
});

router.post('/', authMiddleware, (req: Request, res: Response) => {
  const { name, username, members } = req.body;
  const myId = req.user!.userId;

  if (!name || !username) return res.status(400).json({ error: 'Name and username required' });
  if (!username.startsWith('@')) return res.status(400).json({ error: 'Username must start with @' });

  const existing = db.prepare('SELECT id FROM chats WHERE username = ?').get(username);
  if (existing) return res.status(409).json({ error: 'Chat username already taken' });

  const result = db.prepare(
    "INSERT INTO chats (name, username, type, creator_id) VALUES (?, ?, 'group', ?)"
  ).run(name, username, myId);

  const chatId = result.lastInsertRowid;
  db.prepare("INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, 'creator')").run(chatId, myId);

  if (Array.isArray(members)) {
    for (const userId of members) {
      if (userId === myId) continue;
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
      const isBlocked = db.prepare('SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?').get(userId, myId);
      if (isBlocked) continue;
      db.prepare('INSERT OR IGNORE INTO chat_members (chat_id, user_id) VALUES (?, ?)').run(chatId, userId);
    }
  }

  const membersList = db.prepare(`
    SELECT u.id, u.username, u.avatar_path, cm.role FROM chat_members cm
    JOIN users u ON u.id = cm.user_id WHERE cm.chat_id = ?
  `).all(chatId);

  const chat = db.prepare('SELECT * FROM chats WHERE id = ?').get(chatId) as any;
  res.status(201).json({ chat: { ...chat, members: membersList } });
});

router.get('/:id', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const myId = req.user!.userId;

  const chat = db.prepare(`
    SELECT c.* FROM chats c JOIN chat_members cm ON cm.chat_id = c.id
    WHERE c.id = ? AND cm.user_id = ?
  `).get(chatId, myId) as any;

  if (!chat) return res.status(404).json({ error: 'Chat not found' });

  const members = db.prepare(`
    SELECT u.id, u.username, u.avatar_path, u.bio, cm.role, cm.joined_at
    FROM chat_members cm JOIN users u ON u.id = cm.user_id
    WHERE cm.chat_id = ?
  `).all(chatId);

  const pinned = db.prepare(`
    SELECT m.id, m.text, m.sender_id, u.username as sender_username, m.created_at, m.file_path, m.file_type
    FROM pinned_messages pm JOIN messages m ON m.id = pm.message_id JOIN users u ON u.id = m.sender_id
    WHERE pm.chat_id = ? ORDER BY pm.pinned_at DESC
  `).all(chatId);

  res.json({ chat: { ...chat, members, pinned_messages: pinned } });
});

router.put('/:id', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const myId = req.user!.userId;
  const { name, description, avatar_path, admins_only, invite_permission } = req.body;

  const chat = db.prepare('SELECT * FROM chats WHERE id = ? AND type = \'group\'').get(chatId) as any;
  if (!chat) return res.status(404).json({ error: 'Group not found' });

  if (!canAdmin(chatId, myId)) return res.status(403).json({ error: 'Only admins can update group settings' });

  if (name !== undefined) db.prepare('UPDATE chats SET name = ? WHERE id = ?').run(name, chatId);
  if (description !== undefined) db.prepare('UPDATE chats SET description = ? WHERE id = ?').run(description, chatId);
  if (avatar_path !== undefined) db.prepare('UPDATE chats SET avatar_path = ? WHERE id = ?').run(avatar_path, chatId);
  if (admins_only !== undefined) db.prepare('UPDATE chats SET admins_only = ? WHERE id = ?').run(admins_only ? 1 : 0, chatId);
  if (invite_permission !== undefined) db.prepare('UPDATE chats SET invite_permission = ? WHERE id = ?').run(invite_permission, chatId);

  const updated = db.prepare('SELECT * FROM chats WHERE id = ?').get(chatId) as any;
  res.json({ chat: updated });
});

router.delete('/:id', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const myId = req.user!.userId;

  const chat = db.prepare('SELECT * FROM chats WHERE id = ?').get(chatId) as any;
  if (!chat) return res.status(404).json({ error: 'Chat not found' });

  if (chat.type === 'group') {
    const member = db.prepare('SELECT * FROM chat_members WHERE chat_id = ? AND user_id = ?').get(chatId, myId);
    if (!member) return res.status(403).json({ error: 'Not a member of this chat' });
  }

  const messages = db.prepare('SELECT file_path FROM messages WHERE chat_id = ? AND file_path IS NOT NULL').all(chatId) as any[];
  for (const msg of messages) {
    const filePath = path.join(config.uploadDir, msg.file_path);
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
  }

  db.prepare('DELETE FROM pinned_messages WHERE chat_id = ?').run(chatId);
  db.prepare('DELETE FROM messages WHERE chat_id = ?').run(chatId);
  db.prepare('DELETE FROM chat_members WHERE chat_id = ?').run(chatId);
  db.prepare('DELETE FROM chats WHERE id = ?').run(chatId);
  res.json({ message: 'Chat deleted' });
});

router.post('/:id/invite', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const { userId } = req.body;
  const myId = req.user!.userId;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  const chat = db.prepare("SELECT * FROM chats WHERE id = ? AND type = 'group'").get(chatId) as any;
  if (!chat) return res.status(404).json({ error: 'Group chat not found' });

  const myMember = db.prepare('SELECT * FROM chat_members WHERE chat_id = ? AND user_id = ?').get(chatId, myId) as any;
  if (!myMember) return res.status(403).json({ error: 'Not a member of this chat' });

  if (chat.invite_permission === 'admins' && !canAdmin(chatId, myId)) {
    return res.status(403).json({ error: 'Only admins can invite' });
  }

  const isBlocked = db.prepare('SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?').get(userId, myId);
  if (isBlocked) return res.status(403).json({ error: 'This user blocked you' });

  const privacy = db.prepare('SELECT group_invite_privacy FROM user_settings WHERE user_id = ?').get(userId) as any;
  if (privacy) {
    if (privacy.group_invite_privacy === 'nobody') return res.status(403).json({ error: 'User does not accept group invites' });
    if (privacy.group_invite_privacy === 'contacts') {
      const haveDialog = db.prepare(
        'SELECT id FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) LIMIT 1'
      ).get(myId, userId, userId, myId);
      if (!haveDialog) return res.status(403).json({ error: 'User only accepts invites from contacts' });
    }
  }

  const already = db.prepare('SELECT * FROM chat_members WHERE chat_id = ? AND user_id = ?').get(chatId, userId);
  if (already) return res.status(409).json({ error: 'User already in chat' });

  db.prepare('INSERT INTO chat_members (chat_id, user_id) VALUES (?, ?)').run(chatId, userId);
  res.json({ message: 'User invited' });
});

router.delete('/:id/members/:userId', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const targetId = parseInt(String(req.params.userId), 10);
  const myId = req.user!.userId;

  const chat = db.prepare("SELECT * FROM chats WHERE id = ? AND type = 'group'").get(chatId) as any;
  if (!chat) return res.status(404).json({ error: 'Group not found' });
  if (!canAdmin(chatId, myId)) return res.status(403).json({ error: 'Only admins can remove members' });

  db.prepare('DELETE FROM chat_members WHERE chat_id = ? AND user_id = ?').run(chatId, targetId);
  res.json({ message: 'Member removed' });
});

router.post('/:id/promote/:userId', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const targetId = parseInt(String(req.params.userId), 10);
  const myId = req.user!.userId;

  const chat = db.prepare("SELECT * FROM chats WHERE id = ? AND type = 'group'").get(chatId) as any;
  if (!chat) return res.status(404).json({ error: 'Group not found' });

  const myRole = memberRole(chatId, myId);
  if (myRole !== 'creator') return res.status(403).json({ error: 'Only creator can promote' });

  db.prepare("UPDATE chat_members SET role = 'admin' WHERE chat_id = ? AND user_id = ?").run(chatId, targetId);
  res.json({ message: 'User promoted to admin' });
});

router.post('/:id/demote/:userId', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const targetId = parseInt(String(req.params.userId), 10);
  const myId = req.user!.userId;

  const myRole = memberRole(chatId, myId);
  if (myRole !== 'creator') return res.status(403).json({ error: 'Only creator can demote' });

  db.prepare("UPDATE chat_members SET role = 'member' WHERE chat_id = ? AND user_id = ? AND role = 'admin'").run(chatId, targetId);
  res.json({ message: 'User demoted' });
});

router.post('/:id/pin/:messageId', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const messageId = parseInt(String(req.params.messageId), 10);
  const myId = req.user!.userId;

  if (!canAdmin(chatId, myId)) return res.status(403).json({ error: 'Only admins can pin' });

  db.prepare('INSERT OR IGNORE INTO pinned_messages (chat_id, message_id, pinned_by) VALUES (?, ?, ?)').run(chatId, messageId, myId);
  res.json({ message: 'Message pinned' });
});

router.delete('/:id/pin/:messageId', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const messageId = parseInt(String(req.params.messageId), 10);
  const myId = req.user!.userId;

  if (!canAdmin(chatId, myId)) return res.status(403).json({ error: 'Only admins can unpin' });

  db.prepare('DELETE FROM pinned_messages WHERE chat_id = ? AND message_id = ?').run(chatId, messageId);
  res.json({ message: 'Message unpinned' });
});

router.get('/:id/messages', authMiddleware, (req: Request, res: Response) => {
  const chatId = parseInt(String(req.params.id), 10);
  const myId = req.user!.userId;

  const isMember = db.prepare('SELECT * FROM chat_members WHERE chat_id = ? AND user_id = ?').get(chatId, myId);
  if (!isMember && !db.prepare("SELECT id FROM chats WHERE id = ? AND type = 'dialog'").get(chatId)) {
    return res.status(403).json({ error: 'Not a member' });
  }

  const messages = db.prepare(`
    SELECT m.*, u.username as sender_username
    FROM messages m JOIN users u ON m.sender_id = u.id
    WHERE m.chat_id = ? AND m.is_deleted = 0
    ORDER BY m.created_at ASC LIMIT 200
  `).all(chatId) as any[];

  for (const msg of messages) {
    if (typeof msg.mentions === 'string') {
      try { msg.mentions = JSON.parse(msg.mentions); } catch { msg.mentions = null; }
    }
  }

  res.json({ messages });
});

export default router;
