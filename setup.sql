-- 书斋：在 Supabase 的 SQL Editor 里整段贴上，按 Run，只要跑一次。

-- 1. 书架、进度、划线、设置都存在这一张表，每个人只看得到自己的
create table if not exists public.docs (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);
alter table public.docs enable row level security;

drop policy if exists "docs: read own" on public.docs;
drop policy if exists "docs: add own" on public.docs;
drop policy if exists "docs: change own" on public.docs;
drop policy if exists "docs: delete own" on public.docs;
create policy "docs: read own"   on public.docs for select to authenticated using (user_id = auth.uid());
create policy "docs: add own"    on public.docs for insert to authenticated with check (user_id = auth.uid());
create policy "docs: change own" on public.docs for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "docs: delete own" on public.docs for delete to authenticated using (user_id = auth.uid());

-- 每次改动都盖上服务器的时间（手机和 iPad 的时钟不一定准）
create or replace function public.docs_touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists docs_touch on public.docs;
create trigger docs_touch before insert or update on public.docs for each row execute function public.docs_touch();

-- 只改一条资料里的某几项（例如只改进度），手机和 iPad 同时改也不会互相盖掉
create or replace function public.merge_doc(p_id text, p_patch jsonb)
returns setof public.docs language sql security invoker as $$
  update public.docs set data = data || p_patch
  where user_id = auth.uid() and id = p_id
  returning *;
$$;
grant execute on function public.merge_doc(text, jsonb) to authenticated;

-- 一台设备改了，另一台马上收到
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;

-- 2. 书本文件放在私人的 books 文件夹，每个人只能碰自己的
insert into storage.buckets (id, name, public) values ('books', 'books', false)
on conflict (id) do nothing;

drop policy if exists "books: read own" on storage.objects;
drop policy if exists "books: add own" on storage.objects;
drop policy if exists "books: change own" on storage.objects;
drop policy if exists "books: delete own" on storage.objects;
create policy "books: read own"   on storage.objects for select to authenticated using (bucket_id = 'books' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "books: add own"    on storage.objects for insert to authenticated with check (bucket_id = 'books' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "books: change own" on storage.objects for update to authenticated using (bucket_id = 'books' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "books: delete own" on storage.objects for delete to authenticated using (bucket_id = 'books' and (storage.foldername(name))[1] = auth.uid()::text);
