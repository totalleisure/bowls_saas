# Venue Navigation Platform Test Checklist

## Test data

Use at least four venue records:

1. **Google-complete venue** — Place ID, coordinates, address and name.
2. **Coordinate-only venue** — coordinates and name, but no Place ID.
3. **Address-only venue** — address and name, but no Place ID or coordinates.
4. **Name-only venue** — name only.

Also briefly test a new blank venue: the **Directions** button should remain disabled until a usable destination exists.

## Expected destination order

### Google Maps

1. Google Place ID
2. Coordinates
3. Address
4. Venue name

The URL must contain:

- `api=1`
- `travelmode=driving`
- `dir_action=navigate`
- no explicit `origin`

### Waze

1. Coordinates
2. Address
3. Venue name

The URL must contain `navigate=yes`.

## Android

- Tap a venue and confirm the read-only venue details dialog opens.
- Tap **Directions** and confirm the Google Maps / Waze chooser appears.
- Choose **Google Maps**. Confirm Google Maps opens in directions/navigation mode from the phone's current location.
- Choose **Waze**. Confirm Waze opens and starts or previews navigation to the same venue.
- Repeat once with Google Maps or Waze not installed and confirm the browser fallback opens.
- Deny location permission in the map application and confirm it presents a route preview or asks for an origin rather than failing silently.

## iPhone

- Repeat the Android tests with Google Maps and Waze installed.
- Remove or offload Google Maps and confirm the Google universal URL falls back to the browser.
- Remove or offload Waze and confirm the Waze universal URL falls back to Waze's web experience.
- Confirm returning to the Bowls app does not leave the navigation chooser open.

## Windows

- Confirm **Google Maps** opens in the default external browser with the destination populated.
- Confirm the browser uses the current/estimated location when available, or asks for the origin when it is unavailable.
- Confirm **Waze** opens Waze Live Map rather than claiming desktop turn-by-turn navigation.
- Confirm venue details use the two-column layout at normal desktop widths.

## Web

- Confirm both providers open in a new tab directly from the chooser tap.
- Check that the browser does not report a blocked popup.
- Confirm the original Bowls tab remains open.
- Narrow the browser window below approximately 620 px and confirm venue details change to a single-column layout without horizontal overflow.

## Regression checks

- Ordinary members can view venue details but cannot reach the edit form.
- Admins and superusers see **Edit** and can still refresh from Google.
- Website links remain clickable and open externally.
- Google Place ID, Google Maps URL, latitude and longitude are not displayed in the venue UI.
- Venue sorting and searching remain alphabetical and functional.
