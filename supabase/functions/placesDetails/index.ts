import { serve } from 'https://deno.land/std@0.131.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'

// Add API key for Google Places API to edge function secrets.
const _GoogleApiKey_ = Deno.env.get("GOOGLE_API_KEY")!;

// Enforce JWT verification for function.

serve(async (req) => {
  const fields = "geometry";

  // This is needed if you're planning to invoke your function from a browser.
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { placeId, language, sessiontoken } = await req.json()

    // API request to Google Places API details.
    const query = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${placeId}&key=${_GoogleApiKey_}&language=${language}&fields=${fields}&sessiontoken=${sessiontoken}`;

    let response = await fetch(query)
    
    let text = await response.text()
    
    return new Response(JSON.stringify(text), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
      status: 200,
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
      status: 400,
    })
  }
})