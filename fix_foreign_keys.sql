-- Run this script in your Supabase SQL Editor to enable Cascade Deletion!
-- This will automatically delete connected notifications, user_trips, media, and favorites when a Trip is deleted.

-- 1. Fix Notifications
ALTER TABLE public.notifications DROP CONSTRAINT notifications_trip_id_fkey;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_trip_id_fkey 
  FOREIGN KEY (trip_id) REFERENCES public.trips(id) ON DELETE CASCADE;

-- 2. Fix User Trips
ALTER TABLE public.user_trips DROP CONSTRAINT user_trips_trip_id_fkey;
ALTER TABLE public.user_trips ADD CONSTRAINT user_trips_trip_id_fkey 
  FOREIGN KEY (trip_id) REFERENCES public.trips(id) ON DELETE CASCADE;

-- 3. Fix Media
ALTER TABLE public.media DROP CONSTRAINT media_user_trip_id_fkey;
ALTER TABLE public.media ADD CONSTRAINT media_user_trip_id_fkey 
  FOREIGN KEY (user_trip_id) REFERENCES public.user_trips(id) ON DELETE CASCADE;

-- 4. Fix Favorites
ALTER TABLE public.favorites DROP CONSTRAINT favorites_media_id_fkey;
ALTER TABLE public.favorites ADD CONSTRAINT favorites_media_id_fkey 
  FOREIGN KEY (media_id) REFERENCES public.media(id) ON DELETE CASCADE;
