import {assembleCompetitionEmail,competitionPublicationHtml,requireCompetitionRecipients} from './competition_publication_email.mjs';

export function prepareCompetitionAmendmentMessage(snapshot,delivery,{projectRef='egxdkaotepgfjmszxlyn'}={}) {
 requireCompetitionRecipients(projectRef,[delivery.recipient]);
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
