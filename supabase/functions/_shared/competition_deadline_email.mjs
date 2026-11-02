import {assembleCompetitionEmail,competitionPublicationHtml,competitionEmailDate,requireCompetitionRecipients} from './competition_publication_email.mjs';
export function prepareCompetitionDeadlineMessage(snapshot,delivery,{projectRef='egxdkaotepgfjmszxlyn'}={}) {
 requireCompetitionRecipients(projectRef,[delivery.recipient]);
 if(snapshot.competitions?.length!==1 || snapshot.matches?.length!==1 || snapshot.oldDeadline===snapshot.newDeadline)throw Error('A changed deadline for one match is required');
 const match=snapshot.matches[0],competition=snapshot.competitions[0];
 if(match.id!==snapshot.matchId || match.competition_id!==competition.id || ['completed','bye'].includes(match.status))throw Error('Only unfinished matches receive deadline updates');
 const profile=snapshot.profiles.find(p=>p.id===delivery.member_profile_id);
 if(!profile || String(profile.email_address||'').trim().toLowerCase()!==delivery.recipient)throw Error('Recipient must match frozen entrant');
 const content=assembleCompetitionEmail({...snapshot,profile});
 if(content.entries.length!==1)throw Error('Only affected entrants receive deadline updates');
 const round=snapshot.rounds.find(r=>r.id===match.round_id);
 if(!round || round.play_by!==snapshot.newDeadline)throw Error('Deadline must match saved round');
 content.entries[0].stageName=`${round.name} ${match.match_number}`;
 const heading=`${competition.name} — ${round.name} play-by date changed`;
 const introduction=`The play-by date for your ${round.name} match has changed. Previous play-by date: ${competitionEmailDate(snapshot.oldDeadline)}. New play-by date: ${competitionEmailDate(snapshot.newDeadline)}. Your match details and rules are below. This does not change any fixture booking already arranged; please review your booking and contact the Competitions Manager if needed.`;
 return {subject:heading,html:competitionPublicationHtml({...content,heading,introduction}),content};
}
