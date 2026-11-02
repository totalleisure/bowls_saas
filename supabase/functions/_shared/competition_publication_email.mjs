// Preview/test building blocks only. No queue writes or transport calls.
export const COMPETITION_TEST_RECIPIENTS = Object.freeze([
 'wayne@totalleisure.com','wayne.s.sayers@gmail.com','wayne.streem@gmail.com',
 'wayne.sayers@telius.co.uk','wayne.sayers@icloud.com','wayne.sayers@me.com','suesayers9@gmail.com',
]);
export function requireCompetitionTestRecipients(projectRef, recipients) {
 if(projectRef !== 'egxdkaotepgfjmszxlyn') throw new Error('Competition test sending is staging-only');
 if(!Array.isArray(recipients) || recipients.length===0) throw new Error('Select test recipients');
 const values=recipients.map(x=>String(x).trim().toLowerCase());
 if(values.some(x=>!COMPETITION_TEST_RECIPIENTS.includes(x))) throw new Error('Recipient is not on the competition test allowlist');
 return [...new Set(values)];
}
export function requireCompetitionRecipients(projectRef,recipients) {
 if(projectRef==='egxdkaotepgfjmszxlyn')return requireCompetitionTestRecipients(projectRef,recipients);
 if(projectRef!=='xfjelvvfoguzukgvxchh')throw Error('Unknown competition project');
 if(!Array.isArray(recipients)||!recipients.length)throw Error('Recipients required');
 const values=recipients.map(x=>String(x).trim().toLowerCase());
 if(values.some(x=>! /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(x)))throw Error('Invalid entrant email');
 return [...new Set(values)];
}
const escape = x => String(x ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function competitionEmailDate(value) {
 if(!value)return 'Not yet set';
 const match=String(value).match(/^(\d{4})-(\d{2})-(\d{2})$/);
 if(!match)return String(value);
 const year=Number(match[1]),month=Number(match[2]),day=Number(match[3]);
 const date=new Date(Date.UTC(year,month-1,day));
 if(date.getUTCFullYear()!==year||date.getUTCMonth()!==month-1||date.getUTCDate()!==day)return 'Not yet set';
 const suffix=day%100>=11&&day%100<=13?'th':({1:'st',2:'nd',3:'rd'}[day%10]||'th');
 return `${day}${suffix} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][month-1]} ${year}`;
}
export function competitionPublicationHtml({clubName,recipientName,entries=[],contacts=[],teamContacts=[],heading='Your Club competitions',introduction='Your competition entries and match details are below. Open Competitions from the Options menu in the App for the latest draw and results.'}) {
 const boxes=entries.map(e=>`<table role="presentation" width="100%" style="border:1px solid #aabbd0;border-collapse:collapse;margin:16px 0"><tr><td style="padding:14px;background:#edf3fa"><strong>${escape(e.competitionName)}</strong><br>${escape(e.stageName)}${'<br>Play by: '+escape(competitionEmailDate(e.playBy))}</td></tr><tr><td style="padding:14px"><strong>Your entry:</strong> ${escape(e.entryName)}<br><strong>Opponent:</strong> ${escape(e.opponentName || 'To be confirmed')}<br><strong>Status:</strong> ${escape(({ready:'Please arrange this match in the App.',awaiting_opponent:'Your next opponent is not yet confirmed. Check Competitions in the App for updates.',eliminated:'Your entry has been eliminated from this competition.',winner:'Congratulations — you have won this competition.',pending_confirmation:'Your result is awaiting Admin confirmation.',progressed:'You have progressed. Check Competitions in the App for your next match.'})[e.state]||'See the App for current match details.')}</td></tr><tr><td style="padding:14px;border-top:1px solid #d7e0eb"><strong>Competition rules</strong><br>${escape(e.rules || 'See the competition in the App for current rules.').replace(/\n/g,'<br>')}</td></tr></table>`).join('');
 const contactList=people=>people.map(p=>`<li style="margin:10px 0"><strong>${escape(p.name)}</strong>${p.email ? '<br>Email: '+escape(p.email) : ''}${p.mobile ? '<br>Mobile: '+escape(p.mobile) : ''}${!p.email && !p.mobile ? '<br>Please contact the Competitions Manager for help arranging the match.' : ''}</li>`).join('');
 return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#f1f5f9;font-family:Arial,sans-serif;color:#173554"><table role="presentation" width="100%"><tr><td align="center"><table role="presentation" width="100%" style="max-width:680px;background:white"><tr><td style="padding:24px;background:#173e70;color:white"><h1 style="margin:0;font-size:24px">${escape(heading)}</h1><p>${escape(clubName)}</p></td></tr><tr><td style="padding:24px"><p>Hello ${escape(recipientName)},</p><p>${escape(introduction)}</p>${boxes}${teamContacts.length ? '<h2 style="font-size:18px">Your team contact details</h2><ul style="padding-left:20px">'+contactList(teamContacts)+'</ul>' : ''}<h2 style="font-size:18px">Opponent contact details</h2><ul style="padding-left:20px">${contactList(contacts) || '<li>No opponent contacts are available yet.</li>'}</ul></td></tr><tr><td style="padding:20px;background:#edf3fa">Total Leisure Bowls<br>Your Club. Your Way.</td></tr></table></td></tr></table></body></html>`;
}

export function assembleCompetitionEmail({clubName,profile,competitions,entries,entryMembers,rounds,matches,profiles}) {
 const mine=new Set(entryMembers.filter(x=>x.member_profile_id===profile.id).map(x=>x.entry_id));
 const entryById=new Map(entries.map(x=>[x.id,x])); const peopleById=new Map(profiles.map(x=>[x.id,x]));
 const roundById=new Map(rounds.map(x=>[x.id,x])); const contacts=new Map(); const teamContacts=new Map(); const boxes=[];
 for(const competition of competitions) {
  for(const entry of entries.filter(x=>x.competition_id===competition.id && mine.has(x.id))) {
   for(const link of entryMembers.filter(x=>x.entry_id===entry.id)) {
    const p=peopleById.get(link.member_profile_id) || (link.member_profile_id===profile.id?profile:null);
    if(p)teamContacts.set(p.id,{name:[p.first_name,p.last_name].filter(Boolean).join(' '),email:p.email_address||null,mobile:p.phone||null});
   }
   const games=matches.filter(x=>x.competition_id===competition.id && x.status!=='bye' && (x.side_a_entry_id===entry.id || x.side_b_entry_id===entry.id))
    .sort((a,b)=>(roundById.get(a.round_id)?.round_number??0)-(roundById.get(b.round_id)?.round_number??0));
   const match=games.find(x=>x.status!=='completed') ?? games.at(-1); const round=match?roundById.get(match.round_id):null;
   const opponentId=match ? (match.side_a_entry_id===entry.id?match.side_b_entry_id:match.side_a_entry_id) : null;
   const opponent=entryById.get(opponentId);
   const maxRound=Math.max(0,...rounds.filter(r=>r.competition_id===competition.id||!r.competition_id).map(r=>r.round_number||0));
   const state=match?.status==='completed' ? (match.winner_entry_id!==entry.id?'eliminated':round?.round_number===maxRound?'winner':'progressed') : match?.status==='result_pending'?'pending_confirmation':opponent?'ready':'awaiting_opponent';
   if(opponent && !['eliminated','winner'].includes(state))for(const link of entryMembers.filter(x=>x.entry_id===opponent.id)) {
    const p=peopleById.get(link.member_profile_id);if(p)contacts.set(p.id,{name:[p.first_name,p.last_name].filter(Boolean).join(' '),email:p.email_address||null,mobile:p.phone||null});
   }
   const settings=competition.settings??{};const overrides=round?.rule_overrides??{};
   const effective={...settings,...overrides};
   const rules=[effective.scoring,effective.rules,effective.woods_per_player ? 'Woods per player: '+effective.woods_per_player:null,effective.dress ? 'Dress: '+effective.dress:null];
   const time={...settings,...overrides}; if(time.time_limit_mode==='none')rules.push('No playing time limit');else if(time.time_limit_mode==='minutes')rules.push('Playing time limit: '+time.time_limit_minutes+' minutes');
   boxes.push({state,competitionName:competition.name,stageName:round?.name||'Draw not yet created',playBy:round?.play_by||null,playByLabel:competitionEmailDate(round?.play_by),entryName:entry.name,opponentName:opponent?.name||null,rules:[...new Set(rules.filter(Boolean))].join('\n')});
  }
 }
 return {clubName,recipientName:[profile.first_name,profile.last_name].filter(Boolean).join(' '),entries:boxes,contacts:[...contacts.values()],teamContacts:[...teamContacts.values()]};
}

// Frozen, competition-specific publication message. Never permits a caller-supplied destination.
export function prepareCompetitionPublicationMessage(snapshot, delivery, {projectRef='egxdkaotepgfjmszxlyn'}={}) {
 requireCompetitionRecipients(projectRef,[delivery.recipient]);
 if(snapshot.competitions?.length!==1)throw new Error('Publication must contain exactly one competition');
 const profile=snapshot.profiles.find(p=>p.id===delivery.member_profile_id);
 if(!profile || String(profile.email_address||'').trim().toLowerCase()!==delivery.recipient)throw new Error('Publication recipient does not match the frozen entrant');
 const content=assembleCompetitionEmail({...snapshot,profile});
 if(content.entries.length!==1)throw new Error('Publication must contain this player’s entry in one competition');
 const competition=snapshot.competitions[0];
 const heading=competition.name+' — draw published';
 const introduction='The draw for '+competition.name+' has been published. Your current entry and match details are below. Open Competitions in the App for the latest draw and results.';
 return {subject:heading,html:competitionPublicationHtml({...content,heading,introduction}),content};
}
