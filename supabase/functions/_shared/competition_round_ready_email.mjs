import {assembleCompetitionEmail,competitionPublicationHtml,requireCompetitionRecipients} from './competition_publication_email.mjs';

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
 const heading=`${competition.name} — ${round.name} ${match.match_number} ready to arrange`;
 const introduction=`Your next match in ${competition.name} is now ready to arrange. Both entries are confirmed. Your team, opponents, contact details, play-by date and playing rules are below. Open the Dashboard or My Fixture Bookings and Competitions in the App to arrange this match.`;
 return {subject:heading,html:competitionPublicationHtml({...content,heading,introduction}),content};
}
