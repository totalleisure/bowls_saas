function normalizeHeader(value: string): string {
  return value
    .replace(/^\uFEFF/, "") // strip UTF-8 BOM
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_");
}

export function parseCsv(text: string): Record<string, string>[] {
  const records: { cells: string[]; line: number }[] = [];
  let cells: string[] = [], field = "", quoted = false, line = 1, startLine = 1;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') { field += '"'; i++; }
      else { quoted = !quoted; }
    } else if (c === "," && !quoted) {
      cells.push(field); field = "";
    } else if ((c === "\n" || c === "\r") && !quoted) {
      cells.push(field);
      if (cells.some((v) => v.trim())) records.push({ cells, line: startLine });
      cells = []; field = "";
      if (c === "\r" && text[i + 1] === "\n") i++;
      line++; startLine = line;
    } else {
      field += c;
      if (c === "\n") line++;
    }
  }
  if (quoted) throw new Error("CSV has an unterminated quoted field");
  cells.push(field);
  if (cells.some((v) => v.trim())) records.push({ cells, line: startLine });
  if (!records.length) return [];
  const headers = records.shift()!.cells.map(normalizeHeader);
  if (new Set(headers).size !== headers.length) throw new Error("CSV has duplicate headers");
  return records.map(({ cells, line }) => {
    if (cells.length !== headers.length) throw new Error(`CSV row ${line}: incorrect number of columns`);
    const row: Record<string, string> = { _row: String(line) };
    headers.forEach((h, i) => { row[h] = cells[i].trim(); });
    return row;
  });
}

