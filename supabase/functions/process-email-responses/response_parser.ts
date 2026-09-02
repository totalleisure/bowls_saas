export type ResponseMessage = {
  subject?: string;
  bodyText?: string;
};

export type ParsedResponse = {
  kind: "match";
  command: string;
  responseCode: string;
  responseToken: string | null;
};

export type ResponseParseResult =
  | ParsedResponse
  | { kind: "ambiguous" }
  | null;

const responseLinePattern =
  /^\s*(ACCEPT|DECLINE)\s+(BWL-[A-F0-9]{12})(?:\s+(RSP-[A-F0-9]{48}))?\s*$/i;

const responseSubjectPattern =
  /^\s*(?:RE:\s*)*Bowls response:\s*(ACCEPT|DECLINE)\s+(BWL-[A-F0-9]{12})(?:\s+(RSP-[A-F0-9]{48}))?\s*$/i;

function parsedMatch(match: RegExpMatchArray): ParsedResponse {
  return {
    kind: "match",
    command: match[1].toUpperCase(),
    responseCode: match[2].toUpperCase(),
    responseToken: match[3]?.toUpperCase() ?? null,
  };
}

function sameResponse(left: ParsedResponse, right: ParsedResponse): boolean {
  return left.command === right.command &&
    left.responseCode === right.responseCode &&
    left.responseToken === right.responseToken;
}

function isQuotedHistoryStart(line: string): boolean {
  return /^\s*>/.test(line) ||
    /^\s*On .+ wrote:\s*$/i.test(line) ||
    /^\s*-{2,}\s*(?:Original Message|Forwarded message)\s*-{2,}\s*$/i
      .test(line) ||
    /^\s*From:\s+.+$/i.test(line);
}

export function parseResponse(message: ResponseMessage): ResponseParseResult {
  const subjectMatch = String(message.subject ?? "").match(
    responseSubjectPattern,
  );
  const subjectResponse = subjectMatch ? parsedMatch(subjectMatch) : null;

  const authoredLines: string[] = [];
  for (const line of String(message.bodyText ?? "").split(/\r?\n/)) {
    if (isQuotedHistoryStart(line)) break;
    authoredLines.push(line);
  }

  const nonEmptyLines = authoredLines.filter((line) => line.trim().length > 0);
  if (nonEmptyLines.length === 0) return null;

  // Only the first newly authored non-empty line may authorise a response.
  // Tokens in signatures, quoted history and forwarded content are ignored.
  const firstMatch = nonEmptyLines[0].match(responseLinePattern);
  if (!firstMatch) return null;

  const bodyMatches = nonEmptyLines
    .map((line) => line.match(responseLinePattern))
    .filter((match): match is RegExpMatchArray => match !== null);

  if (bodyMatches.length !== 1) return { kind: "ambiguous" };

  const bodyResponse = parsedMatch(bodyMatches[0]);
  if (subjectResponse && !sameResponse(subjectResponse, bodyResponse)) {
    return { kind: "ambiguous" };
  }

  return bodyResponse;
}
