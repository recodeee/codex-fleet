# Future Runtime: event bus, state, and shutdown

## Scope

This file defines the future `src/runtime/` boundary for the Polymarket CLI.
The runtime layer owns process-wide coordination that does not belong inside a
single command, adapter, or renderer:

- a typed event bus for internal status changes,
- a small state machine for lifecycle reporting,
- a shutdown path that drains in-flight work before the process exits,
- a stable API that command modules can use without depending on a specific
  async executor.

The near-term target module is `src/runtime/mod.rs`. Follow-up modules can split
this into `event_bus.rs`, `state.rs`, and `shutdown.rs` once the first runtime
stub lands.

## Mission

Commands should be able to start workers, publish progress, react to shutdown,
and expose state to the TUI or JSON output without each command inventing its
own channels and signal handling. The runtime should stay boring: predictable
types, bounded queues, explicit shutdown reasons, and no hidden background work.

## Current state

Runtime behavior is mostly implicit. Command handlers own their own loops and
shutdown decisions. State is usually printed directly, which makes it hard to
offer the same information to logs, the TUI, and machine-readable output. The
existing protocol file, `docs/future/PROTOCOL.md`, contains the broad future
catalog, but this split file is the runtime-specific contract for Phase B.

## Pain points

- [Runtime-1] Event shape is not centralized. A command can emit a message that
  another command cannot parse, so shared output and monitoring stay brittle.
- [Runtime-2] State transitions are inferred from logs instead of represented
  as data. That makes resume, status, and graceful shutdown difficult to test.
- [Runtime-3] Shutdown semantics are inconsistent. Some paths exit immediately,
  while others wait for work to finish, and callers cannot tell which occurred.
- [Runtime-4] Backpressure is undefined. A hot feed can overwhelm a slow UI or
  logger because the queue policy is not named.
- [Runtime-5] Async runtime choice is premature. The CLI needs an interface that
  can be implemented with synchronous tests first and swapped to Tokio later.

## Proposals

### [Runtime-1] Typed runtime events

Define `RuntimeEvent` as the only event shape that crosses runtime boundaries.
Initial variants should cover lifecycle transitions, command progress,
warnings, and shutdown requests. Payloads should be small and cloneable.

Acceptance:

- event producers call `EventBus::publish(RuntimeEvent)`,
- command code never sends raw strings through runtime channels,
- every event variant has a documented consumer expectation.

### [Runtime-2] Explicit lifecycle state

Represent runtime status as `RuntimeState`, with `Starting`, `Running`,
`Draining`, `Stopped`, and `Failed` states. State changes should be emitted as
events and stored as the last-known state for status commands.

Acceptance:

- a new command can report lifecycle through state transitions only,
- tests can assert state without parsing logs,
- failure carries a short reason string or typed error code.

### [Runtime-3] Graceful shutdown contract

Introduce `ShutdownSignal` with a reason and drain policy. The default policy is
soft drain: stop accepting new work, emit a shutdown event, flush queued events,
then exit. Hard stop is reserved for corrupted state, repeated signal delivery,
or operator-requested abort.

Acceptance:

- one shutdown request is idempotent,
- a second stronger request can escalate to hard stop,
- shutdown state is visible to TUI and JSON callers before exit.

### [Runtime-4] Bounded event queue

Use a bounded in-memory queue for the first implementation. When full, preserve
shutdown and failure events, then drop low-priority progress events with a
counter. This keeps the process responsive under noisy market feeds.

Acceptance:

- queue capacity is configurable in `RuntimeConfig`,
- dropped progress count is exposed as runtime state,
- shutdown and failure events are never silently dropped.

### [Runtime-5] Executor-neutral API

Keep the first `src/runtime/` API synchronous and dependency-light. A future
Tokio-backed implementation can sit behind the same bus and shutdown types
without forcing every command module to become async.

Acceptance:

- the runtime stub compiles without external crates,
- command modules can own their own blocking work while publishing events,
- async integration is deferred until a command demonstrates a real need.

Deferred:

- OS signal registration is deferred to the command runner because it depends on
  the final CLI entrypoint shape.
- Cross-process event persistence is deferred until storage design is ready.

## Runtime state model

The state model should be small enough to render in one status row:

| State | Meaning | Exit behavior |
| --- | --- | --- |
| `Starting` | Runtime is building command resources. | no exit |
| `Running` | Runtime accepts events and work. | no exit |
| `Draining` | Runtime rejects new work and flushes current work. | exits after drain |
| `Stopped` | Runtime completed normally. | exit code 0 |
| `Failed` | Runtime stopped with a failure reason. | non-zero exit |

State transitions should be monotonic after shutdown starts. `Draining` can move
to `Stopped` or `Failed`; it should not move back to `Running`.

## Event bus contract

The event bus should be the narrow waist between command modules and observers.
It should not know about terminal rendering, HTTP clients, market schemas, or
storage. Those modules translate their own domain events into `RuntimeEvent`
values before publishing.

Minimum event fields:

- `RuntimeEvent::StateChanged(RuntimeState)`,
- `RuntimeEvent::Progress { command, message }`,
- `RuntimeEvent::Warning { code, message }`,
- `RuntimeEvent::ShutdownRequested(ShutdownSignal)`,
- `RuntimeEvent::DroppedProgress { count }`.

## Shutdown contract

Shutdown should be observable and repeatable:

1. Receive a `ShutdownSignal`.
2. Publish `ShutdownRequested`.
3. Move state from `Running` to `Draining`.
4. Stop accepting new command work.
5. Drain queued events.
6. Move to `Stopped` or `Failed`.

A hard stop can skip drain, but it must still update state when possible.

## Verification notes

The Appendix Rust block is self-contained so it can be compiled as a library
stub before `src/runtime/` exists. The target copy path for Phase B is
`src/runtime/mod.rs`.

## Appendix: `src/runtime/mod.rs` starter stub

```rust
use std::collections::VecDeque;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RuntimeState {
    Starting,
    Running,
    Draining { reason: ShutdownReason },
    Stopped,
    Failed { reason: String },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ShutdownReason {
    Operator,
    Signal,
    InternalError,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DrainPolicy {
    SoftDrain,
    HardStop,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ShutdownSignal {
    pub reason: ShutdownReason,
    pub policy: DrainPolicy,
}

impl ShutdownSignal {
    pub fn soft(reason: ShutdownReason) -> Self {
        Self {
            reason,
            policy: DrainPolicy::SoftDrain,
        }
    }

    pub fn hard(reason: ShutdownReason) -> Self {
        Self {
            reason,
            policy: DrainPolicy::HardStop,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RuntimeEvent {
    StateChanged(RuntimeState),
    Progress { command: String, message: String },
    Warning { code: String, message: String },
    ShutdownRequested(ShutdownSignal),
    DroppedProgress { count: u64 },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RuntimeConfig {
    pub event_capacity: usize,
}

impl Default for RuntimeConfig {
    fn default() -> Self {
        Self { event_capacity: 256 }
    }
}

#[derive(Debug)]
pub struct EventBus {
    capacity: usize,
    events: VecDeque<RuntimeEvent>,
    dropped_progress: u64,
}

impl EventBus {
    pub fn new(config: RuntimeConfig) -> Self {
        Self {
            capacity: config.event_capacity.max(1),
            events: VecDeque::new(),
            dropped_progress: 0,
        }
    }

    pub fn publish(&mut self, event: RuntimeEvent) {
        if self.events.len() < self.capacity {
            self.events.push_back(event);
            return;
        }

        match event {
            RuntimeEvent::ShutdownRequested(_)
            | RuntimeEvent::StateChanged(RuntimeState::Failed { .. }) => {
                self.drop_oldest_progress();
                self.events.push_back(event);
            }
            RuntimeEvent::Progress { .. } => {
                self.dropped_progress = self.dropped_progress.saturating_add(1);
            }
            other => {
                self.drop_oldest_progress();
                self.events.push_back(other);
            }
        }
    }

    pub fn drain(&mut self) -> Vec<RuntimeEvent> {
        self.events.drain(..).collect()
    }

    pub fn dropped_progress(&self) -> u64 {
        self.dropped_progress
    }

    fn drop_oldest_progress(&mut self) {
        if let Some(index) = self
            .events
            .iter()
            .position(|event| matches!(event, RuntimeEvent::Progress { .. }))
        {
            self.events.remove(index);
            self.dropped_progress = self.dropped_progress.saturating_add(1);
            return;
        }

        self.events.pop_front();
    }
}

#[derive(Debug)]
pub struct RuntimeController {
    state: RuntimeState,
    bus: EventBus,
}

impl RuntimeController {
    pub fn new(config: RuntimeConfig) -> Self {
        let mut bus = EventBus::new(config);
        let state = RuntimeState::Starting;
        bus.publish(RuntimeEvent::StateChanged(state.clone()));
        Self { state, bus }
    }

    pub fn mark_running(&mut self) {
        self.set_state(RuntimeState::Running);
    }

    pub fn request_shutdown(&mut self, signal: ShutdownSignal) {
        if matches!(self.state, RuntimeState::Stopped | RuntimeState::Failed { .. }) {
            return;
        }

        self.bus
            .publish(RuntimeEvent::ShutdownRequested(signal.clone()));

        match signal.policy {
            DrainPolicy::SoftDrain => {
                self.set_state(RuntimeState::Draining {
                    reason: signal.reason,
                });
            }
            DrainPolicy::HardStop => {
                self.set_state(RuntimeState::Stopped);
            }
        }
    }

    pub fn fail(&mut self, reason: impl Into<String>) {
        self.set_state(RuntimeState::Failed {
            reason: reason.into(),
        });
    }

    pub fn state(&self) -> &RuntimeState {
        &self.state
    }

    pub fn bus_mut(&mut self) -> &mut EventBus {
        &mut self.bus
    }

    fn set_state(&mut self, state: RuntimeState) {
        self.state = state.clone();
        self.bus.publish(RuntimeEvent::StateChanged(state));
    }
}
```
