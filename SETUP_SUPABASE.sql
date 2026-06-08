-- ============================================================
--  SOIRÉE D'ÉTÉ — CSE IQVIA
--  Script de création du projet Supabase (xhijahegkohowfmajjvq)
--  À exécuter dans : Supabase Dashboard → SQL Editor → New query
--  Une seule exécution suffit (idempotent autant que possible).
-- ============================================================

-- ─────────────────────────────────────────────
-- 1) TABLE events
-- ─────────────────────────────────────────────
create table if not exists public.events (
  id                 text primary key,
  name               text,
  is_active          boolean      not null default true,
  uploads_enabled    boolean      not null default true,
  video_enabled      boolean      not null default false,
  max_photos         integer      not null default 500,
  couple_name        text,
  wedding_date       text,
  venue              text,
  primary_color      text         default '#FF7A1A',
  admin_secret_hash  text,
  expires_at         timestamptz,
  allowed_categories text[]       default '{}',
  created_at         timestamptz  not null default now()
);

-- ─────────────────────────────────────────────
-- 2) TABLE photos
-- ─────────────────────────────────────────────
create table if not exists public.photos (
  id             uuid         primary key default gen_random_uuid(),
  event_id       text         not null references public.events(id) on delete cascade,
  uploader_name  text,
  storage_path   text         not null,
  public_url     text,
  category       text         not null default 'ceremonie'
                              check (category in ('ceremonie','cocktail','diner','danse')),
  media_type     text         not null default 'image'
                              check (media_type in ('image','video')),
  likes          integer      not null default 0,
  duration_sec   integer,
  uploader_token uuid,
  uploaded_at    timestamptz  not null default now()
);

create index if not exists photos_event_idx        on public.photos (event_id);
create index if not exists photos_event_cat_idx    on public.photos (event_id, category);
create index if not exists photos_uploaded_at_idx  on public.photos (uploaded_at);

-- ─────────────────────────────────────────────
-- 3) ACTIVATION DE LA RLS
-- ─────────────────────────────────────────────
alter table public.events enable row level security;
alter table public.photos enable row level security;

-- ─────────────────────────────────────────────
-- 4) POLICIES — table events
--    (le dashboard écrit avec la clé anon → on autorise anon)
-- ─────────────────────────────────────────────
drop policy if exists events_select_public on public.events;
create policy events_select_public on public.events
  for select to anon, authenticated
  using (is_active = true);

drop policy if exists events_update_public on public.events;
create policy events_update_public on public.events
  for update to anon, authenticated
  using (true) with check (true);

-- ─────────────────────────────────────────────
-- 5) POLICIES — table photos
-- ─────────────────────────────────────────────
-- Lecture : photos d'un événement actif uniquement
drop policy if exists photos_select_public on public.photos;
create policy photos_select_public on public.photos
  for select to anon, authenticated
  using (exists (select 1 from public.events e
                 where e.id = photos.event_id and e.is_active));

-- Ajout : événement actif + uploads autorisés + nom < 50 car.
drop policy if exists photos_insert_public on public.photos;
create policy photos_insert_public on public.photos
  for insert to anon, authenticated
  with check (
    exists (select 1 from public.events e
            where e.id = event_id and e.is_active and e.uploads_enabled)
    and char_length(coalesce(uploader_name,'')) <= 50
  );

-- Suppression : autorisée tant que l'événement est actif
-- (la fenêtre de 2 min est gérée côté client ; suppression admin via dashboard)
drop policy if exists photos_delete_public on public.photos;
create policy photos_delete_public on public.photos
  for delete to anon, authenticated
  using (exists (select 1 from public.events e
                 where e.id = photos.event_id and e.is_active));

-- NB : pas de policy UPDATE sur photos.
-- Les "likes" passent par la fonction SECURITY DEFINER ci-dessous,
-- ce qui empêche toute modification arbitraire des autres colonnes.

-- ─────────────────────────────────────────────
-- 6) FONCTION RPC — toggle_photo_like
--    Appelée par l'app : rpc/toggle_photo_like(p_id, p_event, p_delta)
-- ─────────────────────────────────────────────
create or replace function public.toggle_photo_like(
  p_id    uuid,
  p_event text,
  p_delta integer
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_likes integer;
begin
  if p_delta not in (-1, 1) then
    raise exception 'delta invalide';
  end if;

  update public.photos
     set likes = greatest(0, least(9999, likes + p_delta))
   where id = p_id and event_id = p_event
  returning likes into v_likes;

  return coalesce(v_likes, 0);
end;
$$;

grant execute on function public.toggle_photo_like(uuid, text, integer) to anon, authenticated;

-- ─────────────────────────────────────────────
-- 7) STORAGE — bucket "photos" (public)
-- ─────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'photos', 'photos', true, 20971520,
  array['image/jpeg','image/jpg','image/png','image/webp','image/heic','image/heif',
        'image/gif','video/mp4','video/webm','video/quicktime','video/x-m4v']
)
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Policies storage.objects pour le bucket "photos"
drop policy if exists soiree_storage_select on storage.objects;
create policy soiree_storage_select on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'photos');

drop policy if exists soiree_storage_insert on storage.objects;
create policy soiree_storage_insert on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'photos');

drop policy if exists soiree_storage_delete on storage.objects;
create policy soiree_storage_delete on storage.objects
  for delete to anon, authenticated
  using (bucket_id = 'photos');

-- ─────────────────────────────────────────────
-- 7b) REALTIME — pousser les nouvelles photos/vidéos aux invités EN DIRECT
--     SANS ÇA, il faut rafraîchir la page pour voir les photos des autres.
--     (idempotent : peut être ré-exécuté sans erreur)
-- ─────────────────────────────────────────────
alter table public.photos replica identity full;
do $$
begin
  alter publication supabase_realtime add table public.photos;
exception when duplicate_object then null;  -- déjà publiée : on ignore
end $$;

-- ─────────────────────────────────────────────
-- 8) L'ÉVÉNEMENT DE LA SOIRÉE
-- ─────────────────────────────────────────────
insert into public.events
  (id, name, is_active, uploads_enabled, video_enabled, max_photos,
   couple_name, wedding_date, venue, primary_color, expires_at)
values
  ('soiree-ete-2026',
   'Soirée d''été — CSE IQVIA',
   true, true, false, 500,
   'Soirée d''été', 'Jeudi 11 Juin 2026', 'CSE IQVIA', '#FF7A1A',
   '2026-06-30 23:59:00+00')
on conflict (id) do update
  set name          = excluded.name,
      couple_name   = excluded.couple_name,
      wedding_date  = excluded.wedding_date,
      venue         = excluded.venue,
      primary_color = excluded.primary_color,
      expires_at    = excluded.expires_at;

-- ─────────────────────────────────────────────
-- 9) (OPTIONNEL) Désactivation automatique à expiration
--    Nécessite l'extension pg_cron (Database → Extensions → activer "pg_cron").
--    Décommentez ce bloc une fois pg_cron activé.
-- ─────────────────────────────────────────────
-- create or replace function public.deactivate_expired_events()
-- returns void language sql security definer set search_path = public as $$
--   update public.events set is_active = false
--    where expires_at is not null and expires_at < now() and is_active = true;
-- $$;
--
-- select cron.schedule('desactiver-events-expires', '0 2 * * *',
--   $$ select public.deactivate_expired_events(); $$);

-- ============================================================
--  FIN — Vérification rapide :
--    select * from public.events;
--    select count(*) from public.photos;
-- ============================================================
