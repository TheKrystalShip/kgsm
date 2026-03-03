import { expect } from 'chai';
import { PathMapper } from '../../src/pathMapper';

describe('PathMapper', () => {
  describe('no mappings', () => {
    it('toRemote() should return path unchanged when no mappings configured', () => {
      const mapper = new PathMapper();
      expect(mapper.toRemote('/local/some/file.sh')).to.equal('/local/some/file.sh');
    });

    it('toLocal() should return path unchanged when no mappings configured', () => {
      const mapper = new PathMapper();
      expect(mapper.toLocal('/remote/some/file.sh')).to.equal('/remote/some/file.sh');
    });
  });

  describe('empty mappings array', () => {
    it('toRemote() should return path unchanged with empty array', () => {
      const mapper = new PathMapper([]);
      expect(mapper.toRemote('/local/some/file.sh')).to.equal('/local/some/file.sh');
    });

    it('toLocal() should return path unchanged with empty array', () => {
      const mapper = new PathMapper([]);
      expect(mapper.toLocal('/remote/some/file.sh')).to.equal('/remote/some/file.sh');
    });
  });

  describe('single mapping', () => {
    const mapper = new PathMapper([
      { localRoot: '/local/root', remoteRoot: '/remote/root' },
    ]);

    it('toRemote() should translate local path to remote path', () => {
      expect(mapper.toRemote('/local/root/file.sh')).to.equal('/remote/root/file.sh');
    });

    it('toLocal() should translate remote path to local path', () => {
      expect(mapper.toLocal('/remote/root/file.sh')).to.equal('/local/root/file.sh');
    });

    it('toRemote() should return unchanged path that does not match', () => {
      expect(mapper.toRemote('/other/path/file.sh')).to.equal('/other/path/file.sh');
    });

    it('toLocal() should return unchanged path that does not match', () => {
      expect(mapper.toLocal('/other/path/file.sh')).to.equal('/other/path/file.sh');
    });
  });

  describe('nested path', () => {
    it('toRemote() should correctly map a deeply nested path', () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root', remoteRoot: '/remote/root' },
      ]);
      expect(mapper.toRemote('/local/root/sub/dir/file.sh')).to.equal('/remote/root/sub/dir/file.sh');
    });

    it('toLocal() should correctly map a deeply nested path', () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root', remoteRoot: '/remote/root' },
      ]);
      expect(mapper.toLocal('/remote/root/sub/dir/file.sh')).to.equal('/local/root/sub/dir/file.sh');
    });
  });

  describe('multiple mappings — first match wins', () => {
    const mapper = new PathMapper([
      { localRoot: '/local/first', remoteRoot: '/remote/first' },
      { localRoot: '/local/second', remoteRoot: '/remote/second' },
      { localRoot: '/local/first/sub', remoteRoot: '/remote/override' },
    ]);

    it('toRemote() should use the first matching mapping', () => {
      expect(mapper.toRemote('/local/first/file.sh')).to.equal('/remote/first/file.sh');
    });

    it('toRemote() should use the second mapping when first does not match', () => {
      expect(mapper.toRemote('/local/second/file.sh')).to.equal('/remote/second/file.sh');
    });

    it('toRemote() first match wins even if a later mapping is more specific', () => {
      // /local/first/sub matches /local/first before /local/first/sub
      expect(mapper.toRemote('/local/first/sub/file.sh')).to.equal('/remote/first/sub/file.sh');
    });

    it('toLocal() should use the first matching mapping', () => {
      expect(mapper.toLocal('/remote/first/file.sh')).to.equal('/local/first/file.sh');
    });
  });

  describe('trailing slash normalization', () => {
    it('toRemote() treats localRoot with trailing slash same as without', () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root/', remoteRoot: '/remote/root/' },
      ]);
      expect(mapper.toRemote('/local/root/file.sh')).to.equal('/remote/root/file.sh');
    });

    it('toLocal() treats remoteRoot with trailing slash same as without', () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root/', remoteRoot: '/remote/root/' },
      ]);
      expect(mapper.toLocal('/remote/root/file.sh')).to.equal('/local/root/file.sh');
    });
  });

  describe('exact root match', () => {
    it('toRemote() should map when path equals localRoot exactly', () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root', remoteRoot: '/remote/root' },
      ]);
      expect(mapper.toRemote('/local/root')).to.equal('/remote/root');
    });

    it('toLocal() should map when path equals remoteRoot exactly', () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root', remoteRoot: '/remote/root' },
      ]);
      expect(mapper.toLocal('/remote/root')).to.equal('/local/root');
    });
  });

  describe('partial name collision', () => {
    it('toRemote() should NOT match /foo/bar against /foo/barbaz/file.sh', () => {
      const mapper = new PathMapper([
        { localRoot: '/foo/bar', remoteRoot: '/remote/bar' },
      ]);
      expect(mapper.toRemote('/foo/barbaz/file.sh')).to.equal('/foo/barbaz/file.sh');
    });

    it('toLocal() should NOT match /remote/bar against /remote/barbaz/file.sh', () => {
      const mapper = new PathMapper([
        { localRoot: '/foo/bar', remoteRoot: '/remote/bar' },
      ]);
      expect(mapper.toLocal('/remote/barbaz/file.sh')).to.equal('/remote/barbaz/file.sh');
    });
  });

  describe('hasMappings', () => {
    it('should return false when no mappings are provided', () => {
      expect(new PathMapper().hasMappings).to.be.false;
    });

    it('should return false with an empty mappings array', () => {
      expect(new PathMapper([]).hasMappings).to.be.false;
    });

    it('should return true when at least one mapping is configured', () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root', remoteRoot: '/remote/root' },
      ]);
      expect(mapper.hasMappings).to.be.true;
    });
  });

  describe('isResolved', () => {
    it('should return true when no placeholders exist', () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root', remoteRoot: '/remote/root' },
      ]);
      expect(mapper.isResolved).to.be.true;
    });

    it('should return true when no mappings exist', () => {
      expect(new PathMapper().isResolved).to.be.true;
    });

    it('should return false when env var placeholders are present', () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root', remoteRoot: '${env:SANDBOX_PATH}' },
      ]);
      expect(mapper.isResolved).to.be.false;
    });
  });

  describe('resolveEnvVars', () => {
    it('should resolve ${env:VAR} in remoteRoot', async () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root', remoteRoot: '${env:SANDBOX_PATH}/project' },
      ]);
      await mapper.resolveEnvVars(async (name) => {
        if (name === 'SANDBOX_PATH') return '/tmp/sandbox-123';
        return undefined;
      });
      expect(mapper.isResolved).to.be.true;
      expect(mapper.toRemote('/local/root/core/foo.sh')).to.equal('/tmp/sandbox-123/project/core/foo.sh');
      expect(mapper.toLocal('/tmp/sandbox-123/project/core/foo.sh')).to.equal('/local/root/core/foo.sh');
    });

    it('should resolve ${env:VAR} in localRoot', async () => {
      const mapper = new PathMapper([
        { localRoot: '${env:WORKSPACE}', remoteRoot: '/remote/root' },
      ]);
      await mapper.resolveEnvVars(async (name) => {
        if (name === 'WORKSPACE') return '/home/user/project';
        return undefined;
      });
      expect(mapper.toRemote('/home/user/project/file.sh')).to.equal('/remote/root/file.sh');
    });

    it('should resolve multiple env vars in the same path', async () => {
      const mapper = new PathMapper([
        { localRoot: '/local', remoteRoot: '${env:BASE}/${env:SUB}' },
      ]);
      await mapper.resolveEnvVars(async (name) => {
        if (name === 'BASE') return '/tmp';
        if (name === 'SUB') return 'sandbox-42';
        return undefined;
      });
      expect(mapper.toRemote('/local/file.sh')).to.equal('/tmp/sandbox-42/file.sh');
    });

    it('should leave unresolved vars as-is when envGetter returns undefined', async () => {
      const mapper = new PathMapper([
        { localRoot: '/local', remoteRoot: '${env:MISSING}/stuff' },
      ]);
      await mapper.resolveEnvVars(async () => undefined);
      // Unresolved placeholder remains — mapping fires but produces path with raw placeholder
      expect(mapper.toRemote('/local/file.sh')).to.equal('${env:MISSING}/stuff/file.sh');
    });

    it('should handle mappings without any placeholders during resolve', async () => {
      const mapper = new PathMapper([
        { localRoot: '/local/root', remoteRoot: '/remote/root' },
      ]);
      await mapper.resolveEnvVars(async () => undefined);
      // Should still work as before
      expect(mapper.toRemote('/local/root/file.sh')).to.equal('/remote/root/file.sh');
    });
  });
});
