-- ============================================================
-- Kopi Chat — full database schema (already applied to project
-- ebdvczthxwyhyaqeqvrd). Kept here for reference / reproducibility.
-- ============================================================

create extension if not exists pgcrypto;
create sequence if not exists public.user_number_seq start with 1 increment by 1;

-- ---------- PROFILES ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  user_number bigint unique not null default nextval('public.user_number_seq'),
  username text unique not null,
  display_name text not null default 'User',
  avatar_url text,
  avatar_preset text default 'coffee-1',
  border_style text default 'none',
  theme text not null default 'mocha',
  font text not null default 'inter',
  bio text default '',
  is_premium boolean not null default false,
  premium_until timestamptz,
  is_developer boolean not null default false,
  is_banned boolean not null default false,
  last_seen timestamptz default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_profiles_user_number on public.profiles(user_number);
create index if not exists idx_profiles_username on public.profiles(lower(username));

-- Auto-create a profile on signup. The FIRST profile ever created becomes the
-- developer with ID 1. Numbering is gapless (max+1) so failed/rolled-back
-- signups never skip ID 1.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_num bigint; v_first boolean; v_username text; v_name text; v_avatar text;
begin
  select count(*) = 0 into v_first from public.profiles;
  select coalesce(max(user_number),0)+1 into v_num from public.profiles;
  v_username := 'user' || v_num::text;
  v_name := coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(coalesce(new.email,'User'), '@', 1));
  v_avatar := new.raw_user_meta_data->>'avatar_url';
  insert into public.profiles (id, user_number, username, display_name, avatar_url, is_developer, is_premium)
  values (new.id, v_num, v_username, v_name, v_avatar, v_first, v_first);
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- FRIENDSHIPS ----------
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','blocked')),
  created_at timestamptz not null default now(),
  unique (requester_id, addressee_id)
);

-- ---------- CONVERSATIONS / MEMBERS / MESSAGES ----------
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null default 'dm' check (type in ('dm','group','community','channel')),
  name text, avatar_url text, description text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('member','admin','owner')),
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  content text default '',
  type text not null default 'text' check (type in ('text','image','video','file','link')),
  media_url text, media_name text, media_size bigint,
  reply_to uuid references public.messages(id) on delete set null,
  deleted_for_all boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.message_deletions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (message_id, user_id)
);
create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  action text not null, detail jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ---------- SECURITY DEFINER HELPERS (avoid RLS recursion) ----------
create or replace function public.is_developer(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_developer from public.profiles where id = uid), false); $$;
create or replace function public.is_member(conv uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.conversation_members where conversation_id = conv and user_id = uid); $$;

-- Prevent non-developers from changing privileged columns.
create or replace function public.guard_profile_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_developer(auth.uid()) then
    new.user_number := old.user_number; new.is_developer := old.is_developer;
    new.is_premium := old.is_premium; new.premium_until := old.premium_until;
    new.is_banned := old.is_banned; new.id := old.id;
  end if;
  return new;
end; $$;
drop trigger if exists trg_guard_profile on public.profiles;
create trigger trg_guard_profile before update on public.profiles
  for each row execute function public.guard_profile_update();

-- ---------- RPCs ----------
create or replace function public.start_dm(other_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); conv uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if me = other_id then raise exception 'cannot dm self'; end if;
  select c.id into conv from public.conversations c
    where c.type = 'dm'
      and exists(select 1 from public.conversation_members m where m.conversation_id=c.id and m.user_id=me)
      and exists(select 1 from public.conversation_members m where m.conversation_id=c.id and m.user_id=other_id)
    limit 1;
  if conv is not null then return conv; end if;
  insert into public.conversations (type, created_by) values ('dm', me) returning id into conv;
  insert into public.conversation_members (conversation_id, user_id, role)
    values (conv, me, 'member'), (conv, other_id, 'member');
  return conv;
end; $$;

create or replace function public.create_group(p_name text, p_type text, p_member_ids uuid[] default '{}')
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); conv uuid; m uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if p_type not in ('group','community','channel') then raise exception 'bad type'; end if;
  insert into public.conversations (type, name, created_by) values (p_type, p_name, me) returning id into conv;
  insert into public.conversation_members (conversation_id, user_id, role) values (conv, me, 'owner');
  if p_member_ids is not null then
    foreach m in array p_member_ids loop
      if m <> me then
        insert into public.conversation_members (conversation_id, user_id, role)
          values (conv, m, 'member') on conflict do nothing;
      end if;
    end loop;
  end if;
  return conv;
end; $$;

create or replace function public.respond_friend(p_request_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if p_accept then update public.friendships set status='accepted' where id=p_request_id and addressee_id=me;
  else delete from public.friendships where id=p_request_id and addressee_id=me; end if;
end; $$;

create or replace function public.dev_set_premium(target uuid, enable boolean, duration_days int default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_developer(auth.uid()) then raise exception 'forbidden'; end if;
  update public.profiles set is_premium=enable,
    premium_until = case when enable and duration_days is not null then now()+(duration_days||' days')::interval else null end
  where id=target;
  insert into public.activity_log(user_id,action,detail) values (target,'premium_change',jsonb_build_object('enable',enable,'days',duration_days));
end; $$;

create or replace function public.dev_set_ban(target uuid, banned boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_developer(auth.uid()) then raise exception 'forbidden'; end if;
  update public.profiles set is_banned=banned where id=target;
  insert into public.activity_log(user_id,action,detail) values (target,'ban_change',jsonb_build_object('banned',banned));
end; $$;

-- ---------- RLS ----------
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_deletions enable row level security;
alter table public.activity_log enable row level security;

create policy p_profiles_select on public.profiles for select to authenticated using (true);
create policy p_profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_developer(auth.uid()))
  with check (id = auth.uid() or public.is_developer(auth.uid()));

create policy p_friend_select on public.friendships for select to authenticated
  using (requester_id=auth.uid() or addressee_id=auth.uid() or public.is_developer(auth.uid()));
create policy p_friend_insert on public.friendships for insert to authenticated with check (requester_id=auth.uid());
create policy p_friend_update on public.friendships for update to authenticated
  using (requester_id=auth.uid() or addressee_id=auth.uid() or public.is_developer(auth.uid()));
create policy p_friend_delete on public.friendships for delete to authenticated
  using (requester_id=auth.uid() or addressee_id=auth.uid() or public.is_developer(auth.uid()));

create policy p_conv_select on public.conversations for select to authenticated
  using (public.is_member(id, auth.uid()) or type in ('channel','community') or public.is_developer(auth.uid()));
create policy p_conv_insert on public.conversations for insert to authenticated with check (created_by=auth.uid());
create policy p_conv_update on public.conversations for update to authenticated
  using (created_by=auth.uid() or public.is_developer(auth.uid()));

create policy p_mem_select on public.conversation_members for select to authenticated
  using (public.is_member(conversation_id, auth.uid()) or public.is_developer(auth.uid()));
create policy p_mem_insert on public.conversation_members for insert to authenticated
  with check (user_id=auth.uid() or public.is_member(conversation_id, auth.uid()) or public.is_developer(auth.uid()));
create policy p_mem_delete on public.conversation_members for delete to authenticated
  using (user_id=auth.uid() or public.is_developer(auth.uid()));

create policy p_msg_select on public.messages for select to authenticated
  using (public.is_member(conversation_id, auth.uid()) or public.is_developer(auth.uid()));
create policy p_msg_insert on public.messages for insert to authenticated
  with check (sender_id=auth.uid() and public.is_member(conversation_id, auth.uid()));
create policy p_msg_update on public.messages for update to authenticated
  using (sender_id=auth.uid() or public.is_developer(auth.uid()));
create policy p_msg_delete on public.messages for delete to authenticated
  using (sender_id=auth.uid() or public.is_developer(auth.uid()));

create policy p_del_all on public.message_deletions for all to authenticated
  using (user_id=auth.uid()) with check (user_id=auth.uid());

create policy p_act_insert on public.activity_log for insert to authenticated
  with check (user_id=auth.uid() or public.is_developer(auth.uid()));
create policy p_act_select on public.activity_log for select to authenticated using (public.is_developer(auth.uid()));

-- ---------- STORAGE ----------
insert into storage.buckets (id,name,public,file_size_limit) values ('media','media',true,104857600)
  on conflict (id) do update set public=true, file_size_limit=104857600;
insert into storage.buckets (id,name,public,file_size_limit) values ('avatars','avatars',true,10485760)
  on conflict (id) do update set public=true;
create policy p_storage_read on storage.objects for select to public using (bucket_id in ('media','avatars'));
create policy p_storage_insert on storage.objects for insert to authenticated
  with check (bucket_id in ('media','avatars') and owner = auth.uid());
create policy p_storage_update on storage.objects for update to authenticated
  using (owner = auth.uid()) with check (bucket_id in ('media','avatars'));
create policy p_storage_delete on storage.objects for delete to authenticated
  using (owner = auth.uid() or public.is_developer(auth.uid()));

-- ---------- REALTIME ----------
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.conversation_members;
alter publication supabase_realtime add table public.friendships;
alter publication supabase_realtime add table public.profiles;
