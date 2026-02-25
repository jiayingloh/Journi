-- Run this script in your Supabase SQL Editor to fix the silent RLS deletion failures!
-- It adds a specific Row Level Security policy that allows the creator of a Trip 
-- to safely delete other members' rows from the user_trips junction table.

-- 1. Create a clear policy for user_trips Deletion
-- A user can be deleted from a trip IF:
-- (A) They are deleting themself (user_id = auth.uid()) OR
-- (B) The current user is the creator of the trip being accessed!

CREATE POLICY "Allow members to leave AND creators to remove members"
ON public.user_trips
FOR DELETE
USING (
  user_id = auth.uid() 
  OR 
  EXISTS (
    SELECT 1 FROM public.trips 
    WHERE trips.id = user_trips.trip_id AND trips.created_by = auth.uid()
  )
);

-- Note: If you already had an existing DELETE policy, you may need to 
-- first DROP your old policy, for example:
-- DROP POLICY "Delete own user trips" ON public.user_trips;
