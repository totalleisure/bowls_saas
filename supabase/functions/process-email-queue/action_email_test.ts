import {test} from 'node:test';
import assert from 'node:assert/strict';
import {buildEmailActionBlock} from './action_email.ts';
import {parseResponse} from '../process-email-responses/response_parser.ts';
const code='BWL-123456ABCDEF',token='RSP-'+'A'.repeat(48);
const block={version:2,response_code:code,response_token:token,actions:[{command:'ACCEPT',label:'Accept'},{command:'DECLINE',label:'Decline',style:'negative'}]};
test('all three buttons use the same secure replacement credential',()=>{
 const html=buildEmailActionBlock(block,'staging@example.test','https://staging.example.test/functions/v1/view-email-fixture');
 const urls=[...html.matchAll(/href="([^"]+)"/g)].map(m=>new URL(m[1].replaceAll('&amp;','&')));
 assert.equal(urls.length,3);
 for(const [i,command] of ['ACCEPT','DECLINE'].entries())assert.deepEqual(parseResponse({subject:urls[i].searchParams.get('subject')!,bodyText:urls[i].searchParams.get('body')!}),{kind:'match',command,responseCode:code,responseToken:token});
 assert.equal(urls[2].hostname,'staging.example.test');assert.equal(urls[2].searchParams.get('code'),code);assert.equal(urls[2].searchParams.get('token'),token);
});
test('ordinary selection keeps existing two buttons',()=>assert.equal([...buildEmailActionBlock(block,'test@example.test').matchAll(/href=/g)].length,2));
