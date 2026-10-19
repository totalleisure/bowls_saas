import {test} from 'node:test';
import assert from 'node:assert/strict';
import {buildEmailActionBlock} from './action_email.ts';
import {parseResponse} from '../process-email-responses/response_parser.ts';
const code='BWL-123456ABCDEF',token='RSP-'+'A'.repeat(48);
const block={version:2,response_code:code,response_token:token,actions:[{command:'ACCEPT',label:'Accept'},{command:'DECLINE',label:'Decline',style:'negative'}]};
test('only Accept and Decline use the secure replacement credential',()=>{
 const html=buildEmailActionBlock(block,'staging@example.test');
 const urls=[...html.matchAll(/href="([^"]+)"/g)].map(m=>new URL(m[1].replaceAll('&amp;','&')));
 assert.equal(urls.length,2);
 assert(!html.includes('View fixture'));
 assert(urls.every(url=>url.protocol==='mailto:'));
 for(const [i,command] of ['ACCEPT','DECLINE'].entries())assert.deepEqual(parseResponse({subject:urls[i].searchParams.get('subject')!,bodyText:urls[i].searchParams.get('body')!}),{kind:'match',command,responseCode:code,responseToken:token});
});
test('ordinary selection keeps existing two buttons',()=>assert.equal([...buildEmailActionBlock(block,'test@example.test').matchAll(/href=/g)].length,2));
