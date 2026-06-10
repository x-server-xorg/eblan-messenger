import { Router, Request, Response } from 'express';
import db from '../db';
import { authMiddleware } from '../middleware/auth';
import fs from 'fs';
import path from 'path';
import { config } from '../config';

const router = Router();

router.get('/search', authMiddleware, (req: Request, res: Response) => {
  const q = req.query.q as string;
  if (!q) {
    return res.status(400).json({ error: 'Query parameter q is required' });
  }

  const users = db.prepare(
    `SELECT id, username, bio, avatar_path FROM users
     WHERE username LIKE ? AND id != ?
     LIMIT 20`
  ).all(`%${q}%`, req.user!.userId);

  res.json({ users });
});

router.get('/:id', authMiddleware, (req: Request, res: Response) => {
  const user = db.prepare(
    'SELECT id, username, bio, avatar_path FROM users WHERE id = ?'
  ).get(String(req.params.id)) as any;

  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  res.json({ user });
});

router.put('/me', authMiddleware, (req: Request, res: Response) => {
  const { username, bio } = req.body;
  const userId = req.user!.userId;

  if (username !== undefined) {
    if (!username.startsWith('@') || username.length < 2 || username.length > 32) {
      return res.status(400).json({ error: 'Invalid username format' });
    }

    const existing = db.prepare('SELECT id FROM users WHERE username = ? AND id != ?').get(username, userId);
    if (existing) {
      return res.status(409).json({ error: 'Username already taken' });
    }

    db.prepare('UPDATE users SET username = ? WHERE id = ?').run(username, userId);
  }

  if (bio !== undefined) {
    db.prepare('UPDATE users SET bio = ? WHERE id = ?').run(bio, userId);
  }

  const user = db.prepare('SELECT id, username, bio, avatar_path FROM users WHERE id = ?').get(userId) as any;
  res.json({ user });
});

router.delete('/me', authMiddleware, (req: Request, res: Response) => {
  const userId = req.user!.userId;

  const user = db.prepare('SELECT username FROM users WHERE id = ?').get(userId) as any;
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  const userDir = path.join(config.uploadDir, String(userId));
  if (fs.existsSync(userDir)) {
    fs.rmSync(userDir, { recursive: true, force: true });
  }

  db.prepare('DELETE FROM users WHERE id = ?').run(userId);

  res.json({ message: 'Account deleted' });
});

router.put('/me/avatar', authMiddleware, (req: Request, res: Response) => {
  const userId = req.user!.userId;

  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded' });
  }

  const avatarPath = `avatars/${req.file.filename}`;

  const oldUser = db.prepare('SELECT avatar_path FROM users WHERE id = ?').get(userId) as any;
  if (oldUser?.avatar_path) {
    const oldPath = path.join(config.uploadDir, oldUser.avatar_path);
    if (fs.existsSync(oldPath)) {
      fs.unlinkSync(oldPath);
    }
  }

  db.prepare('UPDATE users SET avatar_path = ? WHERE id = ?').run(avatarPath, userId);

  res.json({ avatar_path: avatarPath });
});

export default router;
