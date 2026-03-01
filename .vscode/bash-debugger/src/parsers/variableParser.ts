import { BashdbVariable, BashVariableType, BashVariableAttribute } from '../types';

/**
 * Map declare flags string to BashVariableType.
 * Primary type flags checked in priority order: A > a > n > f > i
 */
export function flagsToType(flags: string): BashVariableType {
  if (flags.includes('A')) { return 'associative'; }
  if (flags.includes('a')) { return 'array'; }
  if (flags.includes('n')) { return 'nameref'; }
  if (flags.includes('f')) { return 'function'; }
  if (flags.includes('i')) { return 'integer'; }
  return 'string';
}

/**
 * Map declare flags string to attribute list.
 */
export function flagsToAttributes(flags: string): BashVariableAttribute[] {
  const attrs: BashVariableAttribute[] = [];
  if (flags.includes('r')) { attrs.push('readonly'); }
  if (flags.includes('x')) { attrs.push('exported'); }
  if (flags.includes('i')) { attrs.push('integer'); }
  if (flags.includes('t')) { attrs.push('trace'); }
  if (flags.includes('l')) { attrs.push('lowercase'); }
  if (flags.includes('u')) { attrs.push('uppercase'); }
  if (flags.includes('n')) { attrs.push('nameref'); }
  return attrs;
}

/**
 * Check if a variable name is a bashdb internal variable.
 * Only filters _Dbg_ prefixed variables.
 */
export function isInternalVariable(name: string): boolean {
  return name.startsWith('_Dbg_');
}

/**
 * Parse indexed array value string into child BashdbVariable entries.
 * Input: '([0]="apple" [1]="banana" [2]="cherry")'
 */
export function parseArrayElements(arrayValue: string): BashdbVariable[] {
  // Strip surrounding '( ... )' or ( ... )
  const inner = arrayValue.replace(/^'?\(|\)'?$/g, '').trim();
  if (!inner) { return []; }
  return extractKeyValuePairs(inner);
}

/**
 * Parse associative array value string into child BashdbVariable entries.
 * Input: '([key1]="val1" [key2]="val2")'
 */
export function parseAssocElements(assocValue: string): BashdbVariable[] {
  const inner = assocValue.replace(/^'?\(|\)'?$/g, '').trim();
  if (!inner) { return []; }
  return extractKeyValuePairs(inner);
}

/**
 * Extract [key]="value" pairs from the inner content of an array declaration.
 * Handles values with spaces, escaped quotes, and empty values.
 */
function extractKeyValuePairs(inner: string): BashdbVariable[] {
  const results: BashdbVariable[] = [];
  // Match [key]="value" where value may contain escaped quotes and spaces
  const pattern = /\[([^\]]+)\]="((?:[^"\\]|\\.)*)"/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(inner)) !== null) {
    const key = match[1];
    const val = match[2].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
    results.push({
      name: `[${key}]`,
      value: val,
      type: 'string',
      attributes: [],
    });
  }
  return results;
}

/**
 * Parse a single `declare` line from bashdb `examine`/`typeset -p` output.
 * Returns a BashdbVariable or null if the line can't be parsed.
 */
export function parseDeclareLine(line: string): BashdbVariable | null {
  const trimmed = line.trim();
  if (!trimmed.startsWith('declare')) { return null; }

  // Match: declare [-FLAGS|--] name[="value"] or declare [-FLAGS|--] name='(array)'
  // flags group: captures flag chars or '--'
  const declareRe = /^declare\s+(-{1,2}[a-zA-Z]*)\s+([A-Za-z_][A-Za-z0-9_]*)(?:=(.*))?$/;
  const match = declareRe.exec(trimmed);
  if (!match) { return null; }

  const flagsRaw = match[1]; // e.g. "-ir", "--", "-a"
  const name = match[2];
  const valueRaw = match[3]; // may be undefined (no value), or '"..."', or "'(...)'"

  const flags = flagsRaw === '--' ? '' : flagsRaw.replace(/^-/, '');
  const type = flagsToType(flags);
  const attributes = flagsToAttributes(flags);

  let value = '';
  let children: BashdbVariable[] | undefined;

  if (valueRaw !== undefined) {
    if (type === 'array' || type === 'associative') {
      // Array value: '([0]="a" [1]="b")' — strip outer single quotes if present
      value = valueRaw;
      const elements = type === 'array'
        ? parseArrayElements(valueRaw)
        : parseAssocElements(valueRaw);
      if (elements.length > 0) { children = elements; }
    } else {
      // Quoted string value: "hello world" — strip outer double quotes
      if (valueRaw.startsWith('"') && valueRaw.endsWith('"')) {
        value = valueRaw.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, '\\');
      } else {
        value = valueRaw;
      }
    }
  }

  const variable: BashdbVariable = { name, value, type, attributes };
  if (children !== undefined) { variable.children = children; }
  return variable;
}

/**
 * Parse multi-line `examine` output that may contain multiple declare lines.
 * Returns all parsed variables.
 */
export function parseExamineOutput(output: string): BashdbVariable[] {
  const results: BashdbVariable[] = [];
  for (const line of output.split('\n')) {
    if (line.trim().startsWith('**')) { continue; } // skip error lines
    const v = parseDeclareLine(line);
    if (v) { results.push(v); }
  }
  return results;
}

/**
 * Parse the output of `info variables` to extract variable names.
 * Filters out bashdb internal variables (_Dbg_* prefix).
 * Returns list of variable names.
 */
export function parseInfoVariables(output: string): string[] {
  const names: string[] = [];
  for (const line of output.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) { continue; }
    // Accept "NAME=value" or bare "NAME"
    const eqIdx = trimmed.indexOf('=');
    const name = eqIdx !== -1 ? trimmed.slice(0, eqIdx) : trimmed;
    // Variable names must be valid identifiers
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) { continue; }
    if (isInternalVariable(name)) { continue; }
    names.push(name);
  }
  return names;
}
