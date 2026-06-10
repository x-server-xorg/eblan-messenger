import dotenv from 'dotenv';
import path from 'path';

dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  jwtSecret: process.env.JWT_SECRET || 'default-secret',
  uploadDir: path.resolve(process.env.UPLOAD_DIR || './uploads'),
  dbPath: path.resolve(process.env.DB_PATH || './database.sqlite'),
};
