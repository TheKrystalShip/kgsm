import { expect } from 'chai';
import * as path from 'path';
import {
  findExecutable,
  fileExists,
  resolveBashPath,
  parseBashVersion,
  checkBashVersion,
  getBashVersion,
  resolveScriptPath,
  shellEscape,
} from '../../src/util';

describe('util', () => {
  describe('findExecutable', () => {
    it('should return a path when finding "bash"', () => {
      const result = findExecutable('bash');
      expect(result).to.be.a('string').and.not.be.null;
      expect(result).to.include('bash');
    });

    it('should return null for a non-existent binary', () => {
      const result = findExecutable('__definitely_nonexistent_binary_xyz__');
      expect(result).to.be.null;
    });
  });

  describe('fileExists', () => {
    it('should return true for an existing file', () => {
      // __filename is the compiled JS file path; use the source TS file instead
      const knownPath = '/usr/bin/bash';
      // Fall back to /bin/bash if needed
      const existing = fileExists(knownPath) ? knownPath : '/bin/bash';
      expect(fileExists(existing)).to.be.true;
    });

    it('should return false for a non-existent path', () => {
      expect(fileExists('/tmp/__nonexistent_kgsm_test_file_xyz__')).to.be.false;
    });
  });

  describe('resolveBashPath', () => {
    it('should find system bash with no override', () => {
      const result = resolveBashPath();
      expect(result).to.be.a('string');
      expect(result).to.include('bash');
    });

    it('should return the override path when it exists', () => {
      // Find actual bash path and use it as a valid override
      const bashPath = resolveBashPath();
      expect(bashPath).to.not.be.null;
      const result = resolveBashPath(bashPath!);
      expect(result).to.equal(bashPath);
    });

    it('should fall back to system detection when override path does not exist', () => {
      const result = resolveBashPath('/nonexistent/path/to/bash');
      // Should still find system bash via candidate list or PATH
      expect(result).to.be.a('string');
      expect(result).to.include('bash');
    });
  });

  describe('parseBashVersion', () => {
    it('should parse "5.1.16(1)-release" to { major: 5, minor: 1 }', () => {
      const result = parseBashVersion('5.1.16(1)-release');
      expect(result).to.deep.equal({ major: 5, minor: 1 });
    });

    it('should parse "4.4.20(1)-release" to { major: 4, minor: 4 }', () => {
      const result = parseBashVersion('4.4.20(1)-release');
      expect(result).to.deep.equal({ major: 4, minor: 4 });
    });

    it('should parse "4.0" to { major: 4, minor: 0 }', () => {
      const result = parseBashVersion('4.0');
      expect(result).to.deep.equal({ major: 4, minor: 0 });
    });

    it('should return null for "invalid"', () => {
      const result = parseBashVersion('invalid');
      expect(result).to.be.null;
    });
  });

  describe('checkBashVersion', () => {
    it('should return ok: true with a modern system bash', () => {
      const bashPath = resolveBashPath();
      expect(bashPath).to.not.be.null;
      const result = checkBashVersion(bashPath!);
      expect(result.ok).to.be.true;
    });

    it('should return an object with ok, version, and message fields', () => {
      const bashPath = resolveBashPath();
      expect(bashPath).to.not.be.null;
      const result = checkBashVersion(bashPath!);
      expect(result).to.have.property('ok').that.is.a('boolean');
      expect(result).to.have.property('version').that.is.a('string');
      expect(result).to.have.property('message').that.is.a('string');
    });

    it('should return ok: false with an invalid bash path', () => {
      const result = checkBashVersion('/nonexistent/bash');
      expect(result.ok).to.be.false;
      expect(result.version).to.equal('unknown');
    });
  });

  describe('getBashVersion', () => {
    it('should return a version string for a valid bash path', () => {
      const bashPath = resolveBashPath();
      expect(bashPath).to.not.be.null;
      const version = getBashVersion(bashPath!);
      expect(version).to.be.a('string');
      // Should look like "5.1.16(1)-release" or similar
      expect(version).to.match(/^\d+\.\d+/);
    });

    it('should return null for an invalid path', () => {
      const version = getBashVersion('/nonexistent/bash');
      expect(version).to.be.null;
    });
  });

  describe('resolveScriptPath', () => {
    it('should return an absolute path unchanged', () => {
      const absPath = '/tmp/test.sh';
      expect(resolveScriptPath(absPath)).to.equal(absPath);
    });

    it('should resolve a relative path against cwd', () => {
      const cwd = '/tmp';
      const result = resolveScriptPath('test.sh', cwd);
      expect(result).to.equal(path.join('/tmp', 'test.sh'));
    });

    it('should resolve a relative path against process.cwd() when no cwd is given', () => {
      const result = resolveScriptPath('test.sh');
      expect(result).to.equal(path.resolve(process.cwd(), 'test.sh'));
    });
  });

  describe('shellEscape', () => {
    it('should wrap a simple string in single quotes', () => {
      expect(shellEscape('hello')).to.equal("'hello'");
    });

    it('should handle an empty string', () => {
      expect(shellEscape('')).to.equal("''");
    });

    it('should escape embedded single quotes', () => {
      expect(shellEscape("it's")).to.equal("'it'\\''s'");
    });

    it('should pass through double quotes without modification', () => {
      expect(shellEscape('say "hello"')).to.equal("'say \"hello\"'");
    });

    it('should pass through backticks without modification', () => {
      expect(shellEscape('`cmd`')).to.equal("'`cmd`'");
    });

    it('should pass through dollar signs without modification', () => {
      expect(shellEscape('$HOME')).to.equal("'$HOME'");
    });

    it('should handle multiple single quotes', () => {
      expect(shellEscape("a'b'c")).to.equal("'a'\\''b'\\''c'");
    });

    it('should handle mixed special characters', () => {
      const input = 'val="hello\'s $world"';
      const result = shellEscape(input);
      // Should only escape single quotes; everything else is literal inside single quotes
      expect(result).to.equal("'val=\"hello'\\''s $world\"'");
    });
  });
});
