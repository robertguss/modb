## Milestone 6: Real-World Multi-Agent Engineering & Operations Workbench (`AgentWorkbench`)
## Exercises every MoDB layer end-to-end under `mo serve --workers 8`:
## - Layer 1: CoW B+Tree, persistent root pins, O(diff), lock-free optimistic reads, crash safety
## - Layer 2: Typed tables (`projects`, `tasks`, `artifacts`) with atomic secondary indexes
## - Layer 3: Hash-chained audit ledger, O(touched) incremental commit-time invariants, migrations
## - Layer 4: Attenuated Grants, Claims/leases, speculative Worlds + needless send-back telemetry,
##            upgrade-aware Replay (selective undo + NowAccepted + bug-fix override), & Export
##
## Run live:
##   mo serve --workers 8 --data ./workbench-data examples/agent-workbench.mo
## Test in-memory (zero sockets):
##   mo test examples/agent-workbench.mo
module AgentWorkbench
use Api
use Json
use Modb
use Modb.Claims
use Modb.Export
use Modb.Grants
use Modb.Ledger
use Modb.Replay
use Modb.Table
use Modb.World

enum Role
  Admin
  Planner
  Worker
end

struct Caller
  principal: Text
  role: Role
  reason: Option(Text)
end

struct Project
  name: Text
  budget_cents: Int
  spent_cents: Int
  active: Bool
end

struct ProjectInput
  id: Text
  name: Text
  budget_cents: Int
end

struct ProjectRow
  id: Text
  name: Text
  budget_cents: Int
  spent_cents: Int
  remaining_cents: Int
  active: Bool
end

enum TaskStatus
  Open
  InProgress
  Done
  Cancelled
end

struct Task
  project_id: Text
  title: Text
  assignee: Option(Text)
  base_cost_cents: Int
  billed_cents: Int
  status: TaskStatus
end

struct CreateTaskInput
  id: Int
  project_id: Text
  title: Text
  base_cost_cents: Int
end

struct CompleteTaskInput
  task_id: Int
  assignee: Text
  artifact_id: Option(Text)
  artifact_summary: Option(Text)
  artifact_sha256: Option(Text)
end

struct TaskRow
  id: Int
  project_id: Text
  title: Text
  assignee: Option(Text)
  base_cost_cents: Int
  billed_cents: Int
  status: TaskStatus
end

struct Artifact
  task_id: Int
  author: Text
  summary: Text
  sha256: Text
end

struct ArtifactRow
  id: Text
  task_id: Int
  author: Text
  summary: Text
  sha256: Text
end

struct HealthResponse
  status: Text
  txid: Int
  schema_version: Int
  audit_count: Int
  call_count: Int
end

struct VerifySummary
  ok: Bool
  txid: Int
  page_count: Int
  bucket_count: Int
  schema_version: Int
  audit_entries: Int
  last_audit_hash: Text
  invariants_checked: Int
end

struct GrantInput
  id: Text
  principal: Text
  allowed_actions: List(Text)
  max_calls: Int
  ttl_seconds: Int
end

struct ClaimInput
  resource: Text
  grant_id: Text
  world_id: Option(Text)
  ttl_seconds: Int
end

struct HeartbeatInput
  ttl_seconds: Int
end

struct WorldOpenInput
  id: Text
  grant_id: Text
  ttl_seconds: Int
end

struct WorldQueryInput
  query: Text
  args: Json
end

struct WorldCallInput
  action: Text
  args: Json
end

struct ReplaySimulateInput
  proposal_id: Text
  description: Text
  exclude_principal: Option(Text)
  exclude_grant: Option(Text)
  exclude_world: Option(Text)
  exclude_seqs: Option(List(Int))
  stop_before_seq: Option(Int)
  overhead_pct_override: Option(Int)
end

struct OkStatus
  ok: Bool
end

enum WorkbenchError
  Unauthenticated
  Forbidden(required: Text)
  MissingReason
  InvalidInput(reason: Text)
  InvariantRejected(name: Text, detail: Text)
  ProjectMissing(id: Text)
  TaskMissing(id: Int)
  TaskConflict(detail: Text)
  BudgetExceeded(project_id: Text, needed: Int, remaining: Int)
  GrantMissing(id: Text)
  GrantDenied(detail: Text)
  GrantConflict(detail: Text)
  ClaimMissing(resource: Text)
  ClaimConflict(detail: Text)
  WorldMissing(id: Text)
  WorldConflict(detail: Text)
  ProposalMissing(id: Text)
  ProposalConflict(detail: Text)
  StorageFailed(message: Text)
end

api
  port 8092
  cors "*"
  auth Caller via authenticate

  get "/health" get_health

  scope "/projects"
    post "" post_project
    get "" list_projects
    get "/:id" get_project
    get "/:id/tasks" get_project_tasks
  end

  scope "/tasks"
    post "" post_task
    get "/:id" get_task
    post "/:id/complete" post_complete_task
    get "/:id/artifacts" get_task_artifacts
  end

  scope "/grants"
    post "" post_grant
    get "/:id" get_grant
    post "/:id/delegate" post_delegate_grant
    post "/:id/revoke" post_revoke_grant
  end

  scope "/claims"
    post "" post_claim
    get "" list_claims
    post "/:resource/heartbeat" post_claim_heartbeat
    delete "/:resource" delete_claim
  end

  scope "/worlds"
    post "" post_world
    get "/metrics" get_world_metrics
    post "/:id/query" post_world_query
    post "/:id/call" post_world_call
    get "/:id/diff" get_world_diff
    post "/:id/land" post_world_land
    delete "/:id" delete_world
  end

  get "/audit" get_audit
  post "/admin/init" post_admin_init
  get "/admin/verify" get_admin_verify
  get "/admin/export" get_admin_export

  scope "/admin/replay"
    get "/calls" get_replay_calls
    post "/simulate" post_replay_simulate
    get "/proposals" list_replay_proposals
    get "/proposals/:id" get_replay_proposal
    post "/proposals/:id/accept" post_replay_accept
    delete "/proposals/:id" delete_replay_proposal
  end

  status Unauthenticated = 401
  status Forbidden(_) = 403
  status MissingReason = 400
  status InvalidInput(_) = 400
  status InvariantRejected(_) = 422
  status ProjectMissing(_) = 404
  status TaskMissing(_) = 404
  status TaskConflict(_) = 409
  status BudgetExceeded(_) = 409
  status GrantMissing(_) = 404
  status GrantDenied(_) = 403
  status GrantConflict(_) = 409
  status ClaimMissing(_) = 404
  status ClaimConflict(_) = 409
  status WorldMissing(_) = 404
  status WorldConflict(_) = 409
  status ProposalMissing(_) = 404
  status ProposalConflict(_) = 409
  status StorageFailed(_) = 500
end

fn db_path() : Text
  "workbench.modb"
end

## Default billing overhead percentage applied to task completion (`10%`, overridable in Replay).
fn default_overhead_pct() : Int
  10
end

fn calc_billed_cents(base_cents: Int, overhead_pct: Int) : Int
  (base_cents * (100 + overhead_pct) + 50) / 100
end

fn task_status_label(st: TaskStatus) : Text
  case st
    Open: "open"
    InProgress: "in_progress"
    Done: "done"
    Cancelled: "cancelled"
  end
end

fn projects_table() : Table.Table(Text, Project)
  Table.text_key[Project]("projects")
end

fn tasks_by_project_index() : Table.Index(Int, Task, Text)
  Table.text_index[Int, Task]("tasks_by_project", fn(t) t.project_id end)
end

fn tasks_by_status_index() : Table.Index(Int, Task, Text)
  Table.text_index[Int, Task]("tasks_by_status", fn(t) task_status_label(t.status) end)
end

fn tasks_table() : Table.Table(Int, Task)
  Table.int_key[Task]("tasks").with_index(tasks_by_project_index()).with_index(
    tasks_by_status_index()
  )
end

fn artifacts_by_task_index() : Table.Index(Text, Artifact, Int)
  Table.int_index[Text, Artifact]("artifacts_by_task", fn(a) a.task_id end)
end

fn artifacts_table() : Table.Table(Text, Artifact)
  Table.text_key[Artifact]("artifacts").with_index(artifacts_by_task_index())
end

fn project_to_row(id: Text, p: Project) : ProjectRow
  ProjectRow(
    id: id,
    name: p.name,
    budget_cents: p.budget_cents,
    spent_cents: p.spent_cents,
    remaining_cents: p.budget_cents - p.spent_cents,
    active: p.active
  )
end

fn task_to_row(id: Int, t: Task) : TaskRow
  TaskRow(
    id: id,
    project_id: t.project_id,
    title: t.title,
    assignee: t.assignee,
    base_cost_cents: t.base_cost_cents,
    billed_cents: t.billed_cents,
    status: t.status
  )
end

## Schema v1 -> v2 with O(touched) incremental commit-time invariants.
fn workbench_schema() : Ledger.Schema
  projs = projects_table()
  tasks = tasks_table()
  arts = artifacts_table()
  Ledger.schema(2).with_require_reason(true).with_migration(
    Ledger.migration(
      1,
      "seed core platform project",
      fn(tx)
        Table.put(
          tx,
          projs,
          "core",
          Project(name: "Core Platform", budget_cents: 100000, spent_cents: 0, active: true)
        )
      end
    )
  ).with_migration(
    Ledger.migration(
      2,
      "seed infra operations project",
      fn(tx)
        Table.put(
          tx,
          projs,
          "infra",
          Project(name: "Infrastructure Ops", budget_cents: 50000, spent_cents: 0, active: true)
        )
      end
    )
  ).with_invariant(
    Ledger.row_invariant(
      "budget_bounds",
      projs,
      fn(pid, p)
        if p.budget_cents < 0
          Some("project '#{pid}' negative budget #{p.budget_cents}")
        else if p.spent_cents < 0
          Some("project '#{pid}' negative spent #{p.spent_cents}")
        else if p.spent_cents > p.budget_cents
          Some("project '#{pid}' overspent: #{p.spent_cents} > #{p.budget_cents}")
        else
          None
        end
      end
    )
  ).with_invariant(
    Ledger.row_invariant(
      "task_valid",
      tasks,
      fn(tid, t)
        if t.base_cost_cents < 0 or t.billed_cents < 0
          Some("task ##{tid} has negative cost")
        else if t.title.trim.empty?
          Some("task ##{tid} has empty title")
        else
          None
        end
      end
    )
  ).with_invariant(
    Ledger.invariant(
      "referential_integrity",
      fn(tx)
        incremental? = Modb.tx_is_tracked?(tx) and
          not Modb.tx_bucket_deleted?(tx, "projects") and
          not Modb.tx_bucket_deleted?(tx, "tasks") and
          not Modb.tx_bucket_deleted?(tx, "artifacts") and
          Modb.tx_touched_deletes(tx, "projects").empty? and
          Modb.tx_touched_deletes(tx, "tasks").empty?
        if incremental?
          for kb in Modb.tx_touched_puts(tx, "tasks")
            case try Modb.tx_get(tx, "tasks", kb).map_error(fn(e) Table.Storage(e) end)
              Some(vb):
                tid = try Table.decode_int_key(kb)
                t = try Json.decode[Task](vb).map_error(fn(e) Table.DecodeValue(e) end)
                p_raw = try Modb.tx_get(tx, "projects", t.project_id.bytes).map_error(fn(e)
                  Table.Storage(e)
                end)
                if p_raw is None
                  return Ok(Some("task ##{tid} references unknown project '#{t.project_id}'"))
                end
              None: Unit
            end
          end
          for kb in Modb.tx_touched_puts(tx, "artifacts")
            case try Modb.tx_get(tx, "artifacts", kb).map_error(fn(e) Table.Storage(e) end)
              Some(vb):
                aid = try Table.decode_text_key(kb)
                a = try Json.decode[Artifact](vb).map_error(fn(e) Table.DecodeValue(e) end)
                t_raw = try Modb.tx_get(tx, "tasks", Table.encode_int_key(a.task_id)).map_error(
                  fn(e) Table.Storage(e) end
                )
                if t_raw is None
                  return Ok(Some("artifact '#{aid}' references unknown task ##{a.task_id}"))
                end
              None: Unit
            end
          end
          return Ok(None)
        end

        all_tasks = try Table.tx_scan(tx, tasks, None, None, 0)
        var ok_projs = Set.empty
        for (tid, t) in all_tasks
          if not ok_projs.has?(t.project_id)
            p_raw = try Modb.tx_get(tx, "projects", t.project_id.bytes).map_error(fn(e)
              Table.Storage(e)
            end)
            if p_raw is None
              return Ok(Some("task ##{tid} references unknown project '#{t.project_id}'"))
            end
            ok_projs = ok_projs.add(t.project_id)
          end
        end
        all_arts = try Table.tx_scan(tx, arts, None, None, 0)
        var ok_tasks = Set.empty
        for (aid, a) in all_arts
          if not ok_tasks.has?(a.task_id)
            t_raw = try Modb.tx_get(tx, "tasks", Table.encode_int_key(a.task_id)).map_error(fn(e)
              Table.Storage(e)
            end)
            if t_raw is None
              return Ok(Some("artifact '#{aid}' references unknown task ##{a.task_id}"))
            end
            ok_tasks = ok_tasks.add(a.task_id)
          end
        end
        Ok(None)
      end
    )
  )
end

fn map_ledger_error(err: Ledger.LedgerError) : WorkbenchError
  case err
    Ledger.InvalidMeta(reason: _): MissingReason
    Ledger.InvariantViolation(name: n, detail: d): InvariantRejected(name: n, detail: d)
    Ledger.TableFailure(Table.UniqueConflict(index: _, value: v)): TaskConflict(detail: v)
    Ledger.TableFailure(Table.Storage(e)): StorageFailed(message: e.to_text)
    Ledger.TableFailure(Table.DecodeValue(e)): StorageFailed(message: e.to_text)
    Ledger.TableFailure(Table.DecodeKey(reason: r)): StorageFailed(message: r)
    Ledger.TableFailure(Table.CorruptIndex(index: idx, reason: r)): StorageFailed(
      message: "corrupt index '#{idx}': #{r}"
    )
    Ledger.SchemaTooNew(found: _, supported: _) | Ledger.InvalidMigration(reason: _) | Ledger
      .AuditCorrupt(reason: _): StorageFailed(message: err.to_text)
  end
end

fn map_table_error(err: Table.TableError) : WorkbenchError
  map_ledger_error(Ledger.TableFailure(err))
end

fn map_grant_error(err: Grants.GrantError) : WorkbenchError
  case err
    Grants.LedgerFailure(le): map_ledger_error(le)
    Grants.GrantNotFound(id: id): GrantMissing(id: id)
    Grants.GrantAlreadyExists(id: _): GrantConflict(detail: err.to_text)
    Grants.InvalidGrant(reason: r): InvalidInput(reason: r)
    Grants.WideningDenied(field: _, detail: _) | Grants.Revoked(id: _, revoked_ancestor: _) | Grants
      .Expired(id: _, expired_ancestor: _) | Grants.ActionDenied(id: _, action: _) | Grants
      .BudgetExhausted(id: _, ancestor_id: _, max_calls: _): GrantDenied(detail: err.to_text)
  end
end

fn map_claim_error(err: Claims.ClaimError) : WorkbenchError
  case err
    Claims.LedgerFailure(le): map_ledger_error(le)
    Claims.InvalidClaim(reason: r): InvalidInput(reason: r)
    Claims.AlreadyClaimed(resource: _, holder: _, expires_at: _): ClaimConflict(detail: err.to_text)
    Claims.ClaimNotFound(resource: res): ClaimMissing(resource: res)
    Claims.NotHolder(resource: _, expected: _, actual: _): Forbidden(required: err.to_text)
  end
end

fn map_world_error(err: World.WorldError) : WorkbenchError
  case err
    World.LedgerFailure(le): map_ledger_error(le)
    World.GrantFailure(ge): map_grant_error(ge)
    World.WorldNotFound(id: id): WorldMissing(id: id)
    World.UnknownQuery(name: _) | World.UnknownAction(name: _) | World.QueryFailed(
      query: _,
      detail: _
    ): InvalidInput(reason: err.to_text)
    World.InvariantRejected(name: n, detail: d): InvariantRejected(name: n, detail: d)
    World.WorldAlreadyExists(id: _) | World.WorldNotOpen(id: _, status: _) | World.WorldExpired(
      id: _
    ) | World.ActionRejected(action: _, detail: _) | World.StaleRead(
      query: _,
      args: _,
      expected: _,
      actual: _
    ): WorldConflict(detail: err.to_text)
  end
end

fn map_export_error(err: Export.ExportError) : WorkbenchError
  case err
    Export.LedgerFailure(le): map_ledger_error(le)
    Export.StorageFailure(_) | Export.UnsupportedFormat(found: _, supported: _) | Export
      .InvalidEncoding(bucket: _, detail: _) | Export.ChecksumMismatch(expected: _, actual: _) | Export
      .TargetNotEmpty(path: _): StorageFailed(message: err.to_text)
  end
end

fn map_replay_error(err: Replay.ReplayError) : WorkbenchError
  case err
    Replay.LedgerFailure(le): map_ledger_error(le)
    Replay.ExportFailure(ee): map_export_error(ee)
    Replay.GrantFailure(ge): map_grant_error(ge)
    Replay.ProposalNotFound(id: id): ProposalMissing(id: id)
    Replay.ProposalAlreadyExists(id: _) | Replay.ProposalNotPending(id: _, status: _) | Replay
      .ProposalStale(
        id: _,
        expected_audit_seq: _,
        actual_audit_seq: _,
        expected_call_seq: _,
        actual_call_seq: _
      ): ProposalConflict(detail: err.to_text)
    Replay.UnknownReplayAction(action: _, schema_version: _) | Replay.MissingReplayMigration(
      version: _
    ) | Replay.ReplayActionRejected(action: _, detail: _) | Replay.ReplayFailed(detail: _): InvalidInput(
      reason: err.to_text
    )
  end
end

## Action handler for `create_project`.
fn action_create_project() : fn(Modb.WriteTx, Json) : Result((Modb.WriteTx, Json), Text)
  projs = projects_table()
  fn(tx, args)
    body = try Json.decode[ProjectInput](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
    return Error("project id cannot be empty") if body.id.trim.empty?
    return Error("project name cannot be empty") if body.name.trim.empty?
    return Error("budget_cents must be >= 0") if body.budget_cents < 0
    existing_opt = try Table.tx_get(tx, projs, body.id).map_error(fn(e) e.to_text end)
    spent = case existing_opt
      Some(p): p.spent_cents
      None: 0
    end
    proj = Project(
      name: body.name,
      budget_cents: body.budget_cents,
      spent_cents: spent,
      active: true
    )
    t1 = try Table.put(tx, projs, body.id, proj).map_error(fn(e) e.to_text end)
    Ok((t1, project_to_row(body.id, proj).to_json))
  end
end

## Action handler for `create_task`.
fn action_create_task() : fn(Modb.WriteTx, Json) : Result((Modb.WriteTx, Json), Text)
  projs = projects_table()
  tasks = tasks_table()
  fn(tx, args)
    body = try Json.decode[CreateTaskInput](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
    return Error("task id must be > 0") if body.id <= 0
    return Error("title cannot be empty") if body.title.trim.empty?
    return Error("base_cost_cents must be >= 0") if body.base_cost_cents < 0
    if (try Table.tx_get(tx, projs, body.project_id).map_error(fn(e) e.to_text end)) is None
      return Error("project '#{body.project_id}' not found")
    end
    if (try Table.tx_get(tx, tasks, body.id).map_error(fn(e) e.to_text end)) is Some(_)
      return Error("task ##{body.id} already exists")
    end
    task = Task(
      project_id: body.project_id,
      title: body.title,
      assignee: None,
      base_cost_cents: body.base_cost_cents,
      billed_cents: 0,
      status: Open
    )
    t1 = try Table.put(tx, tasks, body.id, task).map_error(fn(e) e.to_text end)
    Ok((t1, task_to_row(body.id, task).to_json))
  end
end

## Action handler for `complete_task`, parameterized by billing overhead % (default 10%, overridable in Replay).
fn action_complete_task(overhead_pct: Int) : fn(Modb.WriteTx, Json) : Result(
  (Modb.WriteTx, Json),
  Text
)
  projs = projects_table()
  tasks = tasks_table()
  arts = artifacts_table()
  fn(tx, args)
    body = try Json.decode[CompleteTaskInput](Json.encode(args).bytes).map_error(fn(e)
      e.to_text
    end)
    return Error("assignee cannot be empty") if body.assignee.trim.empty?
    task_opt = try Table.tx_get(tx, tasks, body.task_id).map_error(fn(e) e.to_text end)
    task = try task_opt.or_fail("task ##{body.task_id} not found")
    case task.status
      Done | Cancelled: return Error(
        "task ##{body.task_id} already finalized (#{task_status_label(task.status)})"
      )
      Open | InProgress: Unit
    end
    proj_opt = try Table.tx_get(tx, projs, task.project_id).map_error(fn(e) e.to_text end)
    proj = try proj_opt.or_fail("project '#{task.project_id}' not found")
    billed = calc_billed_cents(task.base_cost_cents, overhead_pct)
    remaining = proj.budget_cents - proj.spent_cents
    if billed > remaining
      return Error(
        "budget exceeded on '#{task.project_id}': need #{billed}c, remaining #{remaining}c"
      )
    end
    var next_proj = proj
    next_proj.spent_cents += billed
    var next_task = task
    next_task.assignee = Some(body.assignee)
    next_task.billed_cents = billed
    next_task.status = Done
    t1 = try Table.put(tx, projs, task.project_id, next_proj).map_error(fn(e) e.to_text end)
    t2 = try Table.put(t1, tasks, body.task_id, next_task).map_error(fn(e) e.to_text end)
    t3 = case (body.artifact_id, body.artifact_summary, body.artifact_sha256)
      (Some(aid), Some(sum), Some(sha)): try Table.put(
        t2,
        arts,
        aid,
        Artifact(task_id: body.task_id, author: body.assignee, summary: sum, sha256: sha)
      ).map_error(fn(e) e.to_text end)
      _: t2
    end
    Ok((t3, task_to_row(body.task_id, next_task).to_json))
  end
end

## Approved query & write action catalog exposed to speculative multi-agent Worlds.
## Includes both fine-grained queries (`get_task`, `get_project`) and a coarse query
## (`list_project_tasks`) so real workloads can directly measure needless send-back rates!
fn workbench_catalog() : World.Catalog
  projs = projects_table()
  tasks = tasks_table()
  p_idx = tasks_by_project_index()
  World.catalog().with_query(
    "get_project",
    fn(tx, args)
      pid = try Json.decode[Text](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      p_opt = try Table.tx_get(tx, projs, pid).map_error(fn(e) e.to_text end)
      proj = try p_opt.or_fail("project '#{pid}' not found")
      Ok(project_to_row(pid, proj).to_json)
    end
  ).with_query(
    "get_task",
    fn(tx, args)
      tid = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      t_opt = try Table.tx_get(tx, tasks, tid).map_error(fn(e) e.to_text end)
      t = try t_opt.or_fail("task ##{tid} not found")
      Ok(task_to_row(tid, t).to_json)
    end
  ).with_query(
    "list_project_tasks",
    fn(tx, args)
      pid = try Json.decode[Text](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      rows = try Table.tx_lookup(tx, tasks, p_idx, pid).map_error(fn(e) e.to_text end)
      Ok(rows.map(fn(p) task_to_row(p.0, p.1) end).to_json)
    end
  ).with_action("create_project", action_create_project()).with_action(
    "create_task",
    action_create_task()
  ).with_action("complete_task", action_complete_task(default_overhead_pct()))
end

fn workbench_replay_catalog(overhead_override: Option(Int)) : Replay.ReplayCatalog
  base = Replay.catalog().with_action("create_project", action_create_project()).with_action(
    "create_task",
    action_create_task()
  ).with_action("complete_task", action_complete_task(default_overhead_pct()))
  case overhead_override
    Some(pct): Replay.with_override_action(base, "complete_task", action_complete_task(pct))
    None: base
  end
end

fn authenticate(req: Api.Request, env: Env) : Result(Caller, WorkbenchError)
  token = (req.bearer_token or "").trim
  return Error(Unauthenticated) if token.empty?
  admin_tok = env.get("WB_ADMIN_TOKEN") or "wb-admin"
  planner_tok = env.get("WB_PLANNER_TOKEN") or "wb-planner"
  worker_tok = env.get("WB_WORKER_TOKEN") or "wb-worker"
  reason = req.header("X-Reason")
  agent_hdr = (req.header("X-Agent-Id") or "").trim
  if token == admin_tok
    Ok(Caller(principal: "admin:lead", role: Admin, reason: reason))
  else if token == planner_tok
    who = if agent_hdr.empty?: "agent:planner" else: agent_hdr
    Ok(Caller(principal: who, role: Planner, reason: reason))
  else if token == worker_tok
    who = if agent_hdr.empty?: "agent:worker" else: agent_hdr
    Ok(Caller(principal: who, role: Worker, reason: reason))
  else
    Error(Unauthenticated)
  end
end

fn write_meta(caller: Caller, action: Text, clock: Clock) : Result(Ledger.WriteMeta, WorkbenchError)
  reason = (caller.reason or "").trim
  return Error(MissingReason) if reason.empty?
  Ok(Ledger.WriteMeta(principal: caller.principal, action: action, reason: reason, at: clock.now))
end

fn require_admin(caller: Caller) : Result(Unit, WorkbenchError)
  case caller.role
    Admin: Ok(Unit)
    Planner | Worker: Error(Forbidden(required: "admin role"))
  end
end

fn require_planner_or_admin(caller: Caller) : Result(Unit, WorkbenchError)
  case caller.role
    Admin | Planner: Ok(Unit)
    Worker: Error(Forbidden(required: "admin or planner role"))
  end
end

fn get_health(rf: ReadFiles) : Result(HealthResponse, WorkbenchError)
  if not rf.exists?(db_path())
    return Ok(
      HealthResponse(
        status: "uninitialized",
        txid: 0,
        schema_version: 0,
        audit_count: 0,
        call_count: 0
      )
    )
  end
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      cc = try Replay.call_count(Ledger.store(db)).map_error(map_replay_error)
      Ok(
        HealthResponse(
          status: "ok",
          txid: Ledger.txid(db),
          schema_version: Ledger.schema_version(db),
          audit_count: Ledger.audit_count(db),
          call_count: cc
        )
      )
    end
  )
end

fn post_admin_init(caller: Caller, files: Files, clock: Clock) : Result(
  HealthResponse,
  WorkbenchError
)
  try require_admin(caller)
  (cur_txid, st) = try Ledger.init_locked(files, db_path(), workbench_schema(), clock.now).map_error(
    map_ledger_error
  )
  Ok(
    HealthResponse(
      status: "ok",
      txid: cur_txid,
      schema_version: st.version,
      audit_count: st.next_audit_seq - 1,
      call_count: 0
    )
  )
end

fn post_project(caller: Caller, files: Files, clock: Clock, body: ProjectInput) : Result(
  ProjectRow,
  WorkbenchError
)
  try require_admin(caller)
  return Error(InvalidInput(reason: "project id cannot be empty")) if body.id.trim.empty?
  return Error(InvalidInput(reason: "project name cannot be empty")) if body.name.trim.empty?
  meta = try write_meta(caller, "create_project", clock)
  projs = projects_table()
  Ledger.locked(
    files,
    db_path(),
    workbench_schema(),
    meta.at,
    map_ledger_error,
    fn(db)
      sc_ver = Ledger.schema_version(db)
      aseq = db.state.next_audit_seq
      (_next, row) = try Ledger.transact(
        db,
        meta,
        "upsert project '#{body.id}' (budget=#{body.budget_cents}c)",
        body.to_json,
        map_ledger_error,
        fn(tx)
          ex_opt = try Table.tx_get(tx, projs, body.id).map_error(map_table_error)
          spent = case ex_opt
            Some(p): p.spent_cents
            None: 0
          end
          proj = Project(
            name: body.name,
            budget_cents: body.budget_cents,
            spent_cents: spent,
            active: true
          )
          row = project_to_row(body.id, proj)
          t1 = try Table.put(tx, projs, body.id, proj).map_error(map_table_error)
          (t2, _rec) = try Replay.tx_record_call(
            t1,
            sc_ver,
            Some(aseq),
            meta.principal,
            None,
            [],
            None,
            "create_project",
            body.to_json,
            meta.reason,
            meta.at,
            Replay.OrigOk(reply: row.to_json)
          ).map_error(map_table_error)
          Ok((t2, row))
        end
      )
      Ok(row)
    end
  )
end

fn list_projects(rf: ReadFiles) : Result(List(ProjectRow), WorkbenchError)
  projs = projects_table()
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      rows = try Table.all(Ledger.store(db), projs).map_error(map_table_error)
      Ok(rows.map(fn(p) project_to_row(p.0, p.1) end))
    end
  )
end

fn get_project(rf: ReadFiles, id: Text) : Result(ProjectRow, WorkbenchError)
  projs = projects_table()
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      p_opt = try Table.get(Ledger.store(db), projs, id).map_error(map_table_error)
      proj = try p_opt.or_fail(ProjectMissing(id: id))
      Ok(project_to_row(id, proj))
    end
  )
end

fn get_project_tasks(rf: ReadFiles, id: Text) : Result(List(TaskRow), WorkbenchError)
  projs = projects_table()
  tasks = tasks_table()
  idx = tasks_by_project_index()
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      if (try Table.get(Ledger.store(db), projs, id).map_error(map_table_error)) is None
        return Error(ProjectMissing(id: id))
      end
      rows = try Table.lookup(Ledger.store(db), tasks, idx, id).map_error(map_table_error)
      Ok(rows.map(fn(p) task_to_row(p.0, p.1) end))
    end
  )
end

fn post_task(caller: Caller, files: Files, clock: Clock, body: CreateTaskInput) : Result(
  TaskRow,
  WorkbenchError
)
  try require_planner_or_admin(caller)
  return Error(InvalidInput(reason: "task id must be > 0")) if body.id <= 0
  return Error(InvalidInput(reason: "title cannot be empty")) if body.title.trim.empty?
  meta = try write_meta(caller, "create_task", clock)
  projs = projects_table()
  tasks = tasks_table()
  Ledger.locked(
    files,
    db_path(),
    workbench_schema(),
    meta.at,
    map_ledger_error,
    fn(db)
      sc_ver = Ledger.schema_version(db)
      aseq = db.state.next_audit_seq
      (_next, row) = try Ledger.transact(
        db,
        meta,
        "create task ##{body.id} on '#{body.project_id}'",
        body.to_json,
        map_ledger_error,
        fn(tx)
          if (try Table.tx_get(tx, projs, body.project_id).map_error(map_table_error)) is None
            return Error(ProjectMissing(id: body.project_id))
          end
          if (try Table.tx_get(tx, tasks, body.id).map_error(map_table_error)) is Some(_)
            return Error(TaskConflict(detail: "task ##{body.id} already exists"))
          end
          t = Task(
            project_id: body.project_id,
            title: body.title,
            assignee: None,
            base_cost_cents: body.base_cost_cents,
            billed_cents: 0,
            status: Open
          )
          row = task_to_row(body.id, t)
          t1 = try Table.put(tx, tasks, body.id, t).map_error(map_table_error)
          (t2, _rec) = try Replay.tx_record_call(
            t1,
            sc_ver,
            Some(aseq),
            meta.principal,
            None,
            [],
            None,
            "create_task",
            body.to_json,
            meta.reason,
            meta.at,
            Replay.OrigOk(reply: row.to_json)
          ).map_error(map_table_error)
          Ok((t2, row))
        end
      )
      Ok(row)
    end
  )
end

fn get_task(rf: ReadFiles, id: Int) : Result(TaskRow, WorkbenchError)
  tasks = tasks_table()
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      t_opt = try Table.get(Ledger.store(db), tasks, id).map_error(map_table_error)
      t = try t_opt.or_fail(TaskMissing(id: id))
      Ok(task_to_row(id, t))
    end
  )
end

fn post_complete_task(caller: Caller, files: Files, clock: Clock, id: Int, body: CompleteTaskInput) : Result(
  TaskRow,
  WorkbenchError
)
  return Error(InvalidInput(reason: "task_id mismatch")) if body.task_id != id
  return Error(InvalidInput(reason: "assignee cannot be empty")) if body.assignee.trim.empty?
  meta = try write_meta(caller, "complete_task", clock)
  projs = projects_table()
  tasks = tasks_table()
  arts = artifacts_table()
  Ledger.locked(
    files,
    db_path(),
    workbench_schema(),
    meta.at,
    map_ledger_error,
    fn(db)
      sc_ver = Ledger.schema_version(db)
      aseq = db.state.next_audit_seq
      res = Ledger.transact(
        db,
        meta,
        "complete task ##{id} by #{body.assignee}",
        body.to_json,
        map_ledger_error,
        fn(tx)
          t_opt = try Table.tx_get(tx, tasks, id).map_error(map_table_error)
          task = try t_opt.or_fail(TaskMissing(id: id))
          case task.status
            Done | Cancelled: return Error(TaskConflict(detail: "task ##{id} already finalized"))
            Open | InProgress: Unit
          end
          p_opt = try Table.tx_get(tx, projs, task.project_id).map_error(map_table_error)
          proj = try p_opt.or_fail(ProjectMissing(id: task.project_id))
          billed = calc_billed_cents(task.base_cost_cents, default_overhead_pct())
          rem = proj.budget_cents - proj.spent_cents
          if billed > rem
            return Error(
              BudgetExceeded(project_id: task.project_id, needed: billed, remaining: rem)
            )
          end
          var next_proj = proj
          next_proj.spent_cents += billed
          var next_task = task
          next_task.assignee = Some(body.assignee)
          next_task.billed_cents = billed
          next_task.status = Done
          row = task_to_row(id, next_task)
          t1 = try Table.put(tx, projs, task.project_id, next_proj).map_error(map_table_error)
          t2 = try Table.put(t1, tasks, id, next_task).map_error(map_table_error)
          t3 = case (body.artifact_id, body.artifact_summary, body.artifact_sha256)
            (Some(aid), Some(sum), Some(sha)): try Table.put(
              t2,
              arts,
              aid,
              Artifact(task_id: id, author: body.assignee, summary: sum, sha256: sha)
            ).map_error(map_table_error)
            _: t2
          end
          (t4, _rec) = try Replay.tx_record_call(
            t3,
            sc_ver,
            Some(aseq),
            meta.principal,
            None,
            [],
            None,
            "complete_task",
            body.to_json,
            meta.reason,
            meta.at,
            Replay.OrigOk(reply: row.to_json)
          ).map_error(map_table_error)
          Ok((t4, row))
        end
      )
      case res
        Ok((_next, row)): Ok(row)
        Error(BudgetExceeded(project_id: pid, needed: need, remaining: rem)):
          _ = try Replay.record_refused(
            db,
            meta.principal,
            None,
            [],
            None,
            "complete_task",
            body.to_json,
            meta.reason,
            meta.at,
            "budget exceeded on '#{pid}': need #{need}c, remaining #{rem}c"
          ).map_error(map_replay_error)
          Error(BudgetExceeded(project_id: pid, needed: need, remaining: rem))
        Error(other): Error(other)
      end
    end
  )
end

fn get_task_artifacts(rf: ReadFiles, id: Int) : Result(List(ArtifactRow), WorkbenchError)
  arts = artifacts_table()
  idx = artifacts_by_task_index()
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      rows = try Table.lookup(Ledger.store(db), arts, idx, id).map_error(map_table_error)
      Ok(
        rows.map(fn(p)
          ArtifactRow(
            id: p.0,
            task_id: p.1.task_id,
            author: p.1.author,
            summary: p.1.summary,
            sha256: p.1.sha256
          )
        end)
      )
    end
  )
end

fn post_grant(caller: Caller, files: Files, clock: Clock, body: GrantInput) : Result(
  Grants.Grant,
  WorkbenchError
)
  try require_admin(caller)
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  meta = try write_meta(caller, "issue_grant", clock)
  spec = Grants.GrantSpec(
    id: body.id,
    principal: body.principal,
    allowed_actions: body.allowed_actions,
    max_calls: body.max_calls,
    expires_at: clock.now + 1.second * body.ttl_seconds
  )
  Grants.issue_root_locked(files, db_path(), workbench_schema(), meta, spec).map_error(
    map_grant_error
  )
end

fn get_grant(rf: ReadFiles, id: Text) : Result(Grants.Grant, WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      g_opt = try Grants.get(Ledger.store(db), id).map_error(map_grant_error)
      g_opt.or_fail(GrantMissing(id: id))
    end
  )
end

fn post_delegate_grant(caller: Caller, files: Files, clock: Clock, id: Text, body: GrantInput) : Result(
  Grants.Grant,
  WorkbenchError
)
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  meta = try write_meta(caller, "delegate_grant", clock)
  spec = Grants.GrantSpec(
    id: body.id,
    principal: body.principal,
    allowed_actions: body.allowed_actions,
    max_calls: body.max_calls,
    expires_at: clock.now + 1.second * body.ttl_seconds
  )
  Grants.delegate_locked(files, db_path(), workbench_schema(), meta, id, spec).map_error(
    map_grant_error
  )
end

fn post_revoke_grant(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Grants.Grant,
  WorkbenchError
)
  try require_admin(caller)
  meta = try write_meta(caller, "revoke_grant", clock)
  Grants.revoke_locked(files, db_path(), workbench_schema(), meta, id).map_error(map_grant_error)
end

fn post_claim(caller: Caller, files: Files, clock: Clock, body: ClaimInput) : Result(
  Claims.Claim,
  WorkbenchError
)
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  meta = try write_meta(caller, "acquire_claim", clock)
  exp = clock.now + 1.second * body.ttl_seconds
  Claims.acquire_locked(
    files,
    db_path(),
    workbench_schema(),
    meta,
    body.resource,
    body.grant_id,
    body.world_id,
    exp
  ).map_error(map_claim_error)
end

fn list_claims(rf: ReadFiles, clock: Clock) : Result(List(Claims.Claim), WorkbenchError)
  now = clock.now
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) Claims.list_active(Ledger.store(db), now).map_error(map_claim_error) end
  )
end

fn post_claim_heartbeat(
  caller: Caller,
  files: Files,
  clock: Clock,
  resource: Text,
  body: HeartbeatInput
) : Result(Claims.Claim, WorkbenchError)
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  meta = try write_meta(caller, "heartbeat_claim", clock)
  exp = clock.now + 1.second * body.ttl_seconds
  Claims.heartbeat_locked(files, db_path(), workbench_schema(), meta, resource, exp).map_error(
    map_claim_error
  )
end

fn delete_claim(caller: Caller, files: Files, clock: Clock, resource: Text) : Result(
  OkStatus,
  WorkbenchError
)
  meta = try write_meta(caller, "release_claim", clock)
  _ = try Claims.release_locked(files, db_path(), workbench_schema(), meta, resource).map_error(
    map_claim_error
  )
  Ok(OkStatus(ok: true))
end

fn post_world(caller: Caller, files: Files, clock: Clock, body: WorldOpenInput) : Result(
  World.WorldRecord,
  WorkbenchError
)
  _ = caller
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  now = clock.now
  exp = now + 1.second * body.ttl_seconds
  World.open_world_locked(files, db_path(), workbench_schema(), body.id, body.grant_id, now, exp)
    .map_error(map_world_error)
end

fn get_world_metrics(rf: ReadFiles) : Result(World.LandingMetrics, WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) World.metrics(Ledger.store(db)).map_error(map_world_error) end
  )
end

fn post_world_query(caller: Caller, files: Files, clock: Clock, id: Text, body: WorldQueryInput) : Result(
  Json,
  WorkbenchError
)
  _ = caller
  World.world_query_locked(
    files,
    db_path(),
    workbench_schema(),
    workbench_catalog(),
    id,
    body.query,
    body.args,
    clock.now
  ).map_error(map_world_error)
end

fn post_world_call(caller: Caller, files: Files, clock: Clock, id: Text, body: WorldCallInput) : Result(
  Json,
  WorkbenchError
)
  reason = (caller.reason or "").trim
  return Error(MissingReason) if reason.empty?
  World.world_call_locked(
    files,
    db_path(),
    workbench_schema(),
    workbench_catalog(),
    id,
    body.action,
    body.args,
    reason,
    clock.now
  ).map_error(map_world_error)
end

fn get_world_diff(rf: ReadFiles, id: Text) : Result(List(World.BucketDiffSummary), WorkbenchError)
  World.world_diff_locked(rf, db_path(), workbench_schema(), workbench_catalog(), id).map_error(
    map_world_error
  )
end

fn post_world_land(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  World.LandResult,
  WorkbenchError
)
  reason = (caller.reason or "").trim
  return Error(MissingReason) if reason.empty?
  World.land_world_locked(
    files,
    db_path(),
    workbench_schema(),
    workbench_catalog(),
    id,
    reason,
    clock.now
  ).map_error(map_world_error)
end

fn delete_world(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  OkStatus,
  WorkbenchError
)
  _ = caller
  _ = try World.drop_world_locked(files, db_path(), workbench_schema(), id, clock.now).map_error(
    map_world_error
  )
  Ok(OkStatus(ok: true))
end

fn get_audit(
  rf: ReadFiles,
  principal: Option(Text),
  action: Option(Text),
  since: Option(Int),
  limit: Option(Int)
) : Result(List(Ledger.AuditEntry), WorkbenchError)
  cap = limit or 50
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      entries = case (principal, action, since)
        (Some(who), _, _): try Ledger.audit_by_principal(db, who).map_error(map_ledger_error)
        (None, Some(act), _): try Ledger.audit_by_action(db, act).map_error(map_ledger_error)
        (None, None, Some(s)): try Ledger.audit_since(db, s, cap).map_error(map_ledger_error)
        (None, None, None): try Ledger.audit_tail(db, cap).map_error(map_ledger_error)
      end
      if cap > 0 and entries.size > cap
        Ok(entries.drop(entries.size - cap))
      else
        Ok(entries)
      end
    end
  )
end

fn get_admin_verify(rf: ReadFiles) : Result(VerifySummary, WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      rep = try Ledger.verify_all(db).map_error(map_ledger_error)
      Ok(
        VerifySummary(
          ok: true,
          txid: rep.storage.txid,
          page_count: rep.storage.page_count,
          bucket_count: rep.storage.bucket_count,
          schema_version: rep.audit.schema_version,
          audit_entries: rep.audit.entry_count,
          last_audit_hash: rep.audit.last_hash,
          invariants_checked: rep.invariants_checked
        )
      )
    end
  )
end

fn get_admin_export(rf: ReadFiles, clock: Clock, include_internal: Option(Bool)) : Result(
  Api.Response,
  WorkbenchError
)
  inc = include_internal or true
  snap = try Export.export_locked(rf, db_path(), workbench_schema(), inc, clock.now).map_error(
    map_export_error
  )
  Ok(
    Api.response(
      200,
      [("content-type", "application/json")],
      Export.encode_snapshot_json(snap).bytes
    )
  )
end

fn get_replay_calls(rf: ReadFiles) : Result(List(Replay.CallRecord), WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) Replay.list_calls(Ledger.store(db)).map_error(map_replay_error) end
  )
end

fn post_replay_simulate(caller: Caller, files: Files, clock: Clock, body: ReplaySimulateInput) : Result(
  Replay.ReplayProposal,
  WorkbenchError
)
  try require_admin(caller)
  case body.overhead_pct_override
    Some(pct):
      if pct < 0 or pct > 100
        return Error(InvalidInput(reason: "overhead_pct_override must be in 0..100"))
      end
    None: Unit
  end
  flt = case (
    body.exclude_principal,
    body.exclude_grant,
    body.exclude_world,
    body.exclude_seqs,
    body.stop_before_seq
  )
    (Some(p), _, _, _, _): Replay.ExcludePrincipal(principal: p)
    (None, Some(g), _, _, _): Replay.ExcludeGrant(grant_id: g)
    (None, None, Some(w), _, _): Replay.ExcludeWorld(world_id: w)
    (None, None, None, Some(seqs), _): Replay.ExcludeSeqs(seqs: seqs)
    (None, None, None, None, Some(s)): Replay.StopBeforeSeq(seq: s)
    (None, None, None, None, None): Replay.ReplayAll
  end
  rc = workbench_replay_catalog(body.overhead_pct_override)
  Replay.simulate_replay_locked(
    files,
    db_path(),
    workbench_schema(),
    rc,
    flt,
    body.proposal_id,
    body.description,
    caller.principal,
    clock.now
  ).map_error(map_replay_error)
end

fn list_replay_proposals(rf: ReadFiles) : Result(List(Replay.ReplayProposal), WorkbenchError)
  Replay.list_proposals_locked(rf, db_path(), workbench_schema()).map_error(map_replay_error)
end

fn get_replay_proposal(rf: ReadFiles, id: Text) : Result(Replay.ReplayProposal, WorkbenchError)
  opt = try Replay.get_proposal_locked(rf, db_path(), workbench_schema(), id).map_error(
    map_replay_error
  )
  opt.or_fail(ProposalMissing(id: id))
end

fn post_replay_accept(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Replay.ReplayProposal,
  WorkbenchError
)
  try require_admin(caller)
  meta = try write_meta(caller, "accept_replay_proposal", clock)
  Replay.accept_proposal_locked(files, db_path(), workbench_schema(), id, meta).map_error(
    map_replay_error
  )
end

fn delete_replay_proposal(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Replay.ReplayProposal,
  WorkbenchError
)
  try require_admin(caller)
  Replay.discard_proposal_locked(
    files,
    db_path(),
    workbench_schema(),
    id,
    caller.principal,
    clock.now
  ).map_error(map_replay_error)
end

test "AgentWorkbench end-to-end via ApiTest.send: Grants, Claims, Worlds, Rogue undo replay & overhead fix"
  files = Files.in_memory({})
  ro = files.read_only
  t0 = Time.parse("2026-11-25T18:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  env = Env.of({
    "WB_ADMIN_TOKEN": "tok-admin",
    "WB_PLANNER_TOKEN": "tok-planner",
    "WB_WORKER_TOKEN": "tok-worker"
  })

  ## 1. Init DB + create 2 tasks on `infra` ($500 = 50000c budget)
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/admin/init").with_bearer("tok-admin"),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/tasks").with_bearer("tok-planner").with_header("X-Reason", "plan-1").with_json(
      CreateTaskInput(id: 1, project_id: "infra", title: "Rogue bloat job", base_cost_cents: 40000)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/tasks").with_bearer("tok-planner").with_header("X-Reason", "plan-2").with_json(
      CreateTaskInput(
        id: 2,
        project_id: "infra",
        title: "Critical SRE patch",
        base_cost_cents: 10000
      )
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  ## 2. Issue root grant `g-team` -> delegate `g-rogue-sub`; rogue completes task #1 (44000c billed!)
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/grants").with_bearer("tok-admin").with_header("X-Reason", "team-grant").with_json(
      GrantInput(
        id: "g-team",
        principal: "agent:lead",
        allowed_actions: ["create_task", "complete_task"],
        max_calls: 20,
        ttl_seconds: 3600
      )
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/grants/g-team/delegate").with_bearer("tok-planner").with_header("X-Reason", "sub")
      .with_json(
        GrantInput(
          id: "g-rogue-sub",
          principal: "agent:rogue",
          allowed_actions: ["complete_task"],
          max_calls: 5,
          ttl_seconds: 1800
        )
      ),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds").with_bearer("tok-worker").with_json(
      WorldOpenInput(id: "w-rogue", grant_id: "g-rogue-sub", ttl_seconds: 600)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-rogue/call").with_bearer("tok-worker").with_header("X-Reason", "run-bloat")
      .with_json(
        WorldCallInput(
          action: "complete_task",
          args: CompleteTaskInput(
            task_id: 1,
            assignee: "agent:rogue",
            artifact_id: Some("art-rogue"),
            artifact_summary: Some("junk output"),
            artifact_sha256: Some("deadbeef")
          ).to_json
        )
      ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-rogue/land").with_bearer("tok-worker").with_header("X-Reason", "land"),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  ## 3. Legitimate SRE tries to complete task #2 (needs 11000c, only 6000c left) -> 409 BudgetExceeded!
  sre_refused = ApiTest.send(
    AgentWorkbench,
    Api.post("/tasks/2/complete").with_bearer("tok-worker").with_header("X-Agent-Id", "agent:sre")
      .with_header("X-Reason", "sre-patch").with_json(
        CompleteTaskInput(
          task_id: 2,
          assignee: "agent:sre",
          artifact_id: Some("art-sre"),
          artifact_summary: Some("patched outage"),
          artifact_sha256: Some("cafebabe")
        )
      ),
    files,
    ro,
    clock,
    env
  )
  assert sre_refused.status == 409

  ## 4. Admin simulates excluding `g-rogue-sub` -> task #2 flips to NowAccepted!
  sim = ApiTest.send(
    AgentWorkbench,
    Api.post("/admin/replay/simulate").with_bearer("tok-admin").with_json(
      ReplaySimulateInput(
        proposal_id: "excise-rogue",
        description: "Excise rogue sub-agent and unblock SRE task",
        exclude_principal: None,
        exclude_grant: Some("g-rogue-sub"),
        exclude_world: None,
        exclude_seqs: None,
        stop_before_seq: None,
        overhead_pct_override: None
      )
    ),
    files,
    ro,
    clock,
    env
  )
  assert sim.status == 200
  assert Json.decode_strict[Replay.ReplayProposal](sim.text) is Ok(prop)
  assert prop.summary.excluded == 1 and prop.summary.now_accepted == 1

  ## Accept proposal -> task #2 Done (11000c billed), task #1 back to Open, rogue artifact gone!
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/admin/replay/proposals/excise-rogue/accept").with_bearer("tok-admin").with_header(
      "X-Reason",
      "approve rogue excision"
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(AgentWorkbench, Api.get("/projects/infra"), files, ro, clock, env) is infra_r
  assert Json.decode_strict[ProjectRow](infra_r.text) is Ok(infra_p)
  assert infra_p.spent_cents == 11000 and infra_p.remaining_cents == 39000

  ## 5. Bug-fix replay: remove the 10% overhead billing bug (override to 0%) -> infra spent = 10000c!
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/admin/replay/simulate").with_bearer("tok-admin").with_json(
      ReplaySimulateInput(
        proposal_id: "fix-overhead",
        description: "Remove 10% overhead billing bug",
        exclude_principal: None,
        exclude_grant: Some("g-rogue-sub"),
        exclude_world: None,
        exclude_seqs: None,
        stop_before_seq: None,
        overhead_pct_override: Some(0)
      )
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/admin/replay/proposals/fix-overhead/accept").with_bearer("tok-admin").with_header(
      "X-Reason",
      "apply 0% overhead fix"
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  infra2 = ApiTest.send(AgentWorkbench, Api.get("/projects/infra"), files, ro, clock, env)
  assert Json.decode_strict[ProjectRow](infra2.text) is Ok(ip2)
  assert ip2.spent_cents == 10000 and ip2.remaining_cents == 40000

  ## Verify full ledger & portable export round-trip
  ver = ApiTest.send(AgentWorkbench, Api.get("/admin/verify"), files, ro, clock, env)
  assert ver.status == 200 and Json.decode_strict[VerifySummary](ver.text) is Ok(vs) and vs.ok
  exp = ApiTest.send(AgentWorkbench, Api.get("/admin/export"), files, ro, clock, env)
  assert exp.status == 200 and Json.decode_strict[Export.PortableSnapshot](exp.text) is Ok(snap)
  assert Export.verify_snapshot(snap) is Ok(_)
end
