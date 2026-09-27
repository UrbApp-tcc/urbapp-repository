-- A 20260428204000 revogou DELETE em posts e a 20260605000000 criou a policy
-- de exclusão sem devolver o privilégio. Sem isto, a policy nunca funciona.
grant delete on table public.posts to authenticated;