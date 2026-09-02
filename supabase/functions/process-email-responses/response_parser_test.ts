import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseResponse } from "./response_parser.ts";

const code = "BWL-3304DABC4A08";
const token = `RSP-${"A".repeat(48)}`;

Deno.test("parses one explicit v2 response", () => {
  assertEquals(
    parseResponse({
      subject: `Bowls response: ACCEPT ${code} ${token}`,
      bodyText: `ACCEPT ${code} ${token}`,
    }),
    {
      kind: "match",
      command: "ACCEPT",
      responseCode: code,
      responseToken: token,
    },
  );
});

Deno.test("parses one explicit legacy response", () => {
  assertEquals(
    parseResponse({ bodyText: `DECLINE ${code}` }),
    {
      kind: "match",
      command: "DECLINE",
      responseCode: code,
      responseToken: null,
    },
  );
});

Deno.test("ignores a token found only in quoted history", () => {
  assertEquals(
    parseResponse({
      subject: "Fwd: Team selection",
      bodyText:
        `Please review this.\n\n-----Forwarded message-----\nACCEPT ${code} ${token}`,
    }),
    null,
  );
});

Deno.test("ignores a command-shaped subject without a new body command", () => {
  assertEquals(
    parseResponse({
      subject: `RE: Bowls response: ACCEPT ${code} ${token}`,
      bodyText: `Thanks\n\nOn Tuesday, Bowls wrote:\nACCEPT ${code} ${token}`,
    }),
    null,
  );
});

Deno.test("rejects multiple newly authored response commands", () => {
  assertEquals(
    parseResponse({
      bodyText: `ACCEPT ${code} ${token}\nDECLINE ${code} ${token}`,
    }),
    { kind: "ambiguous" },
  );
});

Deno.test("rejects disagreement between subject and body", () => {
  assertEquals(
    parseResponse({
      subject: `Bowls response: DECLINE ${code} ${token}`,
      bodyText: `ACCEPT ${code} ${token}`,
    }),
    { kind: "ambiguous" },
  );
});

Deno.test("requires the command to be the first authored non-empty line", () => {
  assertEquals(
    parseResponse({
      bodyText: `Hello bowls\nACCEPT ${code} ${token}`,
    }),
    null,
  );
});
