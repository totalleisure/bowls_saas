import { createClient } from "npm:@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const GOOGLE_TEXT_SEARCH_URL = "https://places.googleapis.com/v1/places:searchText";
const GOOGLE_PLACE_DETAILS_BASE = "https://places.googleapis.com/v1/places";

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new HttpError(400, `${name} is required.`);
  }
  return value.trim();
}

function optionalNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? numberValue : null;
}

function validateCoordinates(latitude: number | null, longitude: number | null): void {
  if ((latitude === null) !== (longitude === null)) {
    throw new HttpError(400, "Latitude and longitude must be supplied together.");
  }
  if (latitude !== null && (latitude < -90 || latitude > 90)) {
    throw new HttpError(400, "Latitude is outside the valid range.");
  }
  if (longitude !== null && (longitude < -180 || longitude > 180)) {
    throw new HttpError(400, "Longitude is outside the valid range.");
  }
}

function textValue(value: unknown): string | null {
  if (typeof value === "string" && value.trim() !== "") return value.trim();
  if (value && typeof value === "object" && "text" in value) {
    const text = (value as { text?: unknown }).text;
    return typeof text === "string" && text.trim() !== "" ? text.trim() : null;
  }
  return null;
}

function addressPart(components: unknown, type: string): string | null {
  if (!Array.isArray(components)) return null;
  for (const component of components) {
    if (!component || typeof component !== "object") continue;
    const types = (component as { types?: unknown }).types;
    if (!Array.isArray(types) || !types.includes(type)) continue;
    return textValue((component as { longText?: unknown }).longText) ??
      textValue((component as { shortText?: unknown }).shortText);
  }
  return null;
}

function normalisePlace(place: Record<string, unknown>) {
  const location = (place.location && typeof place.location === "object")
    ? place.location as Record<string, unknown>
    : {};
  const components = place.addressComponents;
  const townCity = addressPart(components, "postal_town") ??
    addressPart(components, "locality") ??
    addressPart(components, "administrative_area_level_2");

  return {
    placeId: typeof place.id === "string" ? place.id : null,
    name: textValue(place.displayName),
    formattedAddress: typeof place.formattedAddress === "string" ? place.formattedAddress : null,
    addressLine1: [
      addressPart(components, "street_number"),
      addressPart(components, "route"),
    ].filter(Boolean).join(" ") || null,
    addressLine2: [addressPart(components, "premise"),addressPart(components, "subpremise")].filter(Boolean).join(", ") || null,
    townCity,
    postcode: addressPart(components, "postal_code"),
    latitude: typeof location.latitude === "number" ? location.latitude : null,
    longitude: typeof location.longitude === "number" ? location.longitude : null,
    phone: typeof place.nationalPhoneNumber === "string" ? place.nationalPhoneNumber : null,
    websiteUrl: typeof place.websiteUri === "string" ? place.websiteUri : null,
    googleMapsUrl: typeof place.googleMapsUri === "string" ? place.googleMapsUri : null,
    businessStatus: typeof place.businessStatus === "string" ? place.businessStatus : null,
    primaryType: typeof place.primaryType === "string" ? place.primaryType : null,
    types: Array.isArray(place.types) ? place.types.filter((v) => typeof v === "string") : [],
  };
}

function haversineMiles(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const radians = (degrees: number) => degrees * Math.PI / 180;
  const earthRadiusMiles = 3958.7613;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLon / 2) ** 2;
  return earthRadiusMiles * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function looksLikeTenPin(name: string | null, types: string[]): boolean {
  const value = (name ?? "").toLowerCase();
  const lawnBowlsTerms = ["bowls club", "bowling club", "lawn bowls", "bowls centre", "bowls center"];
  const obviousTenPinTerms = [
    "tenpin", "ten pin", "bowling alley", "hollywood bowl", "lane7", "lane 7",
    "bloomsbury bowling", "all star lanes", "rowans", "strikz", "tenpin ltd",
  ];

  if (obviousTenPinTerms.some((term) => value.includes(term))) return true;

  // Google often categorises both lawn bowls and ten-pin venues as bowling_alley.
  // Keep a clearly named bowls club, but reject a generic bowling-alley result.
  return types.includes("bowling_alley") &&
    !lawnBowlsTerms.some((term) => value.includes(term));
}

function isLocalityOrRegion(types: string[]): boolean {
  const nonVenueTypes = new Set([
    "locality", "postal_town", "neighborhood", "sublocality", "sublocality_level_1",
    "administrative_area_level_1", "administrative_area_level_2", "administrative_area_level_3",
    "country", "postal_code", "political", "route", "street_address",
  ]);
  return types.some((type) => nonVenueTypes.has(type));
}

function looksLikeBowlsClub(name: string | null, types: string[]): boolean {
  const value = (name ?? "").toLowerCase();
  if (looksLikeTenPin(name, types) || isLocalityOrRegion(types)) return false;

  const nameSignals = [
    "bowls club", "bowling club", "lawn bowls", "bowls centre", "bowls center",
    "bowls association", "bowls academy",
  ];
  return nameSignals.some((term) => value.includes(term));
}

async function googlePost(apiKey: string, body: Record<string, unknown>, fieldMask: string) {
  const response = await fetch(GOOGLE_TEXT_SEARCH_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": fieldMask,
    },
    body: JSON.stringify(body),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const reason = payload?.error?.details?.find((d: { reason?: string }) => d.reason)?.reason;
    const message = `${payload?.error?.message ?? `Google Places returned HTTP ${response.status}.`}${reason ? ` (${reason})` : ""}`;
    throw new HttpError(502, message);
  }
  return payload as { places?: Record<string, unknown>[] };
}

async function googleDetails(apiKey: string, placeId: string) {
  const fieldMask = [
    "id", "displayName", "formattedAddress", "addressComponents", "location",
    "nationalPhoneNumber", "websiteUri", "googleMapsUri", "businessStatus",
    "primaryType", "types",
  ].join(",");

  const response = await fetch(`${GOOGLE_PLACE_DETAILS_BASE}/${encodeURIComponent(placeId)}`, {
    headers: {
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": fieldMask,
    },
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const reason = payload?.error?.details?.find((d: { reason?: string }) => d.reason)?.reason;
    const message = `${payload?.error?.message ?? `Google Places returned HTTP ${response.status}.`}${reason ? ` (${reason})` : ""}`;
    throw new HttpError(502, message);
  }
  return payload as Record<string, unknown>;
}

Deno.serve(async (req) => {
 if (req.method==='OPTIONS') return new Response('ok',{headers:corsHeaders});
 if (req.method!=='POST') return jsonResponse({error:'POST is required.'},405);
 try {
  const url=Deno.env.get('SUPABASE_URL');
  const anon=Deno.env.get('SUPABASE_ANON_KEY');
  const key=Deno.env.get('GOOGLE_PLACES_API_KEY');
  if(!['https://egxdkaotepgfjmszxlyn.supabase.co','https://xfjelvvfoguzukgvxchh.supabase.co'].includes(url??'')) throw new HttpError(403,'Unknown environment.');
  const authorization=req.headers.get('Authorization');
  if(!authorization || !anon) throw new HttpError(401,'Sign in to staging first.');
  const client=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:identityError}=await client.auth.getUser();
  if(identityError || !identity.user || identity.user.is_anonymous) throw new HttpError(401,'Sign in to staging first.');
  const {data:allowed,error:allowedError}=await client.from('app_superusers').select('user_id').eq('user_id',identity.user.id).maybeSingle();
  if(allowedError || !allowed) throw new HttpError(403,'A staging superuser is required.');
  const body=await req.json();
  if(!['search','details'].includes(body.action)) throw new HttpError(400,'Choose search or details.');
  if(!key) throw new HttpError(503,'Google Places is not configured. Your manual address has been kept.');
  const value=requiredString(body.action==='search'?body.query:body.placeId,body.action==='search'?'query':'placeId');
  if(value.length<3 || value.length>200) throw new HttpError(400,'Enter between 3 and 200 characters.');
  const {data:remaining,error:budgetError}=await client.rpc('reserve_staging_onboarding_place_request');
  if(budgetError) throw new HttpError(429,budgetError.message);
  if(body.action==='details') return jsonResponse({place:normalisePlace(await googleDetails(key,value)),remaining});
  const response=await googlePost(key,{textQuery:value,pageSize:8,languageCode:'en',regionCode:'GB'},
   'places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.types,places.businessStatus');
  const places=(response.places??[]).map(normalisePlace).filter((p:ReturnType<typeof normalisePlace>)=>p.placeId && looksLikeBowlsClub(p.name,p.types));
  return jsonResponse({places,remaining});
 } catch(error) {
  if(error instanceof HttpError) return jsonResponse({error:error.message},error.status);
  console.error('Staging onboarding place lookup failed');
  return jsonResponse({error:'Google lookup is unavailable. Your entered details have been kept. Try again later.'},503);
 }
});
