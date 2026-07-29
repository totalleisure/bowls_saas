import { createClient } from "npm:@supabase/supabase-js@2";

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
  const obviousTerms = ["tenpin", "ten pin", "bowling alley", "hollywood bowl", "lane7"];
  return obviousTerms.some((term) => value.includes(term)) && types.includes("bowling_alley");
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
    const message = payload?.error?.message ?? `Google Places returned HTTP ${response.status}.`;
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
    const message = payload?.error?.message ?? `Google Places returned HTTP ${response.status}.`;
    throw new HttpError(502, message);
  }
  return payload as Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "POST is required." }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const googleApiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");
    const authorization = req.headers.get("Authorization");

    if (!supabaseUrl || !supabaseAnonKey || !googleApiKey) {
      throw new HttpError(500, "The venue search service is not fully configured.");
    }
    if (!authorization) throw new HttpError(401, "Authorization header is required.");

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) throw new HttpError(401, "Your sign-in has expired.");

    const body = await req.json().catch(() => { throw new HttpError(400, "Valid JSON is required."); });
    const action = requiredString(body.action, "action");
    const clubId = requiredString(body.clubId, "clubId");

    if (!["search", "details", "nearby_bowls"].includes(action)) {
      throw new HttpError(400, "Unknown venue search action.");
    }

    const units = action === "nearby_bowls" ? 3 : 1;
    const { data: allowance, error: allowanceError } = await supabase.rpc(
      "reserve_venue_places_requests",
      { p_club_id: clubId, p_action: action, p_units: units },
    );
    if (allowanceError) throw new HttpError(403, allowanceError.message);

    if (action === "details") {
      const placeId = requiredString(body.placeId, "placeId");
      const place = await googleDetails(googleApiKey, placeId);
      return jsonResponse({ place: normalisePlace(place), allowance });
    }

    const latitude = optionalNumber(body.latitude);
    const longitude = optionalNumber(body.longitude);
    validateCoordinates(latitude, longitude);

    if (action === "search") {
      const query = requiredString(body.query, "query");
      if (query.length < 3) throw new HttpError(400, "Enter at least three characters.");

      const requestBody: Record<string, unknown> = {
        textQuery: query,
        pageSize: 8,
        languageCode: "en",
        regionCode: "GB",
      };
      if (latitude !== null && longitude !== null) {
        requestBody.locationBias = {
          circle: {
            center: { latitude, longitude },
            radius: Math.min(Math.max(optionalNumber(body.radiusMetres) ?? 30000, 1000), 50000),
          },
        };
      }

      const payload = await googlePost(
        googleApiKey,
        requestBody,
        "places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.types,places.businessStatus",
      );
      const places = (payload.places ?? []).map(normalisePlace);
      return jsonResponse({ places, allowance });
    }

    if (latitude === null || longitude === null) {
      throw new HttpError(400, "The home venue needs latitude and longitude before nearby clubs can be found.");
    }

    const maxRadius = Number(allowance?.max_nearby_radius_metres ?? 50000);
    const radiusMetres = Math.min(
      Math.max(optionalNumber(body.radiusMetres) ?? 16093.4, 1000),
      Number.isFinite(maxRadius) ? maxRadius : 50000,
    );
    const queries = ["lawn bowls club", "bowls club", "bowling club"];
    const fieldMask = [
      "places.id", "places.displayName", "places.formattedAddress", "places.addressComponents",
      "places.location", "places.primaryType", "places.types", "places.businessStatus",
      "places.websiteUri", "places.googleMapsUri", "places.nationalPhoneNumber",
    ].join(",");

    const responses = await Promise.all(queries.map((textQuery) => googlePost(
      googleApiKey,
      {
        textQuery,
        pageSize: 20,
        languageCode: "en",
        regionCode: "GB",
        locationBias: {
          circle: { center: { latitude, longitude }, radius: radiusMetres },
        },
      },
      fieldMask,
    )));

    const byPlaceId = new Map<string, ReturnType<typeof normalisePlace> & { distanceMiles: number | null }>();
    for (const response of responses) {
      for (const rawPlace of response.places ?? []) {
        const place = normalisePlace(rawPlace);
        if (!place.placeId || looksLikeTenPin(place.name, place.types)) continue;
        let distanceMiles: number | null = null;
        if (place.latitude !== null && place.longitude !== null) {
          distanceMiles = haversineMiles(latitude, longitude, place.latitude, place.longitude);
          if (distanceMiles * 1609.344 > radiusMetres * 1.10) continue;
        }
        const current = byPlaceId.get(place.placeId);
        if (!current || (distanceMiles ?? Infinity) < (current.distanceMiles ?? Infinity)) {
          byPlaceId.set(place.placeId, { ...place, distanceMiles });
        }
      }
    }

    const places = [...byPlaceId.values()].sort((a, b) =>
      (a.distanceMiles ?? Infinity) - (b.distanceMiles ?? Infinity)
    );

    return jsonResponse({ places, radiusMetres, allowance });
  } catch (error) {
    if (error instanceof HttpError) return jsonResponse({ error: error.message }, error.status);
    console.error(error);
    return jsonResponse({ error: "Unexpected venue-search error." }, 500);
  }
});
