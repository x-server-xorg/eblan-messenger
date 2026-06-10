import { Router, Request, Response } from 'express';
import multer from 'multer';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import { config } from '../config';
import { authMiddleware } from '../middleware/auth';
import fs from 'fs';

const router = Router();

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    let subdir = 'files';
    if (file.mimetype.startsWith('image/')) subdir = 'photos';
    else if (file.mimetype.startsWith('video/')) subdir = 'videos';
    else if (file.mimetype.startsWith('audio/')) subdir = 'audio';

    const dir = path.join(config.uploadDir, subdir);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `${uuidv4()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 100 * 1024 * 1024 },
});

router.post('/upload', authMiddleware, upload.single('file'), (req: Request, res: Response) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded' });
  }

  const subdir = req.file.path.includes('photos') ? 'photos'
    : req.file.path.includes('videos') ? 'videos'
    : req.file.path.includes('audio') ? 'audio'
    : 'files';

  res.json({
    file_path: `${subdir}/${req.file.filename}`,
    file_type: req.file.mimetype,
    file_name: req.file.originalname,
    file_size: req.file.size,
  });
});

router.get('/:type/:filename', (req: Request, res: Response) => {
  const filePath = path.join(config.uploadDir, String(req.params.type), String(req.params.filename));

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'File not found' });
  }

  res.sendFile(filePath);
});

export default router;
