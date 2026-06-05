-- Allow authors to delete their own posts.
-- Without this policy the rollback in create_post_screen (deletePost on upload
-- failure) was silently blocked by RLS, leaving orphaned posts in the database.
create policy "Users can delete their own posts"
on public.posts
for delete
to authenticated
using (auth.uid() = user_id);
