export interface UserRow {
  id: number;
  username: string;
  password_hash: string;
  bio: string;
  avatar_path: string | null;
  created_at: string;
}

export interface MessageRow {
  id: number;
  sender_id: number;
  receiver_id: number;
  text: string;
  file_path: string | null;
  file_type: string | null;
  file_name: string | null;
  file_size: number | null;
  created_at: string;
}

export interface JwtPayload {
  userId: number;
  username: string;
}
