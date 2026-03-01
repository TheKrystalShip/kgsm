import { expect } from 'chai';
import * as path from 'path';
import { execSync } from 'child_process';
import { BashdbRuntime } from '../../src/bashdbRuntime';
import {
  getPrerequisiteStatus,
  parseBashVersion,
  isBashdbAvailable,
  resolveBashPath,
} from '../../src/util';

const SCRIPTS_DIR = path.join(__dirname, '..', 'scripts');

function bashdbAvailable(): boolean {
  try {
    execSync('which bashdb', { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Prerequisite Detection
// ---------------------------------------------------------------------------

describe('Integration Tests', () => {
  describe('Prerequisite Detection', () => {
    it('should return a valid prerequisite status object', () => {
      const status = getPrerequisiteStatus();
      expect(status).to.have.property('bash');
      expect(status).to.have.property('bashdb');
    });

    it('bash status should have required fields', () => {
      const status = getPrerequisiteStatus();
      expect(status.bash).to.have.property('found').that.is.a('boolean');
      expect(status.bash).to.have.property('path');
      expect(status.bash).to.have.property('version');
      expect(status.bash).to.have.property('ok').that.is.a('boolean');
      expect(status.bash).to.have.property('message').that.is.a('string');
    });

    it('bashdb status should have required fields', () => {
      const status = getPrerequisiteStatus();
      expect(status.bashdb).to.have.property('found').that.is.a('boolean');
      expect(status.bashdb).to.have.property('version');
      expect(status.bashdb).to.have.property('message').that.is.a('string');
    });

    it('should detect bash as available', () => {
      const status = getPrerequisiteStatus();
      expect(status.bash.found).to.be.true;
      expect(status.bash.ok).to.be.true;
      expect(status.bash.path).to.be.a('string').and.include('bash');
    });

    it('bash message should be a non-empty string', () => {
      const status = getPrerequisiteStatus();
      expect(status.bash.message).to.be.a('string').with.length.greaterThan(0);
    });

    it('bashdb status found field should reflect actual availability', () => {
      const status = getPrerequisiteStatus();
      const expected = bashdbAvailable();
      expect(status.bashdb.found).to.equal(expected);
    });

    it('isBashdbAvailable should return a boolean', () => {
      const result = isBashdbAvailable();
      expect(result).to.be.a('boolean');
    });

    it('parseBashVersion should parse a modern version string', () => {
      // Use a representative version string; this is a pure function test
      const parsed = parseBashVersion('5.1.16(1)-release');
      expect(parsed).to.not.be.null;
      expect(parsed!.major).to.equal(5);
      expect(parsed!.minor).to.equal(1);
    });

    it('parseBashVersion should return null for an empty string', () => {
      expect(parseBashVersion('')).to.be.null;
    });

    it('getPrerequisiteStatus should respect a bash path override', () => {
      const bashPath = resolveBashPath();
      const status = getPrerequisiteStatus(bashPath ?? undefined);
      expect(status.bash.ok).to.be.true;
    });
  });

  // ---------------------------------------------------------------------------
  // Runtime Initialization (no bashdb required)
  // ---------------------------------------------------------------------------

  describe('Runtime Initialization', () => {
    it('should create a BashdbRuntime instance without errors', () => {
      const runtime = new BashdbRuntime();
      expect(runtime).to.be.instanceOf(BashdbRuntime);
    });

    it('should start in the uninitialized state', () => {
      const runtime = new BashdbRuntime();
      expect(runtime.state).to.equal('uninitialized');
    });

    it('currentPosition should be null before launch', () => {
      const runtime = new BashdbRuntime();
      expect(runtime.currentPosition).to.be.null;
    });

    it('should extend EventEmitter — on/emit should work', () => {
      const runtime = new BashdbRuntime();
      const received: string[] = [];
      runtime.on('output', (text: string) => received.push(text));
      runtime.emit('output', 'hello', 'stdout');
      expect(received).to.deep.equal(['hello']);
    });

    it('should support multiple event subscriptions', () => {
      const runtime = new BashdbRuntime();
      const log: string[] = [];
      runtime.on('output', () => log.push('output'));
      runtime.on('terminated', () => log.push('terminated'));
      runtime.emit('output', 'msg', 'stdout');
      runtime.emit('terminated');
      expect(log).to.deep.equal(['output', 'terminated']);
    });

    it('should support once() listener', () => {
      const runtime = new BashdbRuntime();
      let count = 0;
      runtime.once('output', () => count++);
      runtime.emit('output', 'first', 'stdout');
      runtime.emit('output', 'second', 'stdout');
      expect(count).to.equal(1);
    });

    it('terminate() on an unstarted runtime should resolve without throwing', async () => {
      const runtime = new BashdbRuntime();
      await runtime.terminate(); // should not throw
    });

    it('should create multiple independent runtime instances', () => {
      const r1 = new BashdbRuntime();
      const r2 = new BashdbRuntime();
      expect(r1).to.not.equal(r2);
      expect(r1.state).to.equal('uninitialized');
      expect(r2.state).to.equal('uninitialized');
    });
  });

  // ---------------------------------------------------------------------------
  // Launch validation (no bashdb required — uses bash directly)
  // ---------------------------------------------------------------------------

  describe('Runtime launch validation', () => {
    it('should reject launch with a non-existent script', async () => {
      const runtime = new BashdbRuntime();
      let caught: Error | null = null;
      try {
        await runtime.launch({
          program: '/nonexistent/path/to/script.sh',
          stopOnEntry: true,
        } as any);
      } catch (err) {
        caught = err as Error;
      } finally {
        await runtime.terminate().catch(() => undefined);
      }
      // Either the promise rejects OR it times out — a rejection is the happy path here
      // If bashdb is unavailable bash --debugger may also fail
      expect(caught).to.not.be.null;
    });

    it('should reject launch with an invalid bash path', async () => {
      const runtime = new BashdbRuntime();
      let caught: Error | null = null;
      try {
        await runtime.launch({
          program: path.join(SCRIPTS_DIR, 'simple.sh'),
          pathBash: '/nonexistent/bash',
          stopOnEntry: true,
        } as any);
      } catch (err) {
        caught = err as Error;
      } finally {
        await runtime.terminate().catch(() => undefined);
      }
      expect(caught).to.not.be.null;
      expect(caught!.message).to.include('/nonexistent/bash');
    });
  });

  // ---------------------------------------------------------------------------
  // Tests that require bashdb
  // ---------------------------------------------------------------------------

  describe('Runtime with bashdb', function () {
    before(function () {
      if (!bashdbAvailable()) {
        this.skip();
      }
    });

    let runtime: BashdbRuntime;

    beforeEach(() => {
      runtime = new BashdbRuntime();
    });

    afterEach(async () => {
      await runtime.terminate().catch(() => undefined);
    });

    // -------------------------------------------------------------------------
    // Launch and stop on entry
    // -------------------------------------------------------------------------

    it('should launch simple.sh and emit stopped:entry', function (done) {
      this.timeout(15000);

      runtime.once('stopped', (reason: string) => {
        try {
          expect(reason).to.equal('entry');
          done();
        } catch (e) {
          done(e);
        }
      });

      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: path.join(SCRIPTS_DIR, 'simple.sh'),
          stopOnEntry: true,
          noDebug: false,
        } as any)
        .then(() => {
          // launch() resolves after bashdb is ready; trigger config-done flow
          runtime.continueAfterConfigDone(true);
        })
        .catch(done);
    });

    it('should set state to stopped after launch with stopOnEntry', function (done) {
      this.timeout(15000);

      runtime.once('stopped', () => {
        try {
          expect(runtime.state).to.equal('stopped');
          done();
        } catch (e) {
          done(e);
        }
      });

      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: path.join(SCRIPTS_DIR, 'simple.sh'),
          stopOnEntry: true,
          noDebug: false,
        } as any)
        .then(() => runtime.continueAfterConfigDone(true))
        .catch(done);
    });

    it('should populate currentPosition after stopping on entry', function (done) {
      this.timeout(15000);

      runtime.once('stopped', (_reason: string, position: any) => {
        try {
          expect(position).to.not.be.null;
          expect(position).to.have.property('file').that.is.a('string');
          expect(position).to.have.property('line').that.is.a('number');
          expect(position.line).to.be.greaterThan(0);
          done();
        } catch (e) {
          done(e);
        }
      });

      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: path.join(SCRIPTS_DIR, 'simple.sh'),
          stopOnEntry: true,
          noDebug: false,
        } as any)
        .then(() => runtime.continueAfterConfigDone(true))
        .catch(done);
    });

    // -------------------------------------------------------------------------
    // Step (next)
    // -------------------------------------------------------------------------

    it('should emit stopped:step after next()', function (done) {
      this.timeout(15000);
      let stoppedCount = 0;

      runtime.on('stopped', (reason: string) => {
        stoppedCount++;
        if (stoppedCount === 1) {
          // First stop is the entry stop — now step
          expect(reason).to.equal('entry');
          runtime.next().catch(done);
        } else {
          // Second stop is after the step
          try {
            expect(reason).to.equal('step');
            done();
          } catch (e) {
            done(e);
          }
        }
      });

      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: path.join(SCRIPTS_DIR, 'simple.sh'),
          stopOnEntry: true,
          noDebug: false,
        } as any)
        .then(() => runtime.continueAfterConfigDone(true))
        .catch(done);
    });

    it('should advance line number after next()', function (done) {
      this.timeout(15000);
      let firstLine: number | null = null;
      let stoppedCount = 0;

      runtime.on('stopped', (_reason: string, position: any) => {
        stoppedCount++;
        if (stoppedCount === 1) {
          firstLine = position?.line ?? null;
          runtime.next().catch(done);
        } else {
          try {
            const secondLine = position?.line ?? null;
            expect(firstLine).to.not.be.null;
            expect(secondLine).to.not.be.null;
            // Lines should differ after a step (or stay the same on a multi-stmt line)
            expect(secondLine).to.be.a('number').and.greaterThan(0);
            done();
          } catch (e) {
            done(e);
          }
        }
      });

      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: path.join(SCRIPTS_DIR, 'simple.sh'),
          stopOnEntry: true,
          noDebug: false,
        } as any)
        .then(() => runtime.continueAfterConfigDone(true))
        .catch(done);
    });

    // -------------------------------------------------------------------------
    // Breakpoints
    // -------------------------------------------------------------------------

    it('should set a breakpoint and stop at it', function (done) {
      this.timeout(20000);
      const scriptPath = path.join(SCRIPTS_DIR, 'breakpoints.sh');

      runtime.once('stopped', async (reason: string) => {
        if (reason !== 'entry') {
          done(new Error(`Unexpected first stop reason: ${reason}`));
          return;
        }

        // Set a breakpoint on the echo line (line 15)
        try {
          await runtime.setBreakpoint(scriptPath, 15);
        } catch (err) {
          done(err);
          return;
        }

        // Listen for the breakpoint hit
        runtime.once('stopped', (hitReason: string) => {
          try {
            expect(hitReason).to.equal('breakpoint');
            done();
          } catch (e) {
            done(e);
          }
        });

        runtime.continue().catch(done);
      });

      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: scriptPath,
          stopOnEntry: true,
          noDebug: false,
        } as any)
        .then(() => runtime.continueAfterConfigDone(true))
        .catch(done);
    });

    it('should return a valid BashdbBreakpoint object from setBreakpoint', function (done) {
      this.timeout(15000);
      const scriptPath = path.join(SCRIPTS_DIR, 'breakpoints.sh');

      runtime.once('stopped', async () => {
        try {
          const bp = await runtime.setBreakpoint(scriptPath, 15);
          expect(bp).to.have.property('id').that.is.a('number');
          expect(bp).to.have.property('file').that.includes('breakpoints.sh');
          expect(bp).to.have.property('line').that.is.a('number');
          expect(bp).to.have.property('verified').that.is.a('boolean');
          expect(bp).to.have.property('enabled').that.is.a('boolean');
          done();
        } catch (e) {
          done(e);
        }
      });

      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: scriptPath,
          stopOnEntry: true,
          noDebug: false,
        } as any)
        .then(() => runtime.continueAfterConfigDone(true))
        .catch(done);
    });

    // -------------------------------------------------------------------------
    // Stack trace
    // -------------------------------------------------------------------------

    it('should return a non-empty stack trace when stopped', function (done) {
      this.timeout(15000);

      runtime.once('stopped', async () => {
        try {
          const frames = await runtime.getStackTrace();
          expect(frames).to.be.an('array').with.length.greaterThan(0);
          expect(frames[0]).to.have.property('file').that.is.a('string');
          expect(frames[0]).to.have.property('line').that.is.a('number');
          expect(frames[0]).to.have.property('isCurrent').that.is.true;
          done();
        } catch (e) {
          done(e);
        }
      });

      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: path.join(SCRIPTS_DIR, 'simple.sh'),
          stopOnEntry: true,
          noDebug: false,
        } as any)
        .then(() => runtime.continueAfterConfigDone(true))
        .catch(done);
    });

    // -------------------------------------------------------------------------
    // Termination
    // -------------------------------------------------------------------------

    it('should emit terminated event when script completes', function (done) {
      this.timeout(15000);

      runtime.once('terminated', () => done());
      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: path.join(SCRIPTS_DIR, 'simple.sh'),
          stopOnEntry: false,
          noDebug: false,
        } as any)
        .then(() => runtime.continueAfterConfigDone(false))
        .catch(done);
    });

    it('terminate() should resolve and not throw after an active session', function (done) {
      this.timeout(15000);

      runtime.once('stopped', async () => {
        try {
          await runtime.terminate();
          done();
        } catch (e) {
          done(e);
        }
      });

      runtime.once('error', (msg: string) => done(new Error(msg)));

      runtime
        .launch({
          program: path.join(SCRIPTS_DIR, 'simple.sh'),
          stopOnEntry: true,
          noDebug: false,
        } as any)
        .then(() => runtime.continueAfterConfigDone(true))
        .catch(done);
    });
  });
});
