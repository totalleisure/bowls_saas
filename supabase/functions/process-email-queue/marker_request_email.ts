function escaped(value: unknown): string {
 return String(value ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#39;').replace(/\r?\n/g,'<br>');
}
export function markerRequestEmailHtml(email: {event_type?:string;body?:unknown;payload?:Record<string,unknown>}, actions: string): string | null {
 if(email.event_type!=='marker_request_opened' || email.payload?.marker_request_layout!==2) return null;
 const footer=email.payload.marker_contact_footer;
 return `${escaped(email.body)}${actions}${footer ? `<div style="margin-top:20px;padding-top:12px;border-top:1px solid #dddddd;font-size:14px;">${escaped(footer)}</div>` : ''}`;
}
