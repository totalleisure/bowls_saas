export const STAGING_URL = 'https://egxdkaotepgfjmszxlyn.supabase.co';
export const PRODUCTION_URL = 'https://xfjelvvfoguzukgvxchh.supabase.co';
export function clubSetupEnvironment(url) {
 if (url === STAGING_URL) return {staging:true,mailbox:'bowls-staging@totalleisure.com'};
 if (url === PRODUCTION_URL) return {staging:false,mailbox:'bowls@totalleisure.com'};
 throw new Error('Unknown club setup environment');
}
