ALTER TABLE users RENAME COLUMN first_name TO username;
ALTER TABLE users RENAME COLUMN last_name TO full_name;
ALTER TABLE users RENAME COLUMN xp TO current_xp;
ALTER TABLE users RENAME COLUMN level TO current_level;
ALTER TABLE users RENAME COLUMN points TO current_points;

ALTER TABLE users ADD COLUMN avatar_url text;
ALTER TABLE users ADD COLUMN updated_at timestamp with time zone DEFAULT now();