import test from 'node:test';
import assert from 'node:assert/strict';
import {handleRequest} from '../supabase/functions/send-graph-email/handler.ts';
test('Embedded badge retains its Content-ID and regular attachments stay unchanged',async()=>{
 const env=n=>({SUPABASE_URL:'https://example.invalid',SUPABASE_SERVICE_ROLE_KEY:'key',MS_TENANT_ID:'tenant',MS_CLIENT_ID:'client',MS_CLIENT_SECRET:'secret',MS_MAILBOX:'sender@example.org'}[n]);
 let graph;
 const req=new Request('https://example.invalid',{method:'POST',headers:{Authorization:'Bearer key'},body:JSON.stringify({to:'test@example.org',subject:'Test',html:'<img src="cid:badge">',attachments:[{name:'badge.png',contentType:'image/png',contentBytes:'YWJj',isInline:true,contentId:'badge'},{name:'guide.pdf',contentType:'application/pdf',contentBytes:'YWJj'}]})});
 const result=await handleRequest(req,env,async(url,options)=>{
 if(url.includes('reserve_'))return Response.json({allowed:true});
 if(url.includes('oauth2'))return Response.json({access_token:'token'});
 graph=JSON.parse(options.body);return new Response(null,{status:202});
 });
 assert.equal(result.status,200);
 assert.equal(graph.message.attachments[0].contentId,'badge');
 assert.equal(graph.message.attachments[0].isInline,true);
 assert.equal('contentId' in graph.message.attachments[1],false);
});
