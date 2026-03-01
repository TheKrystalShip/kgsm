import { expect } from 'chai';
import {
  flagsToType,
  flagsToAttributes,
  isInternalVariable,
  parseArrayElements,
  parseAssocElements,
  parseDeclareLine,
  parseExamineOutput,
  parseInfoVariables,
} from '../../src/parsers/variableParser';

describe('variableParser', () => {
  // -------------------------------------------------------------------------
  // flagsToType
  // -------------------------------------------------------------------------
  describe('flagsToType', () => {
    it('returns "string" for empty flags', () => {
      expect(flagsToType('')).to.equal('string');
    });

    it('returns "associative" for flag "A"', () => {
      expect(flagsToType('A')).to.equal('associative');
    });

    it('returns "array" for flag "a"', () => {
      expect(flagsToType('a')).to.equal('array');
    });

    it('returns "nameref" for flag "n"', () => {
      expect(flagsToType('n')).to.equal('nameref');
    });

    it('returns "function" for flag "f"', () => {
      expect(flagsToType('f')).to.equal('function');
    });

    it('returns "integer" for flag "i"', () => {
      expect(flagsToType('i')).to.equal('integer');
    });

    it('gives "associative" priority over other flags when "A" is present', () => {
      expect(flagsToType('Ai')).to.equal('associative');
    });

    it('gives "array" priority over "i" when "a" is present', () => {
      expect(flagsToType('ai')).to.equal('array');
    });

    it('returns "integer" when combined with "r" (readonly)', () => {
      expect(flagsToType('ir')).to.equal('integer');
    });
  });

  // -------------------------------------------------------------------------
  // flagsToAttributes
  // -------------------------------------------------------------------------
  describe('flagsToAttributes', () => {
    it('returns empty array for empty flags', () => {
      expect(flagsToAttributes('')).to.deep.equal([]);
    });

    it('includes "readonly" for flag "r"', () => {
      expect(flagsToAttributes('r')).to.include('readonly');
    });

    it('includes "exported" for flag "x"', () => {
      expect(flagsToAttributes('x')).to.include('exported');
    });

    it('includes "integer" for flag "i"', () => {
      expect(flagsToAttributes('i')).to.include('integer');
    });

    it('includes "trace" for flag "t"', () => {
      expect(flagsToAttributes('t')).to.include('trace');
    });

    it('includes "lowercase" for flag "l"', () => {
      expect(flagsToAttributes('l')).to.include('lowercase');
    });

    it('includes "uppercase" for flag "u"', () => {
      expect(flagsToAttributes('u')).to.include('uppercase');
    });

    it('includes "nameref" for flag "n"', () => {
      expect(flagsToAttributes('n')).to.include('nameref');
    });

    it('includes multiple attributes for combined flags "rx"', () => {
      const attrs = flagsToAttributes('rx');
      expect(attrs).to.include('readonly');
      expect(attrs).to.include('exported');
    });
  });

  // -------------------------------------------------------------------------
  // isInternalVariable
  // -------------------------------------------------------------------------
  describe('isInternalVariable', () => {
    it('returns true for _Dbg_ prefixed names', () => {
      expect(isInternalVariable('_Dbg_foo')).to.be.true;
    });

    it('returns true for the bare _Dbg_ prefix', () => {
      expect(isInternalVariable('_Dbg_')).to.be.true;
    });

    it('returns false for a regular variable name', () => {
      expect(isInternalVariable('myvar')).to.be.false;
    });

    it('returns false for a similar but non-matching prefix', () => {
      expect(isInternalVariable('_Dbg')).to.be.false;
    });

    it('returns false for an empty string', () => {
      expect(isInternalVariable('')).to.be.false;
    });
  });

  // -------------------------------------------------------------------------
  // parseArrayElements
  // -------------------------------------------------------------------------
  describe('parseArrayElements', () => {
    it('parses quoted array value string into child variables', () => {
      const result = parseArrayElements("'([0]=\"apple\" [1]=\"banana\")'");
      expect(result).to.have.length(2);
      expect(result[0]).to.deep.equal({ name: '[0]', value: 'apple', type: 'string', attributes: [] });
      expect(result[1]).to.deep.equal({ name: '[1]', value: 'banana', type: 'string', attributes: [] });
    });

    it('parses unquoted array value string', () => {
      const result = parseArrayElements('([0]="apple" [1]="banana")');
      expect(result).to.have.length(2);
      expect(result[0].name).to.equal('[0]');
      expect(result[1].name).to.equal('[1]');
    });

    it('returns empty array for empty array value "()"', () => {
      expect(parseArrayElements('()')).to.deep.equal([]);
    });

    it('returns empty array for quoted empty array value "\'()\'"', () => {
      expect(parseArrayElements("'()'")).to.deep.equal([]);
    });

    it('parses a three-element array', () => {
      const result = parseArrayElements('([0]="a" [1]="b" [2]="c")');
      expect(result).to.have.length(3);
      expect(result[2]).to.deep.equal({ name: '[2]', value: 'c', type: 'string', attributes: [] });
    });
  });

  // -------------------------------------------------------------------------
  // parseAssocElements
  // -------------------------------------------------------------------------
  describe('parseAssocElements', () => {
    it('parses quoted associative array value string', () => {
      const result = parseAssocElements("'([key1]=\"val1\" [key2]=\"val2\")'");
      expect(result).to.have.length(2);
      expect(result[0]).to.deep.equal({ name: '[key1]', value: 'val1', type: 'string', attributes: [] });
      expect(result[1]).to.deep.equal({ name: '[key2]', value: 'val2', type: 'string', attributes: [] });
    });

    it('parses unquoted associative array value string', () => {
      const result = parseAssocElements('([alpha]="one" [beta]="two")');
      expect(result).to.have.length(2);
      expect(result[0].name).to.equal('[alpha]');
      expect(result[0].value).to.equal('one');
    });

    it('returns empty array for empty associative array value "()"', () => {
      expect(parseAssocElements('()')).to.deep.equal([]);
    });
  });

  // -------------------------------------------------------------------------
  // parseDeclareLine
  // -------------------------------------------------------------------------
  describe('parseDeclareLine', () => {
    it('parses "declare -- name=\\"value\\"" as a plain string variable', () => {
      const result = parseDeclareLine('declare -- myvar="hello"');
      expect(result).to.deep.equal({
        name: 'myvar',
        value: 'hello',
        type: 'string',
        attributes: [],
      });
    });

    it('parses "declare -i" as integer type with integer attribute', () => {
      const result = parseDeclareLine('declare -i count="42"');
      expect(result).to.not.be.null;
      expect(result!.type).to.equal('integer');
      expect(result!.attributes).to.include('integer');
      expect(result!.value).to.equal('42');
    });

    it('parses "declare -r" as readonly attribute', () => {
      const result = parseDeclareLine('declare -r CONST="immutable"');
      expect(result).to.not.be.null;
      expect(result!.attributes).to.include('readonly');
      expect(result!.type).to.equal('string');
    });

    it('parses "declare -x" as exported attribute', () => {
      const result = parseDeclareLine('declare -x PATH="/usr/bin"');
      expect(result).to.not.be.null;
      expect(result!.attributes).to.include('exported');
      expect(result!.value).to.equal('/usr/bin');
    });

    it('parses "declare -n" as nameref type', () => {
      const result = parseDeclareLine('declare -n myref="other_var"');
      expect(result).to.not.be.null;
      expect(result!.type).to.equal('nameref');
      expect(result!.attributes).to.include('nameref');
    });

    it('parses "declare -a" as array type with children', () => {
      const result = parseDeclareLine('declare -a myarray=\'([0]="apple" [1]="banana")\'');
      expect(result).to.not.be.null;
      expect(result!.type).to.equal('array');
      expect(result!.children).to.have.length(2);
      expect(result!.children![0]).to.deep.equal({
        name: '[0]',
        value: 'apple',
        type: 'string',
        attributes: [],
      });
    });

    it('parses "declare -A" as associative type with children', () => {
      const result = parseDeclareLine('declare -A myassoc=\'([key1]="val1" [key2]="val2")\'');
      expect(result).to.not.be.null;
      expect(result!.type).to.equal('associative');
      expect(result!.children).to.have.length(2);
      expect(result!.children![0].name).to.equal('[key1]');
    });

    it('parses an empty array (no children)', () => {
      const result = parseDeclareLine("declare -a empty='()'");
      expect(result).to.not.be.null;
      expect(result!.type).to.equal('array');
      expect(result!.children).to.be.undefined;
    });

    it('parses a variable declared without a value', () => {
      const result = parseDeclareLine('declare -- novalue');
      expect(result).to.not.be.null;
      expect(result!.name).to.equal('novalue');
      expect(result!.value).to.equal('');
    });

    it('returns null for lines not starting with "declare"', () => {
      expect(parseDeclareLine('some random line')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseDeclareLine('')).to.be.null;
    });

    it('handles escaped double-quotes inside string values', () => {
      const result = parseDeclareLine('declare -- msg="say \\"hello\\""');
      expect(result).to.not.be.null;
      expect(result!.value).to.equal('say "hello"');
    });

    it('parses combined flags -ir (integer + readonly)', () => {
      const result = parseDeclareLine('declare -ir MAX="100"');
      expect(result).to.not.be.null;
      expect(result!.type).to.equal('integer');
      expect(result!.attributes).to.include('integer');
      expect(result!.attributes).to.include('readonly');
    });
  });

  // -------------------------------------------------------------------------
  // parseExamineOutput
  // -------------------------------------------------------------------------
  describe('parseExamineOutput', () => {
    it('parses a single declare line in the output', () => {
      const result = parseExamineOutput('declare -- myvar="hello"');
      expect(result).to.have.length(1);
      expect(result[0].name).to.equal('myvar');
    });

    it('parses multiple declare lines', () => {
      const output = 'declare -- foo="bar"\ndeclare -i count="42"';
      const result = parseExamineOutput(output);
      expect(result).to.have.length(2);
      expect(result[0].name).to.equal('foo');
      expect(result[1].name).to.equal('count');
    });

    it('skips error lines starting with **', () => {
      const output = [
        'declare -- myvar="hello"',
        '** Error: some problem',
        'declare -i count="42"',
      ].join('\n');
      const result = parseExamineOutput(output);
      expect(result).to.have.length(2);
    });

    it('returns empty array for empty input', () => {
      expect(parseExamineOutput('')).to.deep.equal([]);
    });

    it('returns empty array when no declare lines are present', () => {
      expect(parseExamineOutput('just some output\nno variables here')).to.deep.equal([]);
    });
  });

  // -------------------------------------------------------------------------
  // parseInfoVariables
  // -------------------------------------------------------------------------
  describe('parseInfoVariables', () => {
    it('extracts variable names from name=value lines', () => {
      const result = parseInfoVariables('FOO=bar\nBAR=baz');
      expect(result).to.include('FOO');
      expect(result).to.include('BAR');
    });

    it('filters out bashdb internal variables (_Dbg_ prefix)', () => {
      const result = parseInfoVariables('FOO=bar\n_Dbg_internal=test\nBAR=baz');
      expect(result).to.not.include('_Dbg_internal');
      expect(result).to.include('FOO');
      expect(result).to.include('BAR');
    });

    it('filters out lines with invalid identifier names', () => {
      const result = parseInfoVariables('valid_var=ok\ninvalid-name=test\n123bad=val');
      expect(result).to.include('valid_var');
      expect(result).to.not.include('invalid-name');
      expect(result).to.not.include('123bad');
    });

    it('accepts bare variable names (no =value)', () => {
      const result = parseInfoVariables('MYVAR');
      expect(result).to.include('MYVAR');
    });

    it('returns empty array for empty input', () => {
      expect(parseInfoVariables('')).to.deep.equal([]);
    });

    it('skips blank lines', () => {
      const result = parseInfoVariables('\nFOO=bar\n\nBAZ=qux\n');
      expect(result).to.deep.equal(['FOO', 'BAZ']);
    });
  });
});
