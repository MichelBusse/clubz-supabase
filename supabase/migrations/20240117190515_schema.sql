SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";

ALTER SCHEMA "public" OWNER TO "postgres";

CREATE SCHEMA IF NOT EXISTS "supabase_migrations";

ALTER SCHEMA "supabase_migrations" OWNER TO "postgres";

CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "public";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

CREATE OR REPLACE FUNCTION "public"."autocomplete_cities"(search_text text) RETURNS TABLE(description text, lng double precision, lat double precision)
    LANGUAGE "sql"
    AS $$
  select description,
  lng,
  lat
  from cities
  where description LIKE concat(search_text, '%')
$$;

ALTER FUNCTION "public"."autocomplete_cities"(search_text text) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."delete_user"() RETURNS void
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
   delete from auth.users where id = auth.uid();
$$;

ALTER FUNCTION "public"."delete_user"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_event"(filter_event_id uuid) RETURNS TABLE(id uuid, event_name text, end_datetime timestamp with time zone, start_datetime timestamp with time zone, image_url text, creator_id text, description text, visible boolean, place_description text, location public.geography, dress_code integer, dress_code_description text, age_policy integer, age_policy_description text, price_policy integer, price_policy_description text, price_policy_price double precision, price_policy_link text, repeat_weekly boolean, creator json, attending_count integer, interested_count integer, attending_preview json[], interested_preview json[])
    LANGUAGE "sql"
    AS $$
  select *,
  array(select row_to_json(profiles) from attending join profiles on profiles.id = profile_id where event_id = e.id limit 5) as attending_preview,
  array(select row_to_json(profiles) from interested join profiles on profiles.id = profile_id where event_id = e.id limit 5) as interested_preview
  from get_event_data(filter_event_id) as e
$$;

ALTER FUNCTION "public"."get_event"(filter_event_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_event_data"(filter_event_id uuid) RETURNS TABLE(id uuid, event_name text, end_datetime timestamp with time zone, start_datetime timestamp with time zone, image_url text, creator_id text, description text, visible boolean, place_description text, location public.geography, dress_code integer, dress_code_description text, age_policy integer, age_policy_description text, price_policy integer, price_policy_description text, price_policy_price double precision, price_policy_link text, repeat_weekly boolean, creator json, attending_count integer, interested_count integer)
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  select e.id,
  e.event_name,
  e.end_datetime,
  e.start_datetime,
  e.image_url,
  e.creator_id,
  e.description,
  e.visible,
  e.place_description,
  e.location,
  e.dress_code,
  e.dress_code_description,
  e.age_policy,
  e.age_policy_description,
  e.price_policy,
  e.price_policy_description,
  e.price_policy_price,
  e.price_policy_link,
  e.repeat_weekly,
  jsonb_build_object(
              'id', profiles.id,
              'username', profiles.username,
              'full_name', profiles.full_name,
              'avatar_url', profiles.avatar_url,
              'public_profile', profiles.public_profile) as creator,
  counts.attending,
  counts.interested
  from events as e
  join event_counts as counts on e.id = counts.id
  join profiles on e.creator_id = profiles.id
  where e.id = filter_event_id
$$;

ALTER FUNCTION "public"."get_event_data"(filter_event_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_profile_stats"(filter_profile_id uuid) RETURNS record
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
  declare
    follower_count int;
    attending_count int;
    attendees_count int;
    event_count int;
    result_set RECORD;
  BEGIN
    select count(*) into follower_count from following where following.following_id = filter_profile_id and following.accepted;
    select count(*) into attending_count from attending join events on attending.event_id = events.id where attending.profile_id = filter_profile_id and events.creator_id != filter_profile_id;
    select count(*) into event_count from events where events.creator_id = filter_profile_id;
    select count(*) into attendees_count from attending join events on attending.event_id = events.id where events.creator_id = filter_profile_id and attending.profile_id != filter_profile_id;

    select follower_count as follower, (attending_count * 20 + attendees_count * 10) as score, event_count as events into result_set;

    return result_set;
  END;
$$;

ALTER FUNCTION "public"."get_profile_stats"(filter_profile_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS trigger
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'avatar_url');
  return new;
end;
$$;

ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."query_events_feed"(filter_location text, filter_radius integer, filter_end_datetime timestamp without time zone) RETURNS TABLE(id uuid, event_name text, end_datetime timestamp with time zone, start_datetime timestamp with time zone, image_url text, creator_id text, description text, visible boolean, place_description text, location public.geography, dress_code integer, dress_code_description text, age_policy integer, age_policy_description text, price_policy integer, price_policy_description text, price_policy_price double precision, price_policy_link text, repeat_weekly boolean, creator json, attending_preview json[], interested_preview json[], attending_count integer, interested_count integer)
    LANGUAGE "sql"
    AS $$
  select e.id,
  e.event_name,
  e.end_datetime,
  e.start_datetime,
  e.image_url,
  e.creator_id,
  e.description,
  e.visible,
  e.place_description,
  e.location,
  e.dress_code,
  e.dress_code_description,
  e.age_policy,
  e.age_policy_description,
  e.price_policy,
  e.price_policy_description,
  e.price_policy_price,
  e.price_policy_link,
  e.repeat_weekly,
  row_to_json(creator_profile) as creator,
  array(select row_to_json(profiles) from attending join profiles on profiles.id = profile_id where event_id = e.id limit 5) as attending_preview,
  array(select row_to_json(profiles) from interested join profiles on profiles.id = profile_id where event_id = e.id limit 5) as interested_preview,
  counts.attending,
  counts.interested
  from events as e
  join event_counts as counts on e.id = counts.id
  join profiles as creator_profile on e.creator_id = creator_profile.id
  where st_distance(location, st_geogfromtext(filter_location), false) <= filter_radius * 1000 and
  end_datetime >= filter_end_datetime
  order by start_datetime asc
$$;

ALTER FUNCTION "public"."query_events_feed"(filter_location text, filter_radius integer, filter_end_datetime timestamp without time zone) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."query_events_profile_past"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) RETURNS TABLE(id uuid, event_name text, end_datetime timestamp with time zone, start_datetime timestamp with time zone, image_url text, creator_id text, description text, visible boolean, place_description text, location public.geography, dress_code integer, dress_code_description text, age_policy integer, age_policy_description text, price_policy integer, price_policy_description text, price_policy_price double precision, price_policy_link text, repeat_weekly boolean, creator json, attending_preview json[], interested_preview json[], attending_count integer, interested_count integer)
    LANGUAGE "sql"
    AS $$
  select e.id,
  e.event_name,
  e.end_datetime,
  e.start_datetime,
  e.image_url,
  e.creator_id,
  e.description,
  e.visible,
  e.place_description,
  e.location,
  e.dress_code,
  e.dress_code_description,
  e.age_policy,
  e.age_policy_description,
  e.price_policy,
  e.price_policy_description,
  e.price_policy_price,
  e.price_policy_link,
  e.repeat_weekly,
  row_to_json(creator_profile) as creator,
  array(select row_to_json(profiles) from attending join profiles on profiles.id = profile_id where event_id = e.id limit 5) as attending_preview,
  array(select row_to_json(profiles) from interested join profiles on profiles.id = profile_id where event_id = e.id limit 5) as interested_preview,
  counts.attending,
  counts.interested
  from events as e
  join event_counts as counts on e.id = counts.id
  join profiles as creator_profile on e.creator_id = creator_profile.id
  where (e.creator_id = filter_creator_id or exists(SELECT * from attending WHERE attending.profile_id = filter_creator_id and attending.event_id = e.id)) and
  end_datetime < filter_end_datetime
  order by start_datetime desc
$$;

ALTER FUNCTION "public"."query_events_profile_past"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."query_events_profile_upcoming"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) RETURNS TABLE(id uuid, event_name text, end_datetime timestamp with time zone, start_datetime timestamp with time zone, image_url text, creator_id text, description text, visible boolean, place_description text, location public.geography, dress_code integer, dress_code_description text, age_policy integer, age_policy_description text, price_policy integer, price_policy_description text, price_policy_price double precision, price_policy_link text, repeat_weekly boolean, creator json, attending_preview json[], interested_preview json[], attending_count integer, interested_count integer)
    LANGUAGE "sql"
    AS $$
  select e.id,
  e.event_name,
  e.end_datetime,
  e.start_datetime,
  e.image_url,
  e.creator_id,
  e.description,
  e.visible,
  e.place_description,
  e.location,
  e.dress_code,
  e.dress_code_description,
  e.age_policy,
  e.age_policy_description,
  e.price_policy,
  e.price_policy_description,
  e.price_policy_price,
  e.price_policy_link,
  e.repeat_weekly,
  row_to_json(creator_profile) as creator,
  array(select row_to_json(profiles) from attending join profiles on profiles.id = profile_id where event_id = e.id limit 5) as attending_preview,
  array(select row_to_json(profiles) from interested join profiles on profiles.id = profile_id where event_id = e.id limit 5) as interested_preview,
  counts.attending,
  counts.interested
  from events as e
  join event_counts as counts on e.id = counts.id
  join profiles as creator_profile on e.creator_id = creator_profile.id
  where (e.creator_id = filter_creator_id or exists(SELECT * from attending WHERE attending.profile_id = filter_creator_id and attending.event_id = e.id) or exists(SELECT * from interested WHERE interested.profile_id = filter_creator_id and interested.event_id = e.id)) and
  end_datetime >= filter_end_datetime
  order by start_datetime asc
$$;

ALTER FUNCTION "public"."query_events_profile_upcoming"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" uuid NOT NULL,
    "username" text,
    "full_name" text,
    "avatar_url" text,
    "public_profile" boolean DEFAULT false,
    CONSTRAINT "username_length" CHECK ((char_length(username) >= 3))
);

ALTER TABLE "public"."profiles" OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."query_profiles_attending"(filter_event_id uuid) RETURNS SETOF public.profiles
    LANGUAGE "sql"
    AS $$
  select attending_profile.*
  from attending
  join profiles as attending_profile on attending.profile_id = attending_profile.id
  where attending.event_id = filter_event_id
$$;

ALTER FUNCTION "public"."query_profiles_attending"(filter_event_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."query_profiles_follower"() RETURNS SETOF public.profiles
    LANGUAGE "sql"
    AS $$
  select follower_profile.*
  from following
  join profiles as follower_profile on following.follower_id = follower_profile.id
  join profiles as following_profile on following.following_id = following_profile.id
  where following_profile.id = auth.uid()
  order by following.accepted
$$;

ALTER FUNCTION "public"."query_profiles_follower"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."query_profiles_following"() RETURNS SETOF public.profiles
    LANGUAGE "sql"
    AS $$
  select following_profile.*
  from following
  join profiles as follower_profile on following.follower_id = follower_profile.id
  join profiles as following_profile on following.following_id = following_profile.id
  where follower_profile.id = auth.uid()
  order by following.accepted
$$;

ALTER FUNCTION "public"."query_profiles_following"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."query_profiles_interested"(filter_event_id uuid) RETURNS SETOF public.profiles
    LANGUAGE "sql"
    AS $$
  select interested_profile.*
  from interested
  join profiles as interested_profile on interested.profile_id = interested_profile.id
  where interested.event_id = filter_event_id
$$;

ALTER FUNCTION "public"."query_profiles_interested"(filter_event_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."repeat_events"() RETURNS void
    LANGUAGE "sql"
    AS $$
INSERT INTO events
       (event_name, start_datetime, end_datetime, creator_id, image_url, description, visible, place_description, location, dress_code, dress_code_description, age_policy, age_policy_description, price_policy, price_policy_description, price_policy_link, price_policy_price, repeat_weekly)
      SELECT event_name,
             start_datetime + INTERVAL '7 day',
             end_datetime + INTERVAL '7 day',
             creator_id,
             image_url,
             description,
             visible,
             place_description,
             location,
             dress_code,
             dress_code_description,
             age_policy,
             age_policy_description,
             price_policy,
             price_policy_description,
             price_policy_link,
             price_policy_price,
             repeat_weekly
      FROM events WHERE start_datetime > now() AND end_datetime <= (now() + INTERVAL '7 day') AND repeat_weekly
$$;

ALTER FUNCTION "public"."repeat_events"() OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."attending" (
    "event_id" uuid NOT NULL,
    "profile_id" uuid NOT NULL
);

ALTER TABLE "public"."attending" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."cities" (
    "description" text,
    "lat" double precision,
    "lng" double precision,
    "location" public.geography,
    "id" uuid DEFAULT extensions.uuid_generate_v4() NOT NULL
);

ALTER TABLE "public"."cities" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."events" (
    "event_name" text NOT NULL,
    "start_datetime" timestamp with time zone NOT NULL,
    "end_datetime" timestamp with time zone NOT NULL,
    "creator_id" uuid NOT NULL,
    "image_url" text,
    "description" text DEFAULT ''::text NOT NULL,
    "visible" boolean DEFAULT false NOT NULL,
    "id" uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    "place_description" text DEFAULT ''::text NOT NULL,
    "location" public.geography,
    "dress_code" smallint DEFAULT '0'::smallint NOT NULL,
    "dress_code_description" text DEFAULT ''::text NOT NULL,
    "age_policy" smallint DEFAULT '0'::smallint NOT NULL,
    "age_policy_description" text DEFAULT ''::text NOT NULL,
    "price_policy" smallint DEFAULT '0'::smallint NOT NULL,
    "price_policy_description" text DEFAULT ''::text NOT NULL,
    "price_policy_price" real DEFAULT '0'::real NOT NULL,
    "price_policy_link" text DEFAULT ''::text NOT NULL,
    "repeat_weekly" boolean DEFAULT false NOT NULL
);

ALTER TABLE "public"."events" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."interested" (
    "profile_id" uuid NOT NULL,
    "event_id" uuid NOT NULL
);

ALTER TABLE "public"."interested" OWNER TO "postgres";

CREATE OR REPLACE VIEW "public"."event_counts" AS
 SELECT e.id,
    ( SELECT count(*) AS count
           FROM public.attending
          WHERE (attending.event_id = e.id)) AS attending,
    ( SELECT count(*) AS count
           FROM public.interested
          WHERE (interested.event_id = e.id)) AS interested
   FROM public.events e;

ALTER TABLE "public"."event_counts" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."event_reports" (
    "event_id" uuid NOT NULL,
    "reporter_id" uuid NOT NULL,
    "reason" text DEFAULT ''::text NOT NULL
);

ALTER TABLE "public"."event_reports" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."following" (
    "follower_id" uuid NOT NULL,
    "following_id" uuid NOT NULL,
    "accepted" boolean DEFAULT false NOT NULL
);

ALTER TABLE "public"."following" OWNER TO "postgres";

CREATE OR REPLACE VIEW "public"."my_attending" AS
 SELECT attending.event_id,
    attending.profile_id
   FROM public.attending
  WHERE (attending.profile_id = auth.uid());

ALTER TABLE "public"."my_attending" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."profile_reports" (
    "profile_id" uuid NOT NULL,
    "reporter_id" uuid NOT NULL,
    "reason" text DEFAULT ''::text NOT NULL
);

ALTER TABLE "public"."profile_reports" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."profiles_blocked" (
    "profile_id" uuid NOT NULL,
    "blocked_id" uuid NOT NULL
);

ALTER TABLE "public"."profiles_blocked" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "supabase_migrations"."schema_migrations" (
    "version" text NOT NULL,
    "statements" text[],
    "name" text
);

ALTER TABLE "supabase_migrations"."schema_migrations" OWNER TO "postgres";

ALTER TABLE ONLY "public"."attending"
    ADD CONSTRAINT "attending_pkey" PRIMARY KEY ("event_id", "profile_id");

ALTER TABLE ONLY "public"."cities"
    ADD CONSTRAINT "cities_id_key" UNIQUE ("id");

ALTER TABLE ONLY "public"."cities"
    ADD CONSTRAINT "cities_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."event_reports"
    ADD CONSTRAINT "event_reports_pkey" PRIMARY KEY ("event_id", "reporter_id");

ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."following"
    ADD CONSTRAINT "following_pkey" PRIMARY KEY ("follower_id", "following_id");

ALTER TABLE ONLY "public"."interested"
    ADD CONSTRAINT "interested_pkey" PRIMARY KEY ("profile_id", "event_id");

ALTER TABLE ONLY "public"."profile_reports"
    ADD CONSTRAINT "profile_reports_pkey" PRIMARY KEY ("profile_id", "reporter_id");

ALTER TABLE ONLY "public"."profiles_blocked"
    ADD CONSTRAINT "profiles_blocked_pkey" PRIMARY KEY ("profile_id", "blocked_id");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");

ALTER TABLE ONLY "supabase_migrations"."schema_migrations"
    ADD CONSTRAINT "schema_migrations_pkey" PRIMARY KEY ("version");

CREATE TRIGGER notify_on_event_created AFTER INSERT ON public.events FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request('https://fziamtcyxwkbtxbfghjz.functions.supabase.co/notifyOnEventCreated', 'POST', '{"Content-type":"application/json"}', '{}', '1000');

CREATE TRIGGER notify_on_follow_request AFTER INSERT ON public.following FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request('https://fziamtcyxwkbtxbfghjz.functions.supabase.co/notifyOnFollowRequest', 'POST', '{"Content-type":"application/json"}', '{}', '1000');

ALTER TABLE ONLY "public"."attending"
    ADD CONSTRAINT "attending_event_id_fkey" FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."attending"
    ADD CONSTRAINT "attending_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."event_reports"
    ADD CONSTRAINT "event_reports_event_id_fkey" FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."event_reports"
    ADD CONSTRAINT "event_reports_reporter_id_fkey" FOREIGN KEY (reporter_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_creator_id_fkey" FOREIGN KEY (creator_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."following"
    ADD CONSTRAINT "following_follower_id_fkey" FOREIGN KEY (follower_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."following"
    ADD CONSTRAINT "following_following_id_fkey" FOREIGN KEY (following_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."interested"
    ADD CONSTRAINT "interested_event_id_fkey" FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."interested"
    ADD CONSTRAINT "interested_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_reports"
    ADD CONSTRAINT "profile_reports_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_reports"
    ADD CONSTRAINT "profile_reports_reporter_id_fkey" FOREIGN KEY (reporter_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profiles_blocked"
    ADD CONSTRAINT "profiles_blocked_blocked_id_fkey" FOREIGN KEY (blocked_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profiles_blocked"
    ADD CONSTRAINT "profiles_blocked_profile_id_fkey" FOREIGN KEY (blocked_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE POLICY "Enable delete access for involved profiles" ON "public"."interested" FOR DELETE USING ((profile_id = auth.uid()));

CREATE POLICY "Enable delete for creator" ON "public"."events" FOR DELETE USING ((auth.uid() = creator_id));

CREATE POLICY "Enable delete for involved profiles" ON "public"."following" FOR DELETE USING (((auth.uid() = follower_id) OR (auth.uid() = following_id)));

CREATE POLICY "Enable delete for involved users" ON "public"."attending" FOR DELETE USING ((auth.uid() = profile_id));

CREATE POLICY "Enable edit for creator profile" ON "public"."profiles_blocked" USING ((profile_id = auth.uid())) WITH CHECK ((profile_id = auth.uid()));

CREATE POLICY "Enable insert for creator profile" ON "public"."events" FOR INSERT WITH CHECK ((auth.uid() = creator_id));

CREATE POLICY "Enable insert for follower profile" ON "public"."following" FOR INSERT WITH CHECK (((auth.uid() = follower_id) AND ((accepted = false) OR ( SELECT profiles.public_profile
   FROM public.profiles
  WHERE (profiles.id = following.following_id)))));

CREATE POLICY "Enable insert for involved profile" ON "public"."attending" FOR INSERT WITH CHECK ((auth.uid() = profile_id));

CREATE POLICY "Enable insert for involved profiles" ON "public"."interested" FOR INSERT WITH CHECK ((profile_id = auth.uid()));

CREATE POLICY "Enable insert for reporter profile" ON "public"."event_reports" FOR INSERT WITH CHECK ((auth.uid() = reporter_id));

CREATE POLICY "Enable insert for reporter profile" ON "public"."profile_reports" FOR INSERT WITH CHECK ((auth.uid() = reporter_id));

CREATE POLICY "Enable select for all users" ON "public"."cities" FOR SELECT USING (true);

CREATE POLICY "Enable select for all users" ON "public"."spatial_ref_sys" FOR SELECT USING (true);

CREATE POLICY "Enable select for authenticated profiles" ON "public"."interested" FOR SELECT TO authenticated USING (true);

CREATE POLICY "Enable select for involved users and their followers" ON "public"."following" FOR SELECT USING (((auth.uid() = follower_id) OR (auth.uid() = following_id)));

CREATE POLICY "Enable select for profiles who follow creator | Exclude Blocked" ON "public"."events" FOR SELECT USING (((creator_id = auth.uid()) OR ((( SELECT profiles.public_profile
   FROM public.profiles
  WHERE (events.creator_id = profiles.id)) OR ((EXISTS ( SELECT following.accepted
   FROM public.following
  WHERE ((following.following_id = events.creator_id) AND following.accepted AND (following.follower_id = auth.uid())))) AND visible) OR (EXISTS ( SELECT my_attending.event_id
   FROM public.my_attending
  WHERE ((my_attending.profile_id = auth.uid()) AND (my_attending.event_id = events.id))))) AND (NOT (EXISTS ( SELECT profiles_blocked.blocked_id
   FROM public.profiles_blocked
  WHERE (((profiles_blocked.profile_id = events.creator_id) AND (profiles_blocked.blocked_id = auth.uid())) OR ((profiles_blocked.profile_id = auth.uid()) AND (profiles_blocked.blocked_id = events.creator_id)))))))));

CREATE POLICY "Enable select for reporter profile" ON "public"."event_reports" FOR SELECT USING ((auth.uid() = reporter_id));

CREATE POLICY "Enable select for reporter profile" ON "public"."profile_reports" FOR DELETE USING ((auth.uid() = reporter_id));

CREATE POLICY "Enable select for users who follow involved profile" ON "public"."attending" FOR SELECT USING (((auth.uid() = profile_id) OR ( SELECT profiles.public_profile
   FROM public.profiles
  WHERE (attending.profile_id = profiles.id)) OR (EXISTS ( SELECT following.follower_id,
    following.following_id,
    following.accepted
   FROM public.following
  WHERE ((following.following_id = attending.profile_id) AND following.accepted AND (following.follower_id = auth.uid())))) OR (EXISTS ( SELECT events.id
   FROM public.events
  WHERE ((events.id = attending.event_id) AND (events.creator_id = auth.uid()))))));

CREATE POLICY "Enable update for creator profile" ON "public"."events" FOR UPDATE USING ((auth.uid() = creator_id)) WITH CHECK ((auth.uid() = creator_id));

CREATE POLICY "Enable update for following profile" ON "public"."following" FOR UPDATE USING ((auth.uid() = following_id)) WITH CHECK ((auth.uid() = following_id));

CREATE POLICY "Enable update for involved profile" ON "public"."attending" FOR UPDATE USING ((auth.uid() = profile_id)) WITH CHECK ((auth.uid() = profile_id));

CREATE POLICY "Enable update for involved profiles" ON "public"."interested" FOR UPDATE USING ((profile_id = auth.uid())) WITH CHECK ((profile_id = auth.uid()));

CREATE POLICY "Enable update for reporter profile" ON "public"."event_reports" FOR UPDATE USING ((auth.uid() = reporter_id)) WITH CHECK ((auth.uid() = reporter_id));

CREATE POLICY "Enable update for reporter profile" ON "public"."profile_reports" FOR UPDATE USING ((auth.uid() = reporter_id)) WITH CHECK ((auth.uid() = reporter_id));

CREATE POLICY "Public profiles are viewable by everyone." ON "public"."profiles" FOR SELECT USING (true);

CREATE POLICY "Users can insert their own profile." ON "public"."profiles" FOR INSERT WITH CHECK ((auth.uid() = id));

CREATE POLICY "Users can update own profile." ON "public"."profiles" FOR UPDATE USING ((auth.uid() = id));

ALTER TABLE "public"."attending" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."cities" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."event_reports" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."events" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."following" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."interested" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_reports" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."profiles_blocked" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."spatial_ref_sys" ENABLE ROW LEVEL SECURITY;

REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT ALL ON SCHEMA "public" TO PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON FUNCTION "public"."box2d_in"(cstring) TO "anon";
GRANT ALL ON FUNCTION "public"."box2d_in"(cstring) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d_in"(cstring) TO "service_role";

GRANT ALL ON FUNCTION "public"."box2d_out"(public.box2d) TO "anon";
GRANT ALL ON FUNCTION "public"."box2d_out"(public.box2d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d_out"(public.box2d) TO "service_role";

GRANT ALL ON FUNCTION "public"."box2df_in"(cstring) TO "anon";
GRANT ALL ON FUNCTION "public"."box2df_in"(cstring) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2df_in"(cstring) TO "service_role";

GRANT ALL ON FUNCTION "public"."box2df_out"(public.box2df) TO "anon";
GRANT ALL ON FUNCTION "public"."box2df_out"(public.box2df) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2df_out"(public.box2df) TO "service_role";

GRANT ALL ON FUNCTION "public"."box3d_in"(cstring) TO "anon";
GRANT ALL ON FUNCTION "public"."box3d_in"(cstring) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d_in"(cstring) TO "service_role";

GRANT ALL ON FUNCTION "public"."box3d_out"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."box3d_out"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d_out"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_analyze"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_analyze"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_analyze"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_in"(cstring, oid, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_in"(cstring, oid, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_in"(cstring, oid, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_out"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_out"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_out"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_recv"(internal, oid, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_recv"(internal, oid, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_recv"(internal, oid, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_send"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_send"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_send"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_typmod_in"(cstring[]) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_typmod_in"(cstring[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_typmod_in"(cstring[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_analyze"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_analyze"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_analyze"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_in"(cstring) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_in"(cstring) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_in"(cstring) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_out"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_out"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_out"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_recv"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_recv"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_recv"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_send"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_send"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_send"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_typmod_in"(cstring[]) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_typmod_in"(cstring[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_typmod_in"(cstring[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."gidx_in"(cstring) TO "anon";
GRANT ALL ON FUNCTION "public"."gidx_in"(cstring) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gidx_in"(cstring) TO "service_role";

GRANT ALL ON FUNCTION "public"."gidx_out"(public.gidx) TO "anon";
GRANT ALL ON FUNCTION "public"."gidx_out"(public.gidx) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gidx_out"(public.gidx) TO "service_role";

GRANT ALL ON FUNCTION "public"."spheroid_in"(cstring) TO "anon";
GRANT ALL ON FUNCTION "public"."spheroid_in"(cstring) TO "authenticated";
GRANT ALL ON FUNCTION "public"."spheroid_in"(cstring) TO "service_role";

GRANT ALL ON FUNCTION "public"."spheroid_out"(public.spheroid) TO "anon";
GRANT ALL ON FUNCTION "public"."spheroid_out"(public.spheroid) TO "authenticated";
GRANT ALL ON FUNCTION "public"."spheroid_out"(public.spheroid) TO "service_role";

GRANT ALL ON FUNCTION "public"."box3d"(public.box2d) TO "anon";
GRANT ALL ON FUNCTION "public"."box3d"(public.box2d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d"(public.box2d) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry"(public.box2d) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"(public.box2d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"(public.box2d) TO "service_role";

GRANT ALL ON FUNCTION "public"."box"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."box"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."box2d"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."box2d"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."geography"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."bytea"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."bytea"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bytea"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography"(public.geography, integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."geography"(public.geography, integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography"(public.geography, integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."box"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."box"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."box2d"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."box2d"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."box3d"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."box3d"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."bytea"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."bytea"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bytea"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geography"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry"(public.geometry, integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"(public.geometry, integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"(public.geometry, integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."json"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."json"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."json"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."jsonb"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."jsonb"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."jsonb"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."path"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."path"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."path"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."point"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."point"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."point"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."polygon"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."polygon"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."polygon"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."text"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."text"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."text"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry"(path) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"(path) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"(path) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry"(point) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"(point) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"(point) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry"(polygon) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"(polygon) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"(polygon) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."_postgis_deprecate"(oldname text, newname text, version text) TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_deprecate"(oldname text, newname text, version text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_deprecate"(oldname text, newname text, version text) TO "service_role";

GRANT ALL ON FUNCTION "public"."_postgis_index_extent"(tbl regclass, col text) TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_index_extent"(tbl regclass, col text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_index_extent"(tbl regclass, col text) TO "service_role";

GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"(regclass, text, regclass, text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"(regclass, text, regclass, text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"(regclass, text, regclass, text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."_postgis_selectivity"(tbl regclass, att_name text, geom public.geometry, mode text) TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_selectivity"(tbl regclass, att_name text, geom public.geometry, mode text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_selectivity"(tbl regclass, att_name text, geom public.geometry, mode text) TO "service_role";

GRANT ALL ON FUNCTION "public"."_postgis_stats"(tbl regclass, att_name text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_stats"(tbl regclass, att_name text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_stats"(tbl regclass, att_name text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_3ddwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_3ddwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_3ddwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_3dintersects"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_3dintersects"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_3dintersects"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, public.geometry, integer, integer, text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, public.geometry, integer, integer, text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, public.geometry, integer, integer, text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, public.geometry, integer, integer, text) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, public.geometry, integer, integer, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, public.geometry, integer, integer, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_bestsrid"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_bestsrid"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_concavehull"(param_inputgeom public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_concavehull"(param_inputgeom public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_concavehull"(param_inputgeom public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_contains"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_contains"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_contains"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_containsproperly"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_containsproperly"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_containsproperly"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_coveredby"(geog1 public.geography, geog2 public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_coveredby"(geog1 public.geography, geog2 public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_coveredby"(geog1 public.geography, geog2 public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_coveredby"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_coveredby"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_coveredby"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_covers"(geog1 public.geography, geog2 public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_covers"(geog1 public.geography, geog2 public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_covers"(geog1 public.geography, geog2 public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_covers"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_covers"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_covers"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_crosses"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_crosses"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_crosses"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_dfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_distancetree"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distancetree"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distancetree"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_distancetree"(public.geography, public.geography, double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distancetree"(public.geography, public.geography, double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distancetree"(public.geography, public.geography, double precision, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_distanceuncached"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_distanceuncached"(public.geography, public.geography, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"(public.geography, public.geography, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"(public.geography, public.geography, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_distanceuncached"(public.geography, public.geography, double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"(public.geography, public.geography, double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"(public.geography, public.geography, double precision, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_dwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_dwithin"(geog1 public.geography, geog2 public.geography, tolerance double precision, use_spheroid boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithin"(geog1 public.geography, geog2 public.geography, tolerance double precision, use_spheroid boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithin"(geog1 public.geography, geog2 public.geography, tolerance double precision, use_spheroid boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"(public.geography, public.geography, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"(public.geography, public.geography, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"(public.geography, public.geography, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"(public.geography, public.geography, double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"(public.geography, public.geography, double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"(public.geography, public.geography, double precision, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_equals"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_equals"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_equals"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_expand"(public.geography, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_expand"(public.geography, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_expand"(public.geography, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_geomfromgml"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_geomfromgml"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_geomfromgml"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_intersects"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_intersects"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_intersects"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"(line1 public.geometry, line2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"(line1 public.geometry, line2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"(line1 public.geometry, line2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_longestline"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_longestline"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_longestline"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_maxdistance"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_maxdistance"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_maxdistance"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_orderingequals"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_orderingequals"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_orderingequals"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_overlaps"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_overlaps"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_overlaps"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_pointoutside"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_pointoutside"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_pointoutside"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_sortablehash"(geom public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_sortablehash"(geom public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_sortablehash"(geom public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_touches"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_touches"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_touches"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_voronoi"(g1 public.geometry, clip public.geometry, tolerance double precision, return_polygons boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_voronoi"(g1 public.geometry, clip public.geometry, tolerance double precision, return_polygons boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_voronoi"(g1 public.geometry, clip public.geometry, tolerance double precision, return_polygons boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."_st_within"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_within"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_within"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."addauth"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."addauth"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addauth"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."addgeometrycolumn"(table_name character varying, column_name character varying, new_srid integer, new_type character varying, new_dim integer, use_typmod boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"(table_name character varying, column_name character varying, new_srid integer, new_type character varying, new_dim integer, use_typmod boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"(table_name character varying, column_name character varying, new_srid integer, new_type character varying, new_dim integer, use_typmod boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."addgeometrycolumn"(schema_name character varying, table_name character varying, column_name character varying, new_srid integer, new_type character varying, new_dim integer, use_typmod boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"(schema_name character varying, table_name character varying, column_name character varying, new_srid integer, new_type character varying, new_dim integer, use_typmod boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"(schema_name character varying, table_name character varying, column_name character varying, new_srid integer, new_type character varying, new_dim integer, use_typmod boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."addgeometrycolumn"(catalog_name character varying, schema_name character varying, table_name character varying, column_name character varying, new_srid_in integer, new_type character varying, new_dim integer, use_typmod boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"(catalog_name character varying, schema_name character varying, table_name character varying, column_name character varying, new_srid_in integer, new_type character varying, new_dim integer, use_typmod boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"(catalog_name character varying, schema_name character varying, table_name character varying, column_name character varying, new_srid_in integer, new_type character varying, new_dim integer, use_typmod boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."autocomplete_cities"(search_text text) TO "anon";
GRANT ALL ON FUNCTION "public"."autocomplete_cities"(search_text text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."autocomplete_cities"(search_text text) TO "service_role";

GRANT ALL ON FUNCTION "public"."box3dtobox"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."box3dtobox"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3dtobox"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."checkauth"(text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."checkauth"(text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."checkauth"(text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."checkauth"(text, text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."checkauth"(text, text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."checkauth"(text, text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "service_role";

GRANT ALL ON FUNCTION "public"."contains_2d"(public.box2df, public.box2df) TO "anon";
GRANT ALL ON FUNCTION "public"."contains_2d"(public.box2df, public.box2df) TO "authenticated";
GRANT ALL ON FUNCTION "public"."contains_2d"(public.box2df, public.box2df) TO "service_role";

GRANT ALL ON FUNCTION "public"."contains_2d"(public.box2df, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."contains_2d"(public.box2df, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."contains_2d"(public.box2df, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."contains_2d"(public.geometry, public.box2df) TO "anon";
GRANT ALL ON FUNCTION "public"."contains_2d"(public.geometry, public.box2df) TO "authenticated";
GRANT ALL ON FUNCTION "public"."contains_2d"(public.geometry, public.box2df) TO "service_role";

GRANT ALL ON FUNCTION "public"."delete_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_user"() TO "service_role";

GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "anon";
GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "service_role";

GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"(table_name character varying, column_name character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"(table_name character varying, column_name character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"(table_name character varying, column_name character varying) TO "service_role";

GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"(schema_name character varying, table_name character varying, column_name character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"(schema_name character varying, table_name character varying, column_name character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"(schema_name character varying, table_name character varying, column_name character varying) TO "service_role";

GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"(catalog_name character varying, schema_name character varying, table_name character varying, column_name character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"(catalog_name character varying, schema_name character varying, table_name character varying, column_name character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"(catalog_name character varying, schema_name character varying, table_name character varying, column_name character varying) TO "service_role";

GRANT ALL ON FUNCTION "public"."dropgeometrytable"(table_name character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"(table_name character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"(table_name character varying) TO "service_role";

GRANT ALL ON FUNCTION "public"."dropgeometrytable"(schema_name character varying, table_name character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"(schema_name character varying, table_name character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"(schema_name character varying, table_name character varying) TO "service_role";

GRANT ALL ON FUNCTION "public"."dropgeometrytable"(catalog_name character varying, schema_name character varying, table_name character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"(catalog_name character varying, schema_name character varying, table_name character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"(catalog_name character varying, schema_name character varying, table_name character varying) TO "service_role";

GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "anon";
GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "service_role";

GRANT ALL ON FUNCTION "public"."equals"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."equals"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."equals"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "service_role";

GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"(internal, internal, internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"(internal, internal, internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"(internal, internal, internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_cmp"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_cmp"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_cmp"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_distance_knn"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_distance_knn"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_distance_knn"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_eq"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_eq"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_eq"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_ge"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_ge"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_ge"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_gist_compress"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_compress"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_compress"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_gist_consistent"(internal, public.geography, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_consistent"(internal, public.geography, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_consistent"(internal, public.geography, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_gist_decompress"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_decompress"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_decompress"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_gist_distance"(internal, public.geography, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_distance"(internal, public.geography, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_distance"(internal, public.geography, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_gist_penalty"(internal, internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_penalty"(internal, internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_penalty"(internal, internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_gist_same"(public.box2d, public.box2d, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_same"(public.box2d, public.box2d, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_same"(public.box2d, public.box2d, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_gist_union"(bytea, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_union"(bytea, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_union"(bytea, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_gt"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gt"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gt"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_le"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_le"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_le"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_lt"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_lt"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_lt"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_overlaps"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_overlaps"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_overlaps"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"(internal, internal, internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"(internal, internal, internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"(internal, internal, internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"(internal, internal, internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"(internal, internal, internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"(internal, internal, internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"(internal, internal, internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"(internal, internal, internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"(internal, internal, internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_above"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_above"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_above"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_below"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_below"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_below"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_cmp"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_cmp"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_cmp"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_contained_3d"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contained_3d"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contained_3d"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_contains"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contains"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contains"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_contains_3d"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contains_3d"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contains_3d"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_contains_nd"(public.geometry, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contains_nd"(public.geometry, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contains_nd"(public.geometry, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_distance_box"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_box"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_box"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"(public.geometry, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"(public.geometry, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"(public.geometry, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"(public.geometry, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"(public.geometry, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"(public.geometry, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_eq"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_eq"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_eq"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_ge"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_ge"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_ge"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"(internal, public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"(internal, public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"(internal, public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"(internal, public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"(internal, public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"(internal, public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"(internal, public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"(internal, public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"(internal, public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"(internal, public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"(internal, public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"(internal, public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"(internal, internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"(internal, internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"(internal, internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"(internal, internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"(internal, internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"(internal, internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"(geom1 public.geometry, geom2 public.geometry, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"(geom1 public.geometry, geom2 public.geometry, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"(geom1 public.geometry, geom2 public.geometry, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"(public.geometry, public.geometry, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"(public.geometry, public.geometry, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"(public.geometry, public.geometry, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"(bytea, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"(bytea, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"(bytea, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"(bytea, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"(bytea, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"(bytea, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_gt"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gt"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gt"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_hash"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_hash"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_hash"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_le"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_le"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_le"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_left"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_left"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_left"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_lt"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_lt"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_lt"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_overabove"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overabove"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overabove"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_overbelow"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overbelow"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overbelow"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_overlaps"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overlaps"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overlaps"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"(public.geometry, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"(public.geometry, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"(public.geometry, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_overleft"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overleft"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overleft"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_overright"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overright"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overright"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_right"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_right"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_right"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_same"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_same"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_same"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_same_3d"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_same_3d"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_same_3d"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_same_nd"(public.geometry, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_same_nd"(public.geometry, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_same_nd"(public.geometry, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_sortsupport"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_sortsupport"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_sortsupport"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_within"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_within"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_within"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometry_within_nd"(public.geometry, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_within_nd"(public.geometry, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_within_nd"(public.geometry, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometrytype"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."geometrytype"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometrytype"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."geometrytype"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."geometrytype"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometrytype"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."geomfromewkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."geomfromewkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geomfromewkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."geomfromewkt"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."geomfromewkt"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geomfromewkt"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_event"(filter_event_id uuid) TO "anon";
GRANT ALL ON FUNCTION "public"."get_event"(filter_event_id uuid) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_event"(filter_event_id uuid) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_event_data"(filter_event_id uuid) TO "anon";
GRANT ALL ON FUNCTION "public"."get_event_data"(filter_event_id uuid) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_event_data"(filter_event_id uuid) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_profile_stats"(filter_profile_id uuid) TO "anon";
GRANT ALL ON FUNCTION "public"."get_profile_stats"(filter_profile_id uuid) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_profile_stats"(filter_profile_id uuid) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "anon";
GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "service_role";

GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"(internal, oid, internal, smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"(internal, oid, internal, smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"(internal, oid, internal, smallint) TO "service_role";

GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"(internal, oid, internal, smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"(internal, oid, internal, smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"(internal, oid, internal, smallint) TO "service_role";

GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"(internal, oid, internal, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"(internal, oid, internal, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"(internal, oid, internal, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"(internal, oid, internal, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"(internal, oid, internal, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"(internal, oid, internal, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";

GRANT ALL ON FUNCTION "public"."is_contained_2d"(public.box2df, public.box2df) TO "anon";
GRANT ALL ON FUNCTION "public"."is_contained_2d"(public.box2df, public.box2df) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_contained_2d"(public.box2df, public.box2df) TO "service_role";

GRANT ALL ON FUNCTION "public"."is_contained_2d"(public.box2df, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."is_contained_2d"(public.box2df, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_contained_2d"(public.box2df, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."is_contained_2d"(public.geometry, public.box2df) TO "anon";
GRANT ALL ON FUNCTION "public"."is_contained_2d"(public.geometry, public.box2df) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_contained_2d"(public.geometry, public.box2df) TO "service_role";

GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text, timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text, timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text, timestamp without time zone) TO "service_role";

GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text, text, timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text, text, timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"(text, text, text, text, timestamp without time zone) TO "service_role";

GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "anon";
GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "service_role";

GRANT ALL ON FUNCTION "public"."overlaps_2d"(public.box2df, public.box2df) TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_2d"(public.box2df, public.box2df) TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_2d"(public.box2df, public.box2df) TO "service_role";

GRANT ALL ON FUNCTION "public"."overlaps_2d"(public.box2df, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_2d"(public.box2df, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_2d"(public.box2df, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."overlaps_2d"(public.geometry, public.box2df) TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_2d"(public.geometry, public.box2df) TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_2d"(public.geometry, public.box2df) TO "service_role";

GRANT ALL ON FUNCTION "public"."overlaps_geog"(public.geography, public.gidx) TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_geog"(public.geography, public.gidx) TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_geog"(public.geography, public.gidx) TO "service_role";

GRANT ALL ON FUNCTION "public"."overlaps_geog"(public.gidx, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_geog"(public.gidx, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_geog"(public.gidx, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."overlaps_geog"(public.gidx, public.gidx) TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_geog"(public.gidx, public.gidx) TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_geog"(public.gidx, public.gidx) TO "service_role";

GRANT ALL ON FUNCTION "public"."overlaps_nd"(public.geometry, public.gidx) TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_nd"(public.geometry, public.gidx) TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_nd"(public.geometry, public.gidx) TO "service_role";

GRANT ALL ON FUNCTION "public"."overlaps_nd"(public.gidx, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_nd"(public.gidx, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_nd"(public.gidx, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."overlaps_nd"(public.gidx, public.gidx) TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_nd"(public.gidx, public.gidx) TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_nd"(public.gidx, public.gidx) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"(internal, anyelement) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"(internal, anyelement) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"(internal, anyelement) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"(internal, anyelement, text) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"(internal, anyelement, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"(internal, anyelement, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"(internal, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"(internal, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"(internal, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"(bytea, internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"(bytea, internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"(bytea, internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text, integer, text) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text, integer, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text, integer, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text, integer, text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text, integer, text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"(internal, anyelement, text, integer, text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"(internal, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"(internal, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"(internal, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"(internal, public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"(internal, public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"(internal, public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"(internal, public.geometry, double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"(internal, public.geometry, double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"(internal, public.geometry, double precision, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."populate_geometry_columns"(use_typmod boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"(use_typmod boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"(use_typmod boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."populate_geometry_columns"(tbl_oid oid, use_typmod boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"(tbl_oid oid, use_typmod boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"(tbl_oid oid, use_typmod boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_addbbox"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_addbbox"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_addbbox"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"(geomschema text, geomtable text, geomcolumn text) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"(geomschema text, geomtable text, geomcolumn text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"(geomschema text, geomtable text, geomcolumn text) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"(geomschema text, geomtable text, geomcolumn text) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"(geomschema text, geomtable text, geomcolumn text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"(geomschema text, geomtable text, geomcolumn text) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_constraint_type"(geomschema text, geomtable text, geomcolumn text) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_constraint_type"(geomschema text, geomtable text, geomcolumn text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_constraint_type"(geomschema text, geomtable text, geomcolumn text) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_dropbbox"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_dropbbox"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_dropbbox"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_geos_noop"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_geos_noop"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_geos_noop"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_getbbox"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_getbbox"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_getbbox"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_hasbbox"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_hasbbox"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_hasbbox"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"(internal) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"(internal) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"(internal) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_noop"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_noop"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_noop"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"(geom public.geometry, text, text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"(geom public.geometry, text, text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"(geom public.geometry, text, text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_type_name"(geomname character varying, coord_dimension integer, use_new_name boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_type_name"(geomname character varying, coord_dimension integer, use_new_name boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_type_name"(geomname character varying, coord_dimension integer, use_new_name boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "service_role";

GRANT ALL ON FUNCTION "public"."query_events_feed"(filter_location text, filter_radius integer, filter_end_datetime timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."query_events_feed"(filter_location text, filter_radius integer, filter_end_datetime timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."query_events_feed"(filter_location text, filter_radius integer, filter_end_datetime timestamp without time zone) TO "service_role";

GRANT ALL ON FUNCTION "public"."query_events_profile_past"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."query_events_profile_past"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."query_events_profile_past"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) TO "service_role";

GRANT ALL ON FUNCTION "public"."query_events_profile_upcoming"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."query_events_profile_upcoming"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."query_events_profile_upcoming"(filter_creator_id uuid, filter_end_datetime timestamp without time zone) TO "service_role";

GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";

GRANT ALL ON FUNCTION "public"."query_profiles_attending"(filter_event_id uuid) TO "anon";
GRANT ALL ON FUNCTION "public"."query_profiles_attending"(filter_event_id uuid) TO "authenticated";
GRANT ALL ON FUNCTION "public"."query_profiles_attending"(filter_event_id uuid) TO "service_role";

GRANT ALL ON FUNCTION "public"."query_profiles_follower"() TO "anon";
GRANT ALL ON FUNCTION "public"."query_profiles_follower"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."query_profiles_follower"() TO "service_role";

GRANT ALL ON FUNCTION "public"."query_profiles_following"() TO "anon";
GRANT ALL ON FUNCTION "public"."query_profiles_following"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."query_profiles_following"() TO "service_role";

GRANT ALL ON FUNCTION "public"."query_profiles_interested"(filter_event_id uuid) TO "anon";
GRANT ALL ON FUNCTION "public"."query_profiles_interested"(filter_event_id uuid) TO "authenticated";
GRANT ALL ON FUNCTION "public"."query_profiles_interested"(filter_event_id uuid) TO "service_role";

GRANT ALL ON FUNCTION "public"."repeat_events"() TO "anon";
GRANT ALL ON FUNCTION "public"."repeat_events"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."repeat_events"() TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3ddistance"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3ddistance"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3ddistance"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3ddwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3ddwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3ddwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dintersects"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dintersects"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dintersects"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dlength"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dlength"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dlength"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dlongestline"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dlongestline"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dlongestline"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dmakebox"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dmakebox"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dmakebox"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dperimeter"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dperimeter"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dperimeter"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dshortestline"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dshortestline"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dshortestline"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_addmeasure"(public.geometry, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_addmeasure"(public.geometry, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_addmeasure"(public.geometry, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_addpoint"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_addpoint"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_addpoint"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_addpoint"(geom1 public.geometry, geom2 public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_addpoint"(geom1 public.geometry, geom2 public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_addpoint"(geom1 public.geometry, geom2 public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_affine"(public.geometry, double precision, double precision, double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_affine"(public.geometry, double precision, double precision, double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_affine"(public.geometry, double precision, double precision, double precision, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_affine"(public.geometry, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_affine"(public.geometry, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_affine"(public.geometry, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_angle"(line1 public.geometry, line2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_angle"(line1 public.geometry, line2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_angle"(line1 public.geometry, line2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_angle"(pt1 public.geometry, pt2 public.geometry, pt3 public.geometry, pt4 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_angle"(pt1 public.geometry, pt2 public.geometry, pt3 public.geometry, pt4 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_angle"(pt1 public.geometry, pt2 public.geometry, pt3 public.geometry, pt4 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_area"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_area"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_area"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_area"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_area"(geog public.geography, use_spheroid boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_area"(geog public.geography, use_spheroid boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area"(geog public.geography, use_spheroid boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_area2d"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_area2d"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area2d"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geography, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geography, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geography, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geometry, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geometry, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"(public.geometry, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"(geom public.geometry, nprecision integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"(geom public.geometry, nprecision integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"(geom public.geometry, nprecision integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asewkb"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkb"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkb"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asewkb"(public.geometry, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkb"(public.geometry, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkb"(public.geometry, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asewkt"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geography, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geography, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geography, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgeojson"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgeojson"(geog public.geography, maxdecimaldigits integer, options integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"(geog public.geography, maxdecimaldigits integer, options integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"(geog public.geography, maxdecimaldigits integer, options integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgeojson"(geom public.geometry, maxdecimaldigits integer, options integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"(geom public.geometry, maxdecimaldigits integer, options integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"(geom public.geometry, maxdecimaldigits integer, options integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgeojson"(r record, geom_column text, maxdecimaldigits integer, pretty_bool boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"(r record, geom_column text, maxdecimaldigits integer, pretty_bool boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"(r record, geom_column text, maxdecimaldigits integer, pretty_bool boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgml"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgml"(geom public.geometry, maxdecimaldigits integer, options integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"(geom public.geometry, maxdecimaldigits integer, options integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"(geom public.geometry, maxdecimaldigits integer, options integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgml"(geog public.geography, maxdecimaldigits integer, options integer, nprefix text, id text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"(geog public.geography, maxdecimaldigits integer, options integer, nprefix text, id text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"(geog public.geography, maxdecimaldigits integer, options integer, nprefix text, id text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgml"(version integer, geog public.geography, maxdecimaldigits integer, options integer, nprefix text, id text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"(version integer, geog public.geography, maxdecimaldigits integer, options integer, nprefix text, id text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"(version integer, geog public.geography, maxdecimaldigits integer, options integer, nprefix text, id text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgml"(version integer, geom public.geometry, maxdecimaldigits integer, options integer, nprefix text, id text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"(version integer, geom public.geometry, maxdecimaldigits integer, options integer, nprefix text, id text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"(version integer, geom public.geometry, maxdecimaldigits integer, options integer, nprefix text, id text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_ashexewkb"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_ashexewkb"(public.geometry, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"(public.geometry, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"(public.geometry, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_askml"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_askml"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_askml"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_askml"(geog public.geography, maxdecimaldigits integer, nprefix text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_askml"(geog public.geography, maxdecimaldigits integer, nprefix text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_askml"(geog public.geography, maxdecimaldigits integer, nprefix text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_askml"(geom public.geometry, maxdecimaldigits integer, nprefix text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_askml"(geom public.geometry, maxdecimaldigits integer, nprefix text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_askml"(geom public.geometry, maxdecimaldigits integer, nprefix text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_aslatlontext"(geom public.geometry, tmpl text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_aslatlontext"(geom public.geometry, tmpl text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_aslatlontext"(geom public.geometry, tmpl text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asmvtgeom"(geom public.geometry, bounds public.box2d, extent integer, buffer integer, clip_geom boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvtgeom"(geom public.geometry, bounds public.box2d, extent integer, buffer integer, clip_geom boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvtgeom"(geom public.geometry, bounds public.box2d, extent integer, buffer integer, clip_geom boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_assvg"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_assvg"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_assvg"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_assvg"(geog public.geography, rel integer, maxdecimaldigits integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_assvg"(geog public.geography, rel integer, maxdecimaldigits integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_assvg"(geog public.geography, rel integer, maxdecimaldigits integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_assvg"(geom public.geometry, rel integer, maxdecimaldigits integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_assvg"(geom public.geometry, rel integer, maxdecimaldigits integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_assvg"(geom public.geometry, rel integer, maxdecimaldigits integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_astext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_astext"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_astext"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_astext"(public.geography, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"(public.geography, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"(public.geography, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_astext"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_astwkb"(geom public.geometry, prec integer, prec_z integer, prec_m integer, with_sizes boolean, with_boxes boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astwkb"(geom public.geometry, prec integer, prec_z integer, prec_m integer, with_sizes boolean, with_boxes boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astwkb"(geom public.geometry, prec integer, prec_z integer, prec_m integer, with_sizes boolean, with_boxes boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_astwkb"(geom public.geometry[], ids bigint[], prec integer, prec_z integer, prec_m integer, with_sizes boolean, with_boxes boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astwkb"(geom public.geometry[], ids bigint[], prec integer, prec_z integer, prec_m integer, with_sizes boolean, with_boxes boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astwkb"(geom public.geometry[], ids bigint[], prec integer, prec_z integer, prec_m integer, with_sizes boolean, with_boxes boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asx3d"(geom public.geometry, maxdecimaldigits integer, options integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asx3d"(geom public.geometry, maxdecimaldigits integer, options integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asx3d"(geom public.geometry, maxdecimaldigits integer, options integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_azimuth"(geog1 public.geography, geog2 public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_azimuth"(geog1 public.geography, geog2 public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_azimuth"(geog1 public.geography, geog2 public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_azimuth"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_azimuth"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_azimuth"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_boundary"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_boundary"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_boundary"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"(geom public.geometry, fits boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"(geom public.geometry, fits boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"(geom public.geometry, fits boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_buffer"(text, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"(text, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"(text, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_buffer"(public.geography, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"(public.geography, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"(public.geography, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_buffer"(text, double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"(text, double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"(text, double precision, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_buffer"(text, double precision, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"(text, double precision, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"(text, double precision, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_buffer"(public.geography, double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"(public.geography, double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"(public.geography, double precision, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_buffer"(public.geography, double precision, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"(public.geography, double precision, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"(public.geography, double precision, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_buffer"(geom public.geometry, radius double precision, quadsegs integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"(geom public.geometry, radius double precision, quadsegs integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"(geom public.geometry, radius double precision, quadsegs integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_buffer"(geom public.geometry, radius double precision, options text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"(geom public.geometry, radius double precision, options text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"(geom public.geometry, radius double precision, options text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_buildarea"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buildarea"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buildarea"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_centroid"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_centroid"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_centroid"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_centroid"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_centroid"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_centroid"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_centroid"(public.geography, use_spheroid boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_centroid"(public.geography, use_spheroid boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_centroid"(public.geography, use_spheroid boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"(public.geometry, integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"(public.geometry, integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"(public.geometry, integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_cleangeometry"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_cleangeometry"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_cleangeometry"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_clipbybox2d"(geom public.geometry, box public.box2d) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clipbybox2d"(geom public.geometry, box public.box2d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clipbybox2d"(geom public.geometry, box public.box2d) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_closestpoint"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_closestpoint"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_closestpoint"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"(public.geometry, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"(public.geometry, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"(public.geometry, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_clusterdbscan"(public.geometry, eps double precision, minpoints integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterdbscan"(public.geometry, eps double precision, minpoints integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterdbscan"(public.geometry, eps double precision, minpoints integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_clusterintersecting"(public.geometry[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"(public.geometry[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"(public.geometry[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_clusterwithin"(public.geometry[], double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"(public.geometry[], double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"(public.geometry[], double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_collect"(public.geometry[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collect"(public.geometry[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collect"(public.geometry[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_collect"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collect"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collect"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_collectionextract"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collectionextract"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collectionextract"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_collectionextract"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collectionextract"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collectionextract"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_combinebbox"(public.box2d, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_combinebbox"(public.box2d, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_combinebbox"(public.box2d, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_combinebbox"(public.box3d, public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."st_combinebbox"(public.box3d, public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_combinebbox"(public.box3d, public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_combinebbox"(public.box3d, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_combinebbox"(public.box3d, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_combinebbox"(public.box3d, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_concavehull"(param_geom public.geometry, param_pctconvex double precision, param_allow_holes boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_concavehull"(param_geom public.geometry, param_pctconvex double precision, param_allow_holes boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_concavehull"(param_geom public.geometry, param_pctconvex double precision, param_allow_holes boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_contains"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_contains"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_contains"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_containsproperly"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_containsproperly"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_containsproperly"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_convexhull"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_convexhull"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_convexhull"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_coorddim"(geometry public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_coorddim"(geometry public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coorddim"(geometry public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_coveredby"(text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_coveredby"(text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coveredby"(text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_coveredby"(geog1 public.geography, geog2 public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_coveredby"(geog1 public.geography, geog2 public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coveredby"(geog1 public.geography, geog2 public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_coveredby"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_coveredby"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coveredby"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_covers"(text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_covers"(text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_covers"(text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_covers"(geog1 public.geography, geog2 public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_covers"(geog1 public.geography, geog2 public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_covers"(geog1 public.geography, geog2 public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_covers"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_covers"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_covers"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_cpawithin"(public.geometry, public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_cpawithin"(public.geometry, public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_cpawithin"(public.geometry, public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_crosses"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_crosses"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_crosses"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_curvetoline"(geom public.geometry, tol double precision, toltype integer, flags integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_curvetoline"(geom public.geometry, tol double precision, toltype integer, flags integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_curvetoline"(geom public.geometry, tol double precision, toltype integer, flags integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"(g1 public.geometry, tolerance double precision, flags integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"(g1 public.geometry, tolerance double precision, flags integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"(g1 public.geometry, tolerance double precision, flags integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_dfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dfullywithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_difference"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_difference"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_difference"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_dimension"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dimension"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dimension"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_disjoint"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_disjoint"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_disjoint"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_distance"(text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distance"(text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distance"(text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_distance"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distance"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distance"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_distance"(geog1 public.geography, geog2 public.geography, use_spheroid boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distance"(geog1 public.geography, geog2 public.geography, use_spheroid boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distance"(geog1 public.geography, geog2 public.geography, use_spheroid boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_distancecpa"(public.geometry, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancecpa"(public.geometry, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancecpa"(public.geometry, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_distancesphere"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancesphere"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancesphere"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_distancespheroid"(geom1 public.geometry, geom2 public.geometry, public.spheroid) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"(geom1 public.geometry, geom2 public.geometry, public.spheroid) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"(geom1 public.geometry, geom2 public.geometry, public.spheroid) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_dump"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dump"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dump"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_dumppoints"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dumppoints"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dumppoints"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_dumprings"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dumprings"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dumprings"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_dwithin"(text, text, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dwithin"(text, text, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dwithin"(text, text, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_dwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dwithin"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_dwithin"(geog1 public.geography, geog2 public.geography, tolerance double precision, use_spheroid boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dwithin"(geog1 public.geography, geog2 public.geography, tolerance double precision, use_spheroid boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dwithin"(geog1 public.geography, geog2 public.geography, tolerance double precision, use_spheroid boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_endpoint"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_endpoint"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_endpoint"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_envelope"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_envelope"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_envelope"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_equals"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_equals"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_equals"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_estimatedextent"(text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"(text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"(text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_estimatedextent"(text, text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"(text, text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"(text, text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_estimatedextent"(text, text, text, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"(text, text, text, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"(text, text, text, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_expand"(public.box2d, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"(public.box2d, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"(public.box2d, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_expand"(public.box3d, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"(public.box3d, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"(public.box3d, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_expand"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_expand"(box public.box2d, dx double precision, dy double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"(box public.box2d, dx double precision, dy double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"(box public.box2d, dx double precision, dy double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_expand"(box public.box3d, dx double precision, dy double precision, dz double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"(box public.box3d, dx double precision, dy double precision, dz double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"(box public.box3d, dx double precision, dy double precision, dz double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_expand"(geom public.geometry, dx double precision, dy double precision, dz double precision, dm double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"(geom public.geometry, dx double precision, dy double precision, dz double precision, dm double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"(geom public.geometry, dx double precision, dy double precision, dz double precision, dm double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_exteriorring"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_exteriorring"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_exteriorring"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_filterbym"(public.geometry, double precision, double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_filterbym"(public.geometry, double precision, double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_filterbym"(public.geometry, double precision, double precision, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_findextent"(text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_findextent"(text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_findextent"(text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_findextent"(text, text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_findextent"(text, text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_findextent"(text, text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_flipcoordinates"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_flipcoordinates"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_flipcoordinates"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_force2d"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force2d"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force2d"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_force3d"(geom public.geometry, zvalue double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force3d"(geom public.geometry, zvalue double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force3d"(geom public.geometry, zvalue double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_force3dm"(geom public.geometry, mvalue double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force3dm"(geom public.geometry, mvalue double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force3dm"(geom public.geometry, mvalue double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_force3dz"(geom public.geometry, zvalue double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force3dz"(geom public.geometry, zvalue double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force3dz"(geom public.geometry, zvalue double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_force4d"(geom public.geometry, zvalue double precision, mvalue double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force4d"(geom public.geometry, zvalue double precision, mvalue double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force4d"(geom public.geometry, zvalue double precision, mvalue double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_forcecollection"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcecollection"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcecollection"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_forcecurve"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcecurve"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcecurve"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_forcerhr"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcerhr"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcerhr"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_forcesfs"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcesfs"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcesfs"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_forcesfs"(public.geometry, version text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcesfs"(public.geometry, version text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcesfs"(public.geometry, version text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_frechetdistance"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_frechetdistance"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_frechetdistance"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_generatepoints"(area public.geometry, npoints integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_generatepoints"(area public.geometry, npoints integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_generatepoints"(area public.geometry, npoints integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_generatepoints"(area public.geometry, npoints integer, seed integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_generatepoints"(area public.geometry, npoints integer, seed integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_generatepoints"(area public.geometry, npoints integer, seed integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geogfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geogfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geogfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geogfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geogfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geogfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geographyfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geographyfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geographyfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geohash"(geog public.geography, maxchars integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geohash"(geog public.geography, maxchars integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geohash"(geog public.geography, maxchars integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geohash"(geom public.geometry, maxchars integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geohash"(geom public.geometry, maxchars integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geohash"(geom public.geometry, maxchars integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geometricmedian"(g public.geometry, tolerance double precision, max_iter integer, fail_if_not_converged boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometricmedian"(g public.geometry, tolerance double precision, max_iter integer, fail_if_not_converged boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometricmedian"(g public.geometry, tolerance double precision, max_iter integer, fail_if_not_converged boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geometryfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geometryfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geometryn"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometryn"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometryn"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geometrytype"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometrytype"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometrytype"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromewkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromewkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromewkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromewkt"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromewkt"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromewkt"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(jsonb) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(jsonb) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(jsonb) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromgml"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromgml"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromkml"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromkml"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromkml"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_geomfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_gmltosql"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_gmltosql"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_gmltosql"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_gmltosql"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_gmltosql"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_gmltosql"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_hasarc"(geometry public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_hasarc"(geometry public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hasarc"(geometry public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_hexagon"(size double precision, cell_i integer, cell_j integer, origin public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_hexagon"(size double precision, cell_i integer, cell_j integer, origin public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hexagon"(size double precision, cell_i integer, cell_j integer, origin public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_hexagongrid"(size double precision, bounds public.geometry, OUT geom public.geometry, OUT i integer, OUT j integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_hexagongrid"(size double precision, bounds public.geometry, OUT geom public.geometry, OUT i integer, OUT j integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hexagongrid"(size double precision, bounds public.geometry, OUT geom public.geometry, OUT i integer, OUT j integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_interiorringn"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_interiorringn"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_interiorringn"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_interpolatepoint"(line public.geometry, point public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_interpolatepoint"(line public.geometry, point public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_interpolatepoint"(line public.geometry, point public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_intersection"(text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersection"(text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersection"(text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_intersection"(public.geography, public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersection"(public.geography, public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersection"(public.geography, public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_intersection"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersection"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersection"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_intersects"(text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersects"(text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersects"(text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_intersects"(geog1 public.geography, geog2 public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersects"(geog1 public.geography, geog2 public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersects"(geog1 public.geography, geog2 public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_intersects"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersects"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersects"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_isclosed"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isclosed"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isclosed"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_iscollection"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_iscollection"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_iscollection"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_isempty"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isempty"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isempty"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_ispolygonccw"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_ispolygonccw"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ispolygonccw"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_ispolygoncw"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_ispolygoncw"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ispolygoncw"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_isring"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isring"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isring"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_issimple"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_issimple"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_issimple"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_isvalid"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalid"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalid"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_isvalid"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalid"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalid"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_isvaliddetail"(geom public.geometry, flags integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvaliddetail"(geom public.geometry, flags integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvaliddetail"(geom public.geometry, flags integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_isvalidreason"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_isvalidreason"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_length"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_length"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_length"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_length"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_length"(geog public.geography, use_spheroid boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_length"(geog public.geography, use_spheroid boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length"(geog public.geography, use_spheroid boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_length2d"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_length2d"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length2d"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_length2dspheroid"(public.geometry, public.spheroid) TO "anon";
GRANT ALL ON FUNCTION "public"."st_length2dspheroid"(public.geometry, public.spheroid) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length2dspheroid"(public.geometry, public.spheroid) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_lengthspheroid"(public.geometry, public.spheroid) TO "anon";
GRANT ALL ON FUNCTION "public"."st_lengthspheroid"(public.geometry, public.spheroid) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_lengthspheroid"(public.geometry, public.spheroid) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"(line1 public.geometry, line2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"(line1 public.geometry, line2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"(line1 public.geometry, line2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"(txtin text, nprecision integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"(txtin text, nprecision integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"(txtin text, nprecision integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linefromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linefromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linefromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linefromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"(public.geometry, double precision, repeat boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"(public.geometry, double precision, repeat boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"(public.geometry, double precision, repeat boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linelocatepoint"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linelocatepoint"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linelocatepoint"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linemerge"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linemerge"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linemerge"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linesubstring"(public.geometry, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linesubstring"(public.geometry, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linesubstring"(public.geometry, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_linetocurve"(geometry public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linetocurve"(geometry public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linetocurve"(geometry public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_locatealong"(geometry public.geometry, measure double precision, leftrightoffset double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_locatealong"(geometry public.geometry, measure double precision, leftrightoffset double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_locatealong"(geometry public.geometry, measure double precision, leftrightoffset double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_locatebetween"(geometry public.geometry, frommeasure double precision, tomeasure double precision, leftrightoffset double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_locatebetween"(geometry public.geometry, frommeasure double precision, tomeasure double precision, leftrightoffset double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_locatebetween"(geometry public.geometry, frommeasure double precision, tomeasure double precision, leftrightoffset double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"(geometry public.geometry, fromelevation double precision, toelevation double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"(geometry public.geometry, fromelevation double precision, toelevation double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"(geometry public.geometry, fromelevation double precision, toelevation double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_longestline"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_longestline"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_longestline"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_m"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_m"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_m"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makebox2d"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makebox2d"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makebox2d"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makeline"(public.geometry[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeline"(public.geometry[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeline"(public.geometry[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makeline"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeline"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeline"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makepolygon"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepolygon"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepolygon"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makepolygon"(public.geometry, public.geometry[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepolygon"(public.geometry, public.geometry[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepolygon"(public.geometry, public.geometry[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makevalid"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makevalid"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makevalid"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_maxdistance"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_maxdistance"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_maxdistance"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"(public.geometry, OUT center public.geometry, OUT nearest public.geometry, OUT radius double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"(public.geometry, OUT center public.geometry, OUT nearest public.geometry, OUT radius double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"(public.geometry, OUT center public.geometry, OUT nearest public.geometry, OUT radius double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_memsize"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_memsize"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_memsize"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"(inputgeom public.geometry, segs_per_quarter integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"(inputgeom public.geometry, segs_per_quarter integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"(inputgeom public.geometry, segs_per_quarter integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"(public.geometry, OUT center public.geometry, OUT radius double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"(public.geometry, OUT center public.geometry, OUT radius double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"(public.geometry, OUT center public.geometry, OUT radius double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_minimumclearance"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumclearance"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumclearance"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mlinefromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mlinefromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mpointfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mpointfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multi"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multi"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multi"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multipointfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipointfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipointfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_ndims"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_ndims"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ndims"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_node"(g public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_node"(g public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_node"(g public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_normalize"(geom public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_normalize"(geom public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_normalize"(geom public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_npoints"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_npoints"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_npoints"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_nrings"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_nrings"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_nrings"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_numgeometries"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_numgeometries"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numgeometries"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_numinteriorring"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_numinteriorring"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numinteriorring"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_numinteriorrings"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_numinteriorrings"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numinteriorrings"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_numpatches"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_numpatches"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numpatches"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_numpoints"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_numpoints"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numpoints"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_offsetcurve"(line public.geometry, distance double precision, params text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_offsetcurve"(line public.geometry, distance double precision, params text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_offsetcurve"(line public.geometry, distance double precision, params text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_orderingequals"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_orderingequals"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_orderingequals"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_orientedenvelope"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_orientedenvelope"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_orientedenvelope"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_overlaps"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_overlaps"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_overlaps"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_patchn"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_patchn"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_patchn"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_perimeter"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_perimeter"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_perimeter"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_perimeter"(geog public.geography, use_spheroid boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_perimeter"(geog public.geography, use_spheroid boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_perimeter"(geog public.geography, use_spheroid boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_perimeter2d"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_perimeter2d"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_perimeter2d"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_pointfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_pointfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_pointfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_pointfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"(public.geometry, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"(public.geometry, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"(public.geometry, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_pointn"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointn"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointn"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_pointonsurface"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointonsurface"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointonsurface"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_points"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_points"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_points"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polyfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polyfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polyfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polyfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polygon"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygon"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygon"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polygonfromtext"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polygonfromtext"(text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"(text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"(text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"(bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"(bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"(bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"(bytea, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"(bytea, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"(bytea, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polygonize"(public.geometry[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonize"(public.geometry[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonize"(public.geometry[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_project"(geog public.geography, distance double precision, azimuth double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_project"(geog public.geography, distance double precision, azimuth double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_project"(geog public.geography, distance double precision, azimuth double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"(g public.geometry, prec_x integer, prec_y integer, prec_z integer, prec_m integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"(g public.geometry, prec_x integer, prec_y integer, prec_z integer, prec_m integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"(g public.geometry, prec_x integer, prec_y integer, prec_z integer, prec_m integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_reduceprecision"(geom public.geometry, gridsize double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_reduceprecision"(geom public.geometry, gridsize double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_reduceprecision"(geom public.geometry, gridsize double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_relate"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_relate"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relate"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_relate"(geom1 public.geometry, geom2 public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_relate"(geom1 public.geometry, geom2 public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relate"(geom1 public.geometry, geom2 public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_relate"(geom1 public.geometry, geom2 public.geometry, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_relate"(geom1 public.geometry, geom2 public.geometry, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relate"(geom1 public.geometry, geom2 public.geometry, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_relatematch"(text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_relatematch"(text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relatematch"(text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_removepoint"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_removepoint"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_removepoint"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"(geom public.geometry, tolerance double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"(geom public.geometry, tolerance double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"(geom public.geometry, tolerance double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_reverse"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_reverse"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_reverse"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_rotate"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotate"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotate"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_rotate"(public.geometry, double precision, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotate"(public.geometry, double precision, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotate"(public.geometry, double precision, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_rotate"(public.geometry, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotate"(public.geometry, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotate"(public.geometry, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_rotatex"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotatex"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotatex"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_rotatey"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotatey"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotatey"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_rotatez"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotatez"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotatez"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, public.geometry, origin public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, public.geometry, origin public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, public.geometry, origin public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"(public.geometry, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_segmentize"(geog public.geography, max_segment_length double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_segmentize"(geog public.geography, max_segment_length double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_segmentize"(geog public.geography, max_segment_length double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_segmentize"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_segmentize"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_segmentize"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_seteffectivearea"(public.geometry, double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_seteffectivearea"(public.geometry, double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_seteffectivearea"(public.geometry, double precision, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_setpoint"(public.geometry, integer, public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_setpoint"(public.geometry, integer, public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_setpoint"(public.geometry, integer, public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_setsrid"(geog public.geography, srid integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_setsrid"(geog public.geography, srid integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_setsrid"(geog public.geography, srid integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_setsrid"(geom public.geometry, srid integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_setsrid"(geom public.geometry, srid integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_setsrid"(geom public.geometry, srid integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_sharedpaths"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_sharedpaths"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_sharedpaths"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_shiftlongitude"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_shiftlongitude"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_shiftlongitude"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_shortestline"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_shortestline"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_shortestline"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_simplify"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplify"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplify"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_simplify"(public.geometry, double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplify"(public.geometry, double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplify"(public.geometry, double precision, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_simplifyvw"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplifyvw"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplifyvw"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_snap"(geom1 public.geometry, geom2 public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snap"(geom1 public.geometry, geom2 public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snap"(geom1 public.geometry, geom2 public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_snaptogrid"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_snaptogrid"(public.geometry, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"(public.geometry, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"(public.geometry, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_snaptogrid"(public.geometry, double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"(public.geometry, double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"(public.geometry, double precision, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_snaptogrid"(geom1 public.geometry, geom2 public.geometry, double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"(geom1 public.geometry, geom2 public.geometry, double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"(geom1 public.geometry, geom2 public.geometry, double precision, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_split"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_split"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_split"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_square"(size double precision, cell_i integer, cell_j integer, origin public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_square"(size double precision, cell_i integer, cell_j integer, origin public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_square"(size double precision, cell_i integer, cell_j integer, origin public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_squaregrid"(size double precision, bounds public.geometry, OUT geom public.geometry, OUT i integer, OUT j integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_squaregrid"(size double precision, bounds public.geometry, OUT geom public.geometry, OUT i integer, OUT j integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_squaregrid"(size double precision, bounds public.geometry, OUT geom public.geometry, OUT i integer, OUT j integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_srid"(geog public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_srid"(geog public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_srid"(geog public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_srid"(geom public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_srid"(geom public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_srid"(geom public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_startpoint"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_startpoint"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_startpoint"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_subdivide"(geom public.geometry, maxvertices integer, gridsize double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_subdivide"(geom public.geometry, maxvertices integer, gridsize double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_subdivide"(geom public.geometry, maxvertices integer, gridsize double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_summary"(public.geography) TO "anon";
GRANT ALL ON FUNCTION "public"."st_summary"(public.geography) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_summary"(public.geography) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_summary"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_summary"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_summary"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_swapordinates"(geom public.geometry, ords cstring) TO "anon";
GRANT ALL ON FUNCTION "public"."st_swapordinates"(geom public.geometry, ords cstring) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_swapordinates"(geom public.geometry, ords cstring) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_symdifference"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_symdifference"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_symdifference"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_symmetricdifference"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_symmetricdifference"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_symmetricdifference"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_tileenvelope"(zoom integer, x integer, y integer, bounds public.geometry, margin double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_tileenvelope"(zoom integer, x integer, y integer, bounds public.geometry, margin double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_tileenvelope"(zoom integer, x integer, y integer, bounds public.geometry, margin double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_touches"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_touches"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_touches"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_transform"(public.geometry, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"(public.geometry, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"(public.geometry, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_transform"(geom public.geometry, to_proj text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"(geom public.geometry, to_proj text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"(geom public.geometry, to_proj text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_transform"(geom public.geometry, from_proj text, to_srid integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"(geom public.geometry, from_proj text, to_srid integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"(geom public.geometry, from_proj text, to_srid integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_transform"(geom public.geometry, from_proj text, to_proj text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"(geom public.geometry, from_proj text, to_proj text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"(geom public.geometry, from_proj text, to_proj text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_translate"(public.geometry, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_translate"(public.geometry, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_translate"(public.geometry, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_translate"(public.geometry, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_translate"(public.geometry, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_translate"(public.geometry, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_transscale"(public.geometry, double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transscale"(public.geometry, double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transscale"(public.geometry, double precision, double precision, double precision, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_unaryunion"(public.geometry, gridsize double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_unaryunion"(public.geometry, gridsize double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_unaryunion"(public.geometry, gridsize double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_union"(public.geometry[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"(public.geometry[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"(public.geometry[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_union"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_union"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"(geom1 public.geometry, geom2 public.geometry, gridsize double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_voronoilines"(g1 public.geometry, tolerance double precision, extend_to public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_voronoilines"(g1 public.geometry, tolerance double precision, extend_to public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_voronoilines"(g1 public.geometry, tolerance double precision, extend_to public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_voronoipolygons"(g1 public.geometry, tolerance double precision, extend_to public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_voronoipolygons"(g1 public.geometry, tolerance double precision, extend_to public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_voronoipolygons"(g1 public.geometry, tolerance double precision, extend_to public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_within"(geom1 public.geometry, geom2 public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_within"(geom1 public.geometry, geom2 public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_within"(geom1 public.geometry, geom2 public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_wkbtosql"(wkb bytea) TO "anon";
GRANT ALL ON FUNCTION "public"."st_wkbtosql"(wkb bytea) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_wkbtosql"(wkb bytea) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_wkttosql"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_wkttosql"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_wkttosql"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_wrapx"(geom public.geometry, wrap double precision, move double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_wrapx"(geom public.geometry, wrap double precision, move double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_wrapx"(geom public.geometry, wrap double precision, move double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_x"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_x"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_x"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_xmax"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."st_xmax"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_xmax"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_xmin"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."st_xmin"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_xmin"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_y"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_y"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_y"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_ymax"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."st_ymax"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ymax"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_ymin"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."st_ymin"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ymin"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_z"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_z"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_z"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_zmax"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."st_zmax"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_zmax"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_zmflag"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_zmflag"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_zmflag"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_zmin"(public.box3d) TO "anon";
GRANT ALL ON FUNCTION "public"."st_zmin"(public.box3d) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_zmin"(public.box3d) TO "service_role";

GRANT ALL ON FUNCTION "public"."unlockrows"(text) TO "anon";
GRANT ALL ON FUNCTION "public"."unlockrows"(text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."unlockrows"(text) TO "service_role";

GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."updategeometrysrid"(catalogn_name character varying, schema_name character varying, table_name character varying, column_name character varying, new_srid_in integer) TO "anon";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(catalogn_name character varying, schema_name character varying, table_name character varying, column_name character varying, new_srid_in integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(catalogn_name character varying, schema_name character varying, table_name character varying, column_name character varying, new_srid_in integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_3dextent"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dextent"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dextent"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgeobuf"(anyelement) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"(anyelement) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"(anyelement) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asgeobuf"(anyelement, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"(anyelement, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"(anyelement, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text, integer, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text, integer, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text, integer, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text, integer, text, text) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text, integer, text, text) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"(anyelement, text, integer, text, text) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_clusterintersecting"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_clusterwithin"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"(public.geometry, double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_collect"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collect"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collect"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_extent"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_extent"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_extent"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_makeline"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeline"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeline"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_memcollect"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_memcollect"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_memcollect"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_memunion"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_memunion"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_memunion"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_polygonize"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonize"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonize"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_union"(public.geometry) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"(public.geometry) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"(public.geometry) TO "service_role";

GRANT ALL ON FUNCTION "public"."st_union"(public.geometry, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"(public.geometry, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"(public.geometry, double precision) TO "service_role";

GRANT ALL ON TABLE "public"."attending" TO "anon";
GRANT ALL ON TABLE "public"."attending" TO "authenticated";
GRANT ALL ON TABLE "public"."attending" TO "service_role";

GRANT ALL ON TABLE "public"."cities" TO "anon";
GRANT ALL ON TABLE "public"."cities" TO "authenticated";
GRANT ALL ON TABLE "public"."cities" TO "service_role";

GRANT ALL ON TABLE "public"."events" TO "anon";
GRANT ALL ON TABLE "public"."events" TO "authenticated";
GRANT ALL ON TABLE "public"."events" TO "service_role";

GRANT ALL ON TABLE "public"."interested" TO "anon";
GRANT ALL ON TABLE "public"."interested" TO "authenticated";
GRANT ALL ON TABLE "public"."interested" TO "service_role";

GRANT ALL ON TABLE "public"."event_counts" TO "anon";
GRANT ALL ON TABLE "public"."event_counts" TO "authenticated";
GRANT ALL ON TABLE "public"."event_counts" TO "service_role";

GRANT ALL ON TABLE "public"."event_reports" TO "anon";
GRANT ALL ON TABLE "public"."event_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."event_reports" TO "service_role";

GRANT ALL ON TABLE "public"."following" TO "anon";
GRANT ALL ON TABLE "public"."following" TO "authenticated";
GRANT ALL ON TABLE "public"."following" TO "service_role";

REVOKE ALL ON TABLE "public"."geography_columns" FROM "supabase_admin";
GRANT ALL ON TABLE "public"."geography_columns" TO "postgres";

REVOKE ALL ON TABLE "public"."geometry_columns" FROM "supabase_admin";
GRANT ALL ON TABLE "public"."geometry_columns" TO "postgres";

GRANT ALL ON TABLE "public"."my_attending" TO "anon";
GRANT ALL ON TABLE "public"."my_attending" TO "authenticated";
GRANT ALL ON TABLE "public"."my_attending" TO "service_role";

GRANT ALL ON TABLE "public"."profile_reports" TO "anon";
GRANT ALL ON TABLE "public"."profile_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_reports" TO "service_role";

GRANT ALL ON TABLE "public"."profiles_blocked" TO "anon";
GRANT ALL ON TABLE "public"."profiles_blocked" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles_blocked" TO "service_role";

REVOKE ALL ON TABLE "public"."spatial_ref_sys" FROM "supabase_admin";
GRANT ALL ON TABLE "public"."spatial_ref_sys" TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";

RESET ALL;
