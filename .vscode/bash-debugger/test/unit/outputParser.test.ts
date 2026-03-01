import { expect } from 'chai';
import {
  stripAnsi,
  parsePosition,
  parsePrompt,
  parseTerminated,
  parseSignal,
  parseBreakpointSet,
  parseBreakpointHit,
  parseSentinel,
  extractSentinelContent,
  parseError,
} from '../../src/parsers/outputParser';

describe('outputParser', () => {
  // -------------------------------------------------------------------------
  // stripAnsi
  // -------------------------------------------------------------------------
  describe('stripAnsi', () => {
    it('strips color escape codes', () => {
      expect(stripAnsi('\x1B[31mred\x1B[0m')).to.equal('red');
    });

    it('strips bold escape codes', () => {
      expect(stripAnsi('\x1B[1mbold\x1B[0m')).to.equal('bold');
    });

    it('returns plain text unchanged', () => {
      expect(stripAnsi('hello world')).to.equal('hello world');
    });

    it('handles empty string', () => {
      expect(stripAnsi('')).to.equal('');
    });

    it('strips multiple sequences in one string', () => {
      expect(stripAnsi('\x1B[32mgreen\x1B[0m and \x1B[34mblue\x1B[0m')).to.equal('green and blue');
    });
  });

  // -------------------------------------------------------------------------
  // parsePosition
  // -------------------------------------------------------------------------
  describe('parsePosition', () => {
    it('parses a simple file:line position', () => {
      expect(parsePosition('(/path/to/file.sh:42):')).to.deep.equal({
        file: '/path/to/file.sh',
        line: 42,
      });
    });

    it('handles spaces in the file path', () => {
      expect(parsePosition('(/home/user/my script.sh:10):')).to.deep.equal({
        file: '/home/user/my script.sh',
        line: 10,
      });
    });

    it('parses a relative path', () => {
      expect(parsePosition('(script.sh:1):')).to.deep.equal({
        file: 'script.sh',
        line: 1,
      });
    });

    it('returns null for a non-position line', () => {
      expect(parsePosition('some random output')).to.be.null;
    });

    it('returns null for an empty string', () => {
      expect(parsePosition('')).to.be.null;
    });

    it('parses position embedded in a longer line', () => {
      const result = parsePosition('Stopped at (/tmp/test.sh:5): echo hi');
      expect(result).to.deep.equal({ file: '/tmp/test.sh', line: 5 });
    });
  });

  // -------------------------------------------------------------------------
  // parsePrompt
  // -------------------------------------------------------------------------
  describe('parsePrompt', () => {
    it('parses a simple prompt with command number 1', () => {
      expect(parsePrompt('bashdb<1> ')).to.equal(1);
    });

    it('parses a prompt with a larger command number', () => {
      expect(parsePrompt('bashdb<42> ')).to.equal(42);
    });

    it('parses a subshell prompt (double angle bracket)', () => {
      expect(parsePrompt('bashdb<<2> ')).to.equal(2);
    });

    it('returns null for regular text', () => {
      expect(parsePrompt('some output line')).to.be.null;
    });

    it('returns null for an empty string', () => {
      expect(parsePrompt('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseTerminated
  // -------------------------------------------------------------------------
  describe('parseTerminated', () => {
    it('returns "exited normally" for normal termination', () => {
      expect(parseTerminated('Debugged program terminated normally.')).to.equal('exited normally');
    });

    it('returns exit code reason for non-zero exit code', () => {
      expect(parseTerminated('Debugged program terminated with code 8. Use q to quit or R to restart.')).to.equal(
        'exited with code 8',
      );
    });

    it('returns exit code reason for code 1', () => {
      expect(parseTerminated('Debugged program terminated with code 1.')).to.equal(
        'exited with code 1',
      );
    });

    it('returns signal reason for signal-based termination', () => {
      expect(parseTerminated('Program terminated with signal SIGKILL')).to.equal(
        'terminated by signal SIGKILL',
      );
    });

    it('returns "program finished (will restart)" for restart message', () => {
      expect(parseTerminated('The program finished and will be restarted')).to.equal(
        'program finished (will restart)',
      );
    });

    it('returns null for non-termination text', () => {
      expect(parseTerminated('Stepping over line 10')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseTerminated('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseSignal
  // -------------------------------------------------------------------------
  describe('parseSignal', () => {
    it('parses SIGINT signal line', () => {
      expect(parseSignal('Program received signal SIGINT, Interrupt.')).to.deep.equal({
        signal: 'SIGINT',
        description: 'Interrupt',
      });
    });

    it('parses SIGTERM signal line', () => {
      expect(parseSignal('Program received signal SIGTERM, Terminated.')).to.deep.equal({
        signal: 'SIGTERM',
        description: 'Terminated',
      });
    });

    it('returns null for non-signal text', () => {
      expect(parseSignal('some other output')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseSignal('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseBreakpointSet
  // -------------------------------------------------------------------------
  describe('parseBreakpointSet', () => {
    it('parses a breakpoint-set confirmation with absolute path', () => {
      expect(parseBreakpointSet('Breakpoint 1 set in file /path/script.sh, line 10.')).to.deep.equal({
        id: 1,
        file: '/path/script.sh',
        line: 10,
      });
    });

    it('parses a breakpoint-set confirmation with high id and relative file', () => {
      expect(parseBreakpointSet('Breakpoint 42 set in file script.sh, line 1.')).to.deep.equal({
        id: 42,
        file: 'script.sh',
        line: 1,
      });
    });

    it('returns null for non-breakpoint text', () => {
      expect(parseBreakpointSet('some random output')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseBreakpointSet('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseBreakpointHit
  // -------------------------------------------------------------------------
  describe('parseBreakpointHit', () => {
    it('parses a simple hit with no count', () => {
      expect(parseBreakpointHit('Breakpoint 1 hit.')).to.deep.equal({ id: 1 });
    });

    it('parses a hit with plural times count', () => {
      expect(parseBreakpointHit('Breakpoint 3 hit (5 times).')).to.deep.equal({
        id: 3,
        hitCount: 5,
      });
    });

    it('parses a hit with singular "time"', () => {
      expect(parseBreakpointHit('Breakpoint 1 hit (1 time).')).to.deep.equal({
        id: 1,
        hitCount: 1,
      });
    });

    it('returns null for non-hit text', () => {
      expect(parseBreakpointHit('some other output')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseBreakpointHit('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // parseSentinel
  // -------------------------------------------------------------------------
  describe('parseSentinel', () => {
    it('parses a CMD_START sentinel', () => {
      expect(parseSentinel('<<CMD_START:abc-123>>')).to.deep.equal({
        type: 'start',
        commandId: 'abc-123',
      });
    });

    it('parses a CMD_END sentinel', () => {
      expect(parseSentinel('<<CMD_END:abc-123>>')).to.deep.equal({
        type: 'end',
        commandId: 'abc-123',
      });
    });

    it('returns null for non-sentinel text', () => {
      expect(parseSentinel('some regular output')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseSentinel('')).to.be.null;
    });
  });

  // -------------------------------------------------------------------------
  // extractSentinelContent
  // -------------------------------------------------------------------------
  describe('extractSentinelContent', () => {
    it('extracts content between matching markers', () => {
      const output = '<<CMD_START:abc-123>>\nresult line\n<<CMD_END:abc-123>>';
      const content = extractSentinelContent(output, 'abc-123');
      expect(content).to.include('result line');
    });

    it('returns null when markers are not found', () => {
      expect(extractSentinelContent('some other text', 'abc-123')).to.be.null;
    });

    it('handles multi-line content between markers', () => {
      const output = '<<CMD_START:cmd-1>>\nfirst\nsecond\nthird\n<<CMD_END:cmd-1>>';
      const content = extractSentinelContent(output, 'cmd-1');
      expect(content).to.include('first');
      expect(content).to.include('second');
      expect(content).to.include('third');
    });

    it('returns null when only the start marker is present', () => {
      const output = '<<CMD_START:cmd-1>>\nsome output';
      expect(extractSentinelContent(output, 'cmd-1')).to.be.null;
    });

    it('does not mix up content from a different command id', () => {
      const output =
        '<<CMD_START:cmd-A>>\ncontent-A\n<<CMD_END:cmd-A>>\n' +
        '<<CMD_START:cmd-B>>\ncontent-B\n<<CMD_END:cmd-B>>';
      expect(extractSentinelContent(output, 'cmd-A')).to.include('content-A');
      expect(extractSentinelContent(output, 'cmd-B')).to.include('content-B');
    });
  });

  // -------------------------------------------------------------------------
  // parseError
  // -------------------------------------------------------------------------
  describe('parseError', () => {
    it('parses a double-star error line', () => {
      expect(parseError('** Error: something went wrong')).to.equal('something went wrong');
    });

    it('parses a triple-star error line', () => {
      expect(parseError('*** Error: severe problem')).to.equal('severe problem');
    });

    it('returns null for non-error lines', () => {
      expect(parseError('normal output line')).to.be.null;
    });

    it('returns null for empty string', () => {
      expect(parseError('')).to.be.null;
    });

    it('trims trailing whitespace from the error message', () => {
      const result = parseError('** Error: trailing spaces   ');
      expect(result).to.equal('trailing spaces');
    });
  });
});
