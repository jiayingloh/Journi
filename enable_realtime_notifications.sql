-- Run this in your Supabase SQL Editor to enable Realtime for notifications!
-- Without this, the Flutter app's ".stream()" listener cannot receive live push updates.

-- Add the 'notifications' table to the 'supabase_realtime' publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;

-- (Optional) If you get an error that it's already added, you can safely ignore it.
