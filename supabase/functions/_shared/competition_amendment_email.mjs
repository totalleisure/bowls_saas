import {assembleCompetitionEmail,competitionPublicationHtml,requireCompetitionRecipients} from './competition_publication_email.mjs';
import {competitionHandicapSummary} from './competition_round_ready_email.mjs';

function replacementMessage(snapshot,delivery) {
 const competition=snapshot.competitions?.[0],change=snapshot.playerReplacement;
 if(snapshot.competitions?.length!==1 || !snapshot.amendment || !change?.entryId ||
   !snapshot.entries?.some(e=>e.id===change.entryId && e.competition_id===competition.id) ||
   !snapshot.matches?.length || snapshot.matches.some(m=>m.competition_id!==competition.id))throw Error('Invalid player replacement');
 const profile=snapshot.profiles.find(p=>p.id===delivery.member_profile_id);
 if(!profile || String(profile.email_address||'').trim().toLowerCase()!==delivery.recipient)throw Error('Recipient must match frozen entrant');
 const removed=profile.id===change.outgoingId;
 const content=removed?{clubName:snapshot.clubName,recipientName:[profile.first_name,profile.last_name].filter(Boolean).join(' '),entries:[],contacts:[],teamContacts:[]}:
   assembleCompetitionEmail({...snapshot,profile});
 if(!removed && content.entries.length!==1)throw Error('Only affected entrants receive replacements');
 if(!removed){
  const own=snapshot.entryMembers.find(e=>e.member_profile_id===profile.id)?.entry_id;
  const match=snapshot.matches.find(m=>m.status==='to_be_arranged' && m.side_a_entry_id && m.side_b_entry_id && [m.side_a_entry_id,m.side_b_entry_id].includes(own));
  if(match){const h=competitionHandicapSummary(snapshot,competition,match,profile.id);if(h)content.entries[0].handicapSummary=h;if(match.fixture_id)content.entries[0].state='arranged';}
 }
 const heading=`${competition.name} — ${removed?'entry correction':'player corrected'}`;
 const introduction=removed?
  `An Admin has corrected the entry ${change.entryName}. You are no longer listed in this competition entry. Please disregard earlier match and booking details for it. If this is unexpected, contact the Competition Secretary.`:
  `An Admin has corrected a player in ${competition.name}: ${change.oldName} has been replaced by ${change.newName}. The corrected entry is ${change.entryName}. The draw position has not changed. Please use the revised player and contact details below instead of earlier emails. Any existing booking retains its date, time and rink; revised booking details are sent separately.`;
 return {subject:heading,html:competitionPublicationHtml({...content,heading,introduction}),content};
}

export function prepareCompetitionAmendmentMessage(snapshot,delivery,{projectRef='egxdkaotepgfjmszxlyn'}={}) {
 requireCompetitionRecipients(projectRef,[delivery.recipient]);
 if(snapshot.playerReplacement)return replacementMessage(snapshot,delivery);
 if(!snapshot.amendment || snapshot.competitions?.length!==1 || snapshot.matches?.length!==2)throw Error('A draw amendment is required');
 const competition=snapshot.competitions[0];
 const match=snapshot.matches.find(m=>m.id===snapshot.matchId);
 const target=snapshot.matches.find(m=>m.side_a_source_id===match?.id || m.side_b_source_id===match?.id);
 if(!match || !target || match.competition_id!==competition.id || target.competition_id!==competition.id ||
   !match.side_a_entry_id || !match.side_b_entry_id || match.status!=='to_be_arranged')throw Error('Invalid amended draw');
 const profile=snapshot.profiles.find(p=>p.id===delivery.member_profile_id);
 if(!profile || String(profile.email_address||'').trim().toLowerCase()!==delivery.recipient)throw Error('Recipient must match frozen entrant');
 const content=assembleCompetitionEmail({...snapshot,profile});
 if(content.entries.length!==1)throw Error('Only affected entrants receive amendments');
 const round=snapshot.rounds.find(r=>r.id===match.round_id);
 if(!round)throw Error('Preliminary round is required');
 const challenger=snapshot.entries.find(e=>e.id===snapshot.challengerEntryId);
 const heading=`${competition.name} — draw amended`;
 const introduction=`A preliminary match has been added: ${snapshot.entries.find(e=>e.id===match.side_a_entry_id)?.name} versus ${snapshot.entries.find(e=>e.id===match.side_b_entry_id)?.name}. ${challenger?.name} are the challengers. The winner will take the existing place in ${snapshot.targetReference}. Your affected entry, contact details, play-by date and rules are below. Please use these revised details instead of the earlier draw email.`;
 return {subject:heading,html:competitionPublicationHtml({...content,heading,introduction}),content};
}
