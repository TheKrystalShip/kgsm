import { expect } from 'chai';
import {
  parseInfoBreakpoints,
  parseConditionError,
  parseDeleteConfirmation,
  parseDeleteError,
  parseActionSet,
  parseFunctionBreakpointError,
} from '../../src/parsers/breakpointParser';

describe('breakpointParser', () => {
  // -------------------------------------------------------------------------
  // parseInfoBreakpoints
  // -------------------------------------------------------------------------
  describe('parseInfoBreakpoints', () => {
    it('parses a single enabled breakpoint', () => {
      const output = 'Num Type       Disp Enb What\n  1 breakpoint keep y   /path/script.sh:10';
      const result = parseInfoBreakpoints(output);
      expect(result).to.have.length(1);
      expect(result[0]).to.deep.equal({
        id: 1,
        enabled: true,
        file: '/path/script.sh',
        line: 10,
        verified: true,
      });
    });

    it('parses a single disabled breakpoint', () => {
      const output = 'Num Type       Disp Enb What\n  2 breakpoint keep n   /other/script.sh:20';
      const result = parseInfoBreakpoints(output);
      expect(result).to.have.length(1);
      expect(result[0].enabled).to.be.false;
      expect(result[0].id).to.equal(2);
    });

    it('parses multiple breakpoints', () => {
      const output = [
        'Num Type       Disp Enb What',
        '  1 breakpoint keep y   /path/script.sh:10',
        '  2 breakpoint keep n   /other/script.sh:20',
      ].join('\n');
      const result = parseInfoBreakpoints(output);
      expect(result).to.have.length(2);
      expect(result[0].id).to.equal(1);
      expect(result[1].id).to.equal(2);
      expect(result[1].enabled).to.be.false;
      expect(result[1].line).to.equal(20);
    });

    it('parses condition line attached to a breakpoint', () => {
      const output = [
        'Num Type       Disp Enb What',
        '  1 breakpoint keep y   /path/script.sh:10',
        '        stop only if (x > 5)',
      ].join('\n');
      const result = parseInfoBreakpoints(output);
      expect(result).to.have.length(1);
      expect(result[0].condition).to.equal('(x > 5)');
    });

    it('parses hit count line attached to a breakpoint', () => {
      const output = [
        'Num Type       Disp Enb What',
        '  1 breakpoint keep y   /path/script.sh:10',
        '        breakpoint already hit 3 times',
      ].join('\n');
      const result = parseInfoBreakpoints(output);
      expect(result).to.have.length(1);
      expect(result[0].hitCount).to.equal(3);
    });

    it('parses both condition and hit count on the same breakpoint', () => {
      const output = [
        'Num Type       Disp Enb What',
        '  1 breakpoint keep y   /path/script.sh:10',
        '        stop only if count > 0',
        '        breakpoint already hit 1 time',
      ].join('\n');
      const result = parseInfoBreakpoints(output);
      expect(result).to.have.length(1);
      expect(result[0].condition).to.equal('count > 0');
      expect(result[0].hitCount).to.equal(1);
    });

    it('returns empty array for empty input', () => {
      expect(parseInfoBreakpoints('')).to.deep.equal([]);
    });

    it('returns empty array for header-only input', () => {
      expect(parseInfoBreakpoints('Num Type       Disp Enb What')).to.deep.equal([]);
    });
  });

  // -------------------------------------------------------------------------
  // parseConditionError
  // -------------------------------------------------------------------------
  describe('parseConditionError', () => {
    it('parses a condition error message', () => {
      const result = parseConditionError(
        '** Error: condition: Breakpoint number 99 out of range.',
      );
      expect(result).to.equal('Breakpoint number 99 out of range.');
    });

    it('returns null for success output (no error)', () => {
      expect(parseConditionError('condition set')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseConditionError('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseDeleteConfirmation
  // -------------------------------------------------------------------------
  describe('parseDeleteConfirmation', () => {
    it('parses "Deleted breakpoint N." and returns N', () => {
      expect(parseDeleteConfirmation('Deleted breakpoint 1.')).to.equal(1);
    });

    it('parses "Deleted action N." and returns N', () => {
      expect(parseDeleteConfirmation('Deleted action 3.')).to.equal(3);
    });

    it('returns null for non-delete text', () => {
      expect(parseDeleteConfirmation('some other output')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseDeleteConfirmation('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseDeleteError
  // -------------------------------------------------------------------------
  describe('parseDeleteError', () => {
    it('parses a delete error message', () => {
      const result = parseDeleteError('** Error: delete: No breakpoint number 99.');
      expect(result).to.equal('No breakpoint number 99.');
    });

    it('returns null for success output (no error)', () => {
      expect(parseDeleteError('Deleted breakpoint 1.')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseDeleteError('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseActionSet
  // -------------------------------------------------------------------------
  describe('parseActionSet', () => {
    it('parses an action-set confirmation', () => {
      const result = parseActionSet('Action 1 set in file /path/script.sh, line 10.');
      expect(result).to.deep.equal({ id: 1, file: '/path/script.sh', line: 10 });
    });

    it('parses an action-set confirmation with a high id', () => {
      const result = parseActionSet('Action 99 set in file script.sh, line 5.');
      expect(result).to.deep.equal({ id: 99, file: 'script.sh', line: 5 });
    });

    it('returns null for non-action text', () => {
      expect(parseActionSet('some random output')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseActionSet('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseFunctionBreakpointError
  // -------------------------------------------------------------------------
  describe('parseFunctionBreakpointError', () => {
    it('parses a function-not-found breakpoint error', () => {
      const result = parseFunctionBreakpointError(
        "** Error: break: Function 'nonexistent' not found.",
      );
      expect(result).to.equal("Function 'nonexistent' not found.");
    });

    it('returns null for success output (no error)', () => {
      expect(parseFunctionBreakpointError('Breakpoint 1 set in file /path/script.sh, line 5.')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseFunctionBreakpointError('')).to.be.null;
    });
  });
});
