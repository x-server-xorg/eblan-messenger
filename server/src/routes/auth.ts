import { Router, Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import db from '../db';
import { config } from '../config';
import { authMiddleware } from '../middleware/auth';

const router = Router();

router.post('/register', (req: Request, res: Response) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }

  if (!username.startsWith('@')) {
    return res.status(400).json({ error: 'Username must start with @' });
  }

  if (username.length < 2 || username.length > 32) {
    return res.status(400).json({ error: 'Username must be 2-32 characters' });
  }

  if (password.length < 4) {
    return res.status(400).json({ error: 'Password must be at least 4 characters' });
  }

  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (existing) {
    return res.status(409).json({ error: 'Username already taken' });
  }

  const password_hash = bcrypt.hashSync(password, 10);
  const result = db.prepare('INSERT INTO users (username, password_hash) VALUES (?, ?)').run(username, password_hash);

  const token = jwt.sign({ userId: result.lastInsertRowid, username }, config.jwtSecret, { expiresIn: '30d' });

  res.status(201).json({
    token,
    user: { id: result.lastInsertRowid, username, bio: '', avatar_path: null },
  });
});

router.post('/login', (req: Request, res: Response) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }

  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username) as any;
  if (!user) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  if (!bcrypt.compareSync(password, user.password_hash)) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const token = jwt.sign({ userId: user.id, username: user.username }, config.jwtSecret, { expiresIn: '30d' });

  res.json({
    token,
    user: { id: user.id, username: user.username, bio: user.bio, avatar_path: user.avatar_path },
  });
});

router.get('/me', authMiddleware, (req: Request, res: Response) => {
  const user = db.prepare('SELECT id, username, bio, avatar_path, created_at FROM users WHERE id = ?').get(req.user!.userId) as any;
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }
  res.json({ user });
});

export default router;
