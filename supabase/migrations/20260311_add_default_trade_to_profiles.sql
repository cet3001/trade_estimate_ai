-- Add default_trade column to profiles table.
-- This field stores the user's preferred trade for pre-filling the trade
-- selector in the New Estimate flow, and is read/written by the Settings screen.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS default_trade TEXT;
