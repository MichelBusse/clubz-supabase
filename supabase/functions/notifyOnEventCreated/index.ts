import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import * as OneSignal from "https://esm.sh/@onesignal/node-onesignal@1.0.0-beta7";
import { corsHeaders } from "../_shared/cors.ts";
import * as postgres from "https://deno.land/x/postgres@v0.14.2/mod.ts";

const pool = new postgres.Pool(databaseUrl, 3, true);

const databaseUrl = Deno.env.get("SUPABASE_DB_URL")!;

// Add app id for OneSignal to edge function secrets.
const _OnesignalAppId_ = Deno.env.get("ONESIGNAL_APP_ID")!;
// Add user auth key for OneSignal to edge function secrets.
const _OnesignalUserAuthKey_ = Deno.env.get("USER_AUTH_KEY")!;
// Add rest api key for OneSignal to edge function secrets.
const _OnesignalRestApiKey_ = Deno.env.get("ONESIGNAL_REST_API_KEY")!;

const configuration = OneSignal.createConfiguration({
  userKey: _OnesignalUserAuthKey_,
  appKey: _OnesignalRestApiKey_,
});

const onesignal = new OneSignal.DefaultApi(configuration);

// Trigger function after insert for table "events".
// Do not enforce JWT verification.

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Newly inserted events record from database.
    const { record } = await req.json();

    // Do not notify anyone if event is not public.
    if (!record.visible) {
      return new Response(JSON.stringify({ message: "Event not visible" }), {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json; charset=utf-8",
        },
        status: 200,
      });
    }

    const connection = await pool.connect();

    // Get all followers of creator of event.
    const followersResult = await connection.queryObject(
      `SELECT * FROM following WHERE following_id = $1 AND accepted = TRUE`,
      record.creator_id
    );

    const followers = followersResult.rows.map(
      (follower: any) => follower.follower_id
    );

    // Get profile details of creator of event.
    const creatorResult = await connection.queryObject(
      `SELECT * FROM profiles WHERE id = $1`,
      record.creator_id
    );
    const creator = creatorResult.rows.map((creator: any) => creator.full_name);

    if (creator.length < 1) {
      return new Response(String("Creator not found"), { status: 500 });
    }

    // Build OneSignal notification object
    const notification = new OneSignal.Notification();
    notification.app_id = _OnesignalAppId_;
    notification.include_external_user_ids = followers;
    notification.contents = {
      en: `${creator} has created a new event: ${record.event_name}`,
      de: `${creator} hat ein neues Event erstellt: ${record.event_name}`,
    };
    notification.ios_badge_type = "SetTo";
    notification.ios_badge_count = 1;

    // Notify every follower of creator profile about newly created event.
    const onesignalApiRes = await onesignal.createNotification(notification);

    return new Response(
      JSON.stringify({
        message: "Notification sent successfully",
        onesignalResponse: onesignalApiRes,
      }),
      {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json; charset=utf-8",
        },
        status: 200,
      }
    );
  } catch (err) {
    return new Response(String(err?.message ?? err), { status: 500 });
  }
});
