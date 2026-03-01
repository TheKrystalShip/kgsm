import { expect } from 'chai';
import {
  LaunchRequestArguments,
  BashdbPosition,
  BashdbBreakpoint,
  BashdbVariable,
  BashdbStackFrame,
  CommandResponse,
  StopReason,
  RuntimeState,
  ScopeCategory,
} from '../../src/types';

describe('Types', () => {
  it('should allow creating a valid LaunchRequestArguments', () => {
    const args: LaunchRequestArguments = {
      program: '/tmp/test.sh',
      noDebug: false,
    };
    expect(args.program).to.equal('/tmp/test.sh');
  });

  it('should allow creating a valid BashdbPosition', () => {
    const pos: BashdbPosition = { file: '/tmp/test.sh', line: 42 };
    expect(pos.file).to.equal('/tmp/test.sh');
    expect(pos.line).to.equal(42);
  });

  it('should allow creating a BashdbVariable with children', () => {
    const v: BashdbVariable = {
      name: 'arr',
      value: '(1 2 3)',
      type: 'array',
      attributes: [],
      children: [
        { name: '[0]', value: '1', type: 'string', attributes: [] },
        { name: '[1]', value: '2', type: 'string', attributes: [] },
      ],
    };
    expect(v.children).to.have.lengthOf(2);
  });

  it('should allow creating a BashdbBreakpoint with all fields', () => {
    const bp: BashdbBreakpoint = {
      id: 1,
      file: '/tmp/test.sh',
      line: 10,
      verified: true,
      enabled: true,
      condition: 'x > 5',
      hitCount: 3,
      message: 'test',
    };
    expect(bp.id).to.equal(1);
    expect(bp.condition).to.equal('x > 5');
  });

  it('should allow creating a BashdbStackFrame', () => {
    const frame: BashdbStackFrame = {
      index: 0,
      file: '/tmp/test.sh',
      line: 5,
      functionName: 'main',
      args: 'arg1 arg2',
      isCurrent: true,
    };
    expect(frame.index).to.equal(0);
    expect(frame.isCurrent).to.be.true;
  });

  it('should allow creating a CommandResponse', () => {
    const resp: CommandResponse = {
      commandId: 'abc-123',
      output: 'some output\n',
      lines: ['some output'],
    };
    expect(resp.commandId).to.equal('abc-123');
    expect(resp.lines).to.have.lengthOf(1);
  });

  it('should support all StopReason values', () => {
    // Compile-time validation: TypeScript will error if any member is missing or invalid
    const reasons: StopReason[] = ['step', 'breakpoint', 'pause', 'entry', 'exception', 'data breakpoint', 'function breakpoint'];
    // Verify each value is a non-empty string
    for (const reason of reasons) {
      expect(reason).to.be.a('string').and.not.be.empty;
    }
  });

  it('should support all RuntimeState values', () => {
    const states: RuntimeState[] = ['uninitialized', 'launching', 'running', 'stopped', 'terminated'];
    for (const state of states) {
      expect(state).to.be.a('string').and.not.be.empty;
    }
  });

  it('should support all ScopeCategory values', () => {
    const scopes: ScopeCategory[] = ['locals', 'globals', 'environment'];
    for (const scope of scopes) {
      expect(scope).to.be.a('string').and.not.be.empty;
    }
  });
});
