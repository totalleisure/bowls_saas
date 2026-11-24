import {matchesClubQuery} from './handler.mjs';

export function publicWebsiteUrl(value) {
 const u=new URL(value);
 if(u.protocol!=='https:' || u.username || u.password || (u.port && u.port!=='443') || u.search || u.hash)throw new Error('Use a public HTTPS club website without query parameters');
 const host=u.hostname.toLowerCase();
 if(!/^[a-z0-9.-]+$/.test(host) || !host.includes('.') || /(^|\.)(localhost|local|internal|test|invalid|example|onion)$/.test(host) || /^\d+(\.\d+)*$/.test(host))throw new Error('Public website required');
 return u;
}
export function publicAddress(ip) {
 if(ip.includes(':')) {
  const s=ip.toLowerCase();
  // Only globally routable IPv6 unicast; exclude transition/documentation ranges.
  return /^[23][0-9a-f]{0,3}:/.test(s) && !s.startsWith('2001:db8:') && !s.startsWith('2002:') && !s.startsWith('2001:0:') && !s.includes('.');
 }
 const p=ip.split('.').map(Number);if(p.length!==4 || p.some(x=>!Number.isInteger(x)||x<0||x>255))return false;
 const [a,b]=p;
 return !(a===0||a===10||a===127||a>=224||a===169&&b===254||a===172&&b>=16&&b<=31||a===192&&(b===168||b===0||b===2)||a===100&&b>=64&&b<=127||a===198&&(b===18||b===19||b===51)||a===203&&b===0);
}
export function safeWebsiteReader({fetcher=fetch,resolve}) {
 return async input=>{
  let url=publicWebsiteUrl(input);
  for(let hop=0;hop<4;hop++) {
   const ips=await resolve(url.hostname);
   if(!ips.length || !ips.every(publicAddress))throw new Error('Public website required');
   const response=await fetcher(url.href,{redirect:'manual',signal:AbortSignal.timeout(7000),headers:{Accept:'text/html,application/xhtml+xml','User-Agent':'TotalLeisure-ClubVerification/1.0'}});
   if([301,302,303,307,308].includes(response.status)) {
    const next=publicWebsiteUrl(new URL(response.headers.get('location'),url).href);
    // Do not turn a supplied website into a general redirect proxy.
    if(next.hostname.replace(/^www\./,'')!==url.hostname.replace(/^www\./,''))throw new Error('Website redirects to another organisation');
    url=next;continue;
   }
   if(!response.ok || !/text\/html|application\/xhtml\+xml/i.test(response.headers.get('content-type')||''))throw new Error('Website unavailable');
   const reader=response.body?.getReader();if(!reader)throw new Error('Empty website');
   const chunks=[];let size=0;
   try {
    while(true){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>350000)throw new Error('Website page too large');chunks.push(value);}
   } finally {await reader.cancel();}
   const all=new Uint8Array(size);let at=0;for(const c of chunks){all.set(c,at);at+=c.length;}
   return {url:url.href,html:new TextDecoder().decode(all)};
  }
  throw new Error('Too many redirects');
 };
}
export const plainText=html=>html.replace(/<(script|style|noscript)\b[^>]*>[\s\S]*?<\/\1>/gi,' ')
 .replace(/<br\s*\/?>|<\/(?:p|div|li|h[1-6])>/gi,'\n').replace(/<[^>]+>/g,' ')
 .replace(/&#(x[\da-f]+|\d+);/gi,(_,n)=>{const c=n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):parseInt(n,10);return c<=0x10ffff?String.fromCodePoint(c):'';})
 .replace(/&nbsp;/gi,' ').replace(/&amp;/gi,'&').replace(/&quot;/gi,'"').replace(/&#39;|&apos;/gi,"'")
 .split(/\n/).map(l=>l.replace(/\s+/g,' ').trim()).filter(Boolean).join('\n');

function clubName(html,query) {
 const title=plainText(html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1]||'');
 const headings=[...html.matchAll(/<h1\b[^>]*>([\s\S]*?)<\/h1>/gi)].map(m=>plainText(m[1]));
 const names=[...title.split(/\s+[|–—]\s+/),...headings].map(s=>s.trim());
 return names.find(n=>n.length<=160 && /\b(?:bowls|bowling)\b/i.test(n) && /\b(?:club|centre|center|association|academy)\b/i.test(n) && matchesClubQuery(query,n))||null;
}
function postalAddress(html,name) {
 // A contact address must explicitly belong to this club, rather than a footer
 // belonging to a hosting platform or a list of unrelated clubs.
 for(const m of html.matchAll(/<address\b[^>]*>([\s\S]*?)<\/address>/gi)) {
  const lines=plainText(m[1]).split('\n');
  const ni=lines.findIndex(l=>l.toLowerCase()===name.toLowerCase());
  if(ni<0)continue;
  const pi=lines.findIndex((l,i)=>i>ni && /\b(?:GIR\s?0AA|[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2})\b/i.test(l));
  if(pi<ni+2)continue;
  const postcode=lines[pi].match(/\b(?:GIR\s?0AA|[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2})\b/i)[0].toUpperCase().replace(/\s/g,'').replace(/(.{3})$/,' $1');
  const parts=lines.slice(ni+1,pi);if(parts.length<2 || parts.some(x=>x.length>180))continue;
  // Preserve the website's address lines, without inventing a street number or
  // borrowing a nearby club's address. The Secretary reviews these before setup.
  return {addressLine1:parts[0],addressLine2:parts.length>2?parts.slice(2).join(', '):null,townCity:parts[1],postcode,
   formattedAddress:[...parts,postcode].join(', ')};
 }
 return null;
}
export async function verifyClubWebsite({website,query,read,hash}) {
 const supplied=publicWebsiteUrl(/^[a-z][a-z0-9+.-]*:/i.test(website) ? website : 'https://'+website);
 const root=await read(supplied.origin+'/');
 const name=clubName(root.html,query);if(!name)return null;
 const pages=[root];
 // Follow only advertised contact pages on this club's own origin.
 for(const m of root.html.matchAll(/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
  if(!/\b(?:contact|find us|where we are)\b/i.test(plainText(m[2])))continue;
  let u;try{u=publicWebsiteUrl(new URL(m[1],root.url).href);}catch{continue;}
  if(u.origin!==new URL(root.url).origin || pages.some(p=>p.url===u.href))continue;
  try{pages.push(await read(u.href));}catch{/* Inaccessible pages never establish evidence. */}
  if(pages.length>=3)break;
 }
 const found=pages.map(p=>({page:p,address:postalAddress(p.html,name)})).filter(p=>p.address);
 if(!found.length)return null;
 if(new Set(found.map(p=>p.address.postcode.replace(/\s/g,''))).size>1)return null;
 const evidence=found[0];
 const websiteUrl=new URL(root.url).origin+'/';
 return {source:'website',placeId:'web_'+await hash(websiteUrl),name,...evidence.address,websiteUrl,
  evidenceUrl:evidence.page.url,googleMapsUrl:null,latitude:null,longitude:null,
  verifiedAt:new Date().toISOString()};
}
