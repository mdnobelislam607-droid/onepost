create table connected_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  platform text not null,
  display_name text,
  refresh_token_enc text,
  created_at timestamptz default now()
);
create table posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  title text, caption text, video_path text,
  scheduled_at timestamptz default now(),
  created_at timestamptz default now()
);
create table post_targets (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references posts on delete cascade,
  platform text not null,
  status text default 'queued',
  error text,
  created_at timestamptz default now()
);
alter table connected_accounts enable row level security;
alter table posts enable row level security;
alter table post_targets enable row level security;
create policy own_accounts on connected_accounts for select using (user_id = auth.uid());
create policy del_accounts on connected_accounts for delete using (user_id = auth.uid());
create policy own_posts on posts for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_targets on post_targets for all
  using (exists (select 1 from posts p where p.id = post_id and p.user_id = auth.uid()))
  with check (exists (select 1 from posts p where p.id = post_id and p.user_id = auth.uid()));
insert into storage.buckets (id, name, public) values ('videos','videos',false);
create policy up_videos on storage.objects for insert to authenticated
  with check (bucket_id='videos' and (storage.foldername(name))[1] = auth.uid()::text);
