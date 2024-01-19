import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import * as OneSignal from "https://esm.sh/@onesignal/node-onesignal@1.0.0-beta7";
import { corsHeaders } from "../_shared/cors.ts";

// Add app id for OneSignal app to edge function secrets.
const _OnesignalAppId_ = Deno.env.get("ONESIGNAL_APP_ID")!;
// Add user auth key for OneSignal app to edge function secrets.
const _OnesignalUserAuthKey_ = Deno.env.get("USER_AUTH_KEY")!;
// Add rest api key for OneSignal app to edge function secrets.
const _OnesignalRestApiKey_ = Deno.env.get("ONESIGNAL_REST_API_KEY")!;

const configuration = OneSignal.createConfiguration({
  userKey: _OnesignalUserAuthKey_,
  appKey: _OnesignalRestApiKey_,
});

const onesignal = new OneSignal.DefaultApi(configuration);

// Trigger function after insert for table "following".
// Do not enforce JWT verification.

serve(async (req) => {
  // This is needed if you're planning to invoke your function from a browser.
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Newly inserted following record from database.
    const { record } = await req.json();

    // Do nothing if following is already accepted.
    if (record.accepted) {
      return new Response(
        JSON.stringify({ message: 'Following is already accepted' }),
        {
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json; charset=utf-8",
          },
          status: 200,
        }
      );
    }

    // Build OneSignal notification object
    const notification = new OneSignal.Notification();
    notification.app_id = _OnesignalAppId_;
    notification.include_external_user_ids = [record.following_id];
    notification.contents = {
      en: `You received a new follow request!`,
      de: "Du hast eine neue Follower-Anfrage erhalten!",
    };
    notification.ios_badge_type = "SetTo";
    notification.ios_badge_count = 1;

    // Send notification to profile with following_id from record.
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
