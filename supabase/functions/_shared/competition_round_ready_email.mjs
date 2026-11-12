import {assembleCompetitionEmail,competitionPublicationHtml,requireCompetitionRecipients} from './competition_publication_email.mjs';

function handicapSummary(snapshot,competition,match,profileId) {
 if(competition.settings?.handicap_mode!=='team_difference')return null;
 const ownEntry=snapshot.entryMembers.find(p=>p.member_profile_id===profileId &&
  [match.side_a_entry_id,match.side_b_entry_id].includes(p.entry_id))?.entry_id;
 const otherEntry=ownEntry===match.side_a_entry_id?match.side_b_entry_id:match.side_a_entry_id;
 const team=id=>{
  const entry=snapshot.entries.find(e=>e.id===id);
  const people=snapshot.entryMembers.filter(p=>p.entry_id===id).map(link=>{
   const person=snapshot.profiles.find(p=>p.id===link.member_profile_id);
   return {name:[person?.first_name,person?.last_name].filter(Boolean).join(' ')||'Player',
    handicap:Number.isSafeInteger(link.individual_handicap)?link.individual_handicap:null};
  });
  // Preserve the saved playing order, including Lead / Skip order.
  const order=String(entry?.name||'').toLowerCase();
  people.sort((a,b)=>{
   const index=p=>{const i=order.indexOf(p.name.toLowerCase());return i<0?Number.MAX_SAFE_INTEGER:i;};
   return index(a)-index(b);
  });
  const required=competition.settings?.players_per_entry??people.length;
  const complete=people.length>0 && people.length===required && people.every(p=>p.handicap!==null);
  return {people,total:complete?people.reduce((sum,p)=>sum+p.handicap,0):null};
 };
 const own=team(ownEntry),other=team(otherEntry);
 const known=own.total!==null && other.total!==null;
 const lines=(label,side,opponent)=>[
  label,
  ...side.people.map(p=>`${p.name} (Hcp ${p.handicap??'not recorded'})`),
  `Combined handicap: ${side.total??'not recorded'}`,
  `Starting score: ${known?Math.max(opponent.total-side.total,0):'awaiting complete handicaps'}`,
 ];
 return [...lines('Your team',own,other),'',...lines('Opponents',other,own),
  '', 'The team with the lower combined handicap receives the difference as its starting score.'].join('\n');
}

export function prepareCompetitionRoundReadyMessage(snapshot,delivery,{projectRef='egxdkaotepgfjmszxlyn'}={}) {
 requireCompetitionRecipients(projectRef,[delivery.recipient]);
 if(snapshot.competitions?.length!==1 || snapshot.matches?.length!==1)throw Error('One competition match is required');
 const match=snapshot.matches[0],competition=snapshot.competitions[0];
 if(match.id!==snapshot.matchId || match.competition_id!==competition.id ||
    match.status!=='to_be_arranged' || !match.side_a_entry_id || !match.side_b_entry_id)throw Error('The next match must be playable');
 const profile=snapshot.profiles.find(p=>p.id===delivery.member_profile_id);
 if(!profile || String(profile.email_address||'').trim().toLowerCase()!==delivery.recipient)throw Error('Recipient must match the frozen entrant');
 const content=assembleCompetitionEmail({...snapshot,profile});
 if(content.entries.length!==1 || content.entries[0].state!=='ready')throw Error('Recipient must play in this match');
 const round=snapshot.rounds.find(r=>r.id===match.round_id);
 if(!round)throw Error('Round is required');
 content.entries[0].stageName=`${round.name} ${match.match_number}`;
 const handicaps=handicapSummary(snapshot,competition,match,profile.id);
 if(handicaps)content.entries[0].handicapSummary=handicaps;
 const heading=`${competition.name} — ${round.name} ${match.match_number} ready to arrange`;
 const introduction=`Your next match in ${competition.name} is now ready to arrange. Both entries are confirmed. Your team, opponents, contact details, play-by date and playing rules are below. Open the Dashboard or My Fixture Bookings and Competitions in the App to arrange this match.`;
 return {subject:heading,html:competitionPublicationHtml({...content,heading,introduction}),content};
}
