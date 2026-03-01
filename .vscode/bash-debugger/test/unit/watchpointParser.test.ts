import { expect } from 'chai';
import {
  parseWatchpointSet,
  parseWatchpointHit,
  parseInfoWatchpoints,
  parseNoWatchpoints,
} from '../../src/parsers/watchpointParser';

describe('watchpointParser', () => {
  // -------------------------------------------------------------------------
  // parseWatchpointSet
  // -------------------------------------------------------------------------
  describe('parseWatchpointSet', () => {
    it('parses a string-equality watchpoint (arith: 0)', () => {
      expect(parseWatchpointSet(' 0: ($myvar)==hello arith: 0')).to.deep.equal({
        id: 0,
        expression: '$myvar',
        currentValue: 'hello',
        isArithmetic: false,
      });
    });

    it('parses an arithmetic watchpoint (arith: 1)', () => {
      expect(parseWatchpointSet(' 1: (x+y)==42 arith: 1')).to.deep.equal({
        id: 1,
        expression: 'x+y',
        currentValue: '42',
        isArithmetic: true,
      });
    });

    it('parses when there is no leading whitespace', () => {
      const result = parseWatchpointSet('2: ($count)==0 arith: 0');
      expect(result).to.not.be.null;
      expect(result!.id).to.equal(2);
      expect(result!.isArithmetic).to.be.false;
    });

    it('returns null for non-watchpoint text', () => {
      expect(parseWatchpointSet('some random output')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseWatchpointSet('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseWatchpointHit
  // -------------------------------------------------------------------------
  describe('parseWatchpointHit', () => {
    it('parses a three-line watchpoint hit notification', () => {
      const output = 'Watchpoint 0: ($myvar)\nOld value: hello\nNew value: world';
      expect(parseWatchpointHit(output)).to.deep.equal({
        id: 0,
        expression: '$myvar',
        oldValue: 'hello',
        newValue: 'world',
      });
    });

    it('parses a watchpoint hit with a different id and expression', () => {
      const output = 'Watchpoint 5: (counter)\nOld value: 10\nNew value: 11';
      const result = parseWatchpointHit(output);
      expect(result).to.not.be.null;
      expect(result!.id).to.equal(5);
      expect(result!.expression).to.equal('counter');
      expect(result!.oldValue).to.equal('10');
      expect(result!.newValue).to.equal('11');
    });

    it('returns null when fewer than 3 lines are provided', () => {
      expect(parseWatchpointHit('Watchpoint 0: ($myvar)\nOld value: hello')).to.be.null;
    });

    it('returns null for completely mismatched format', () => {
      expect(parseWatchpointHit('some\nrandom\nlines')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseWatchpointHit('')).to.be.null;
    });

    it('returns null when Old/New value lines are missing', () => {
      const output = 'Watchpoint 0: ($myvar)\nnot old value\nnot new value';
      expect(parseWatchpointHit(output)).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseInfoWatchpoints
  // -------------------------------------------------------------------------
  describe('parseInfoWatchpoints', () => {
    it('parses a single watchpoint with hit count', () => {
      const output = [
        'Num Type       Enb  Expression',
        '0   watchpoint yes  ($myvar)',
        '    breakpoint already hit 1 time(s).',
      ].join('\n');
      const result = parseInfoWatchpoints(output);
      expect(result).to.have.length(1);
      expect(result[0]).to.deep.equal({
        id: 0,
        enabled: true,
        expression: '$myvar',
        hitCount: 1,
      });
    });

    it('parses a disabled watchpoint', () => {
      const output = [
        'Num Type       Enb  Expression',
        '1   watchpoint no   ($flag)',
      ].join('\n');
      const result = parseInfoWatchpoints(output);
      expect(result).to.have.length(1);
      expect(result[0].enabled).to.be.false;
      expect(result[0].hitCount).to.equal(0);
    });

    it('parses multiple watchpoints', () => {
      const output = [
        'Num Type       Enb  Expression',
        '0   watchpoint yes  ($myvar)',
        '    breakpoint already hit 2 time(s).',
        '1   watchpoint no   ($other)',
      ].join('\n');
      const result = parseInfoWatchpoints(output);
      expect(result).to.have.length(2);
      expect(result[0].id).to.equal(0);
      expect(result[0].hitCount).to.equal(2);
      expect(result[1].id).to.equal(1);
      expect(result[1].enabled).to.be.false;
    });

    it('returns empty array for empty input', () => {
      expect(parseInfoWatchpoints('')).to.deep.equal([]);
    });

    it('returns empty array for header-only input', () => {
      expect(parseInfoWatchpoints('Num Type       Enb  Expression')).to.deep.equal([]);
    });

    it('defaults hitCount to 0 when no hit line is present', () => {
      const output = [
        'Num Type       Enb  Expression',
        '0   watchpoint yes  ($x)',
      ].join('\n');
      const result = parseInfoWatchpoints(output);
      expect(result[0].hitCount).to.equal(0);
    });
  });

  // -------------------------------------------------------------------------
  // parseNoWatchpoints
  // -------------------------------------------------------------------------
  describe('parseNoWatchpoints', () => {
    it('returns true for the "no watch expressions" message', () => {
      expect(parseNoWatchpoints('No watch expressions have been set.')).to.be.true;
    });

    it('returns true when the message appears within a larger string', () => {
      expect(
        parseNoWatchpoints('bashdb output:\nNo watch expressions have been set.\n'),
      ).to.be.true;
    });

    it('returns false for other text', () => {
      expect(parseNoWatchpoints('some other output')).to.be.false;
    });

    it('returns false for empty string', () => {
      expect(parseNoWatchpoints('')).to.be.false;
    });
  });
});
