import { Router, Request, Response } from 'express';
import db from '../db';
import { authMiddleware } from '../middleware/auth';

const router = Router();

router.get('/:userId', authMiddleware, (req: Request, res: Response) => {
  const myId = req.user!.userId;
  const otherId = parseInt(String(req.params.userId), 10);

  const messages = db.prepare(
    `SELECT m.*, u.username as sender_username
     FROM messages m
     JOIN users u ON m.sender_id = u.id
     WHERE (m.sender_id = ? AND m.receiver_id = ?)
        OR (m.sender_id = ? AND m.receiver_id = ?)
     ORDER BY m.created_at ASC
     LIMIT 200`
  ).all(myId, otherId, otherId, myId);

  res.json({ messages });
});

router.get('/chats/list', authMiddleware, (req: Request, res: Response) => {
  const myId = req.user!.userId;

  const chats = db.prepare(
    `SELECT
       CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END as user_id,
       u.username,
       u.avatar_path,
       u.bio,
       MAX(m.created_at) as last_message_at,
       (SELECT text FROM messages m2
        WHERE (m2.sender_id = ? AND m2.receiver_id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END)
           OR (m2.receiver_id = ? AND m2.sender_id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END)
        ORDER BY m2.created_at DESC LIMIT 1) as last_message_text
     FROM messages m
     JOIN users u ON u.id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END
     WHERE m.sender_id = ? OR m.receiver_id = ?
     GROUP BY user_id
     ORDER BY last_message_at DESC`
  ).all(myId, myId, myId, myId, myId, myId, myId, myId);

  res.json({ chats });
});

export default router;
