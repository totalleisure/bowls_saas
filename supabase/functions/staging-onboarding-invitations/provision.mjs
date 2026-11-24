// Account creation is an explicit invitation action, never an onboarding preview side effect.
export async function provisionContact(admin, contactId, callerId, clubId) {
  const context = await admin.rpc('staging_invitation_contact_context', {p_contact:contactId,p_caller:callerId});
  if(context.error || !context.data || context.data.club_id!==clubId) throw new Error('Contact needs administrator review');
  let userId=context.data.user_id;
  if(!userId) {
    const created=await admin.auth.admin.createUser({
      email:context.data.email,email_confirm:true,
      app_metadata:{staging_onboarding_contact_id:contactId},
      user_metadata:{display_name:`${context.data.first_name} ${context.data.last_name}`},
    });
    userId=created.data?.user?.id;
    if(created.error || !userId) {
      // A competing request may have created this same identity. Never create a second account.
      const retry=await admin.rpc('staging_invitation_contact_context',{p_contact:contactId,p_caller:callerId});
      if(retry.error || !retry.data?.user_id) throw new Error('Sign-in account could not be prepared; review before retrying');
      userId=retry.data.user_id;
    }
  }
  const finished=await admin.rpc('finish_staging_invitation_contact',{p_contact:contactId,p_caller:callerId,p_user:userId});
  if(finished.error) throw new Error('Account prepared but invitation needs review; do not create another account');
  return finished.data;
}
