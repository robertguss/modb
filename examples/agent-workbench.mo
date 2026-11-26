## Milestone 6: Real-World Multi-Agent Engineering & Operations Workbench (`AgentWorkbench`)
## Exercises every MoDB layer end-to-end under `mo serve --workers 8`:
## - Layer 1: CoW B+Tree, persistent root pins, O(diff), lock-free optimistic reads, crash safety
## - Layer 2: Typed tables (`projects`, `tasks`, `artifacts`) with atomic secondary indexes
##            + transactional BM25+ `Modb.Fts` & quantized `Modb.Vec` hybrid search indexes
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
use Modb.Fts
use Modb.Grants
use Modb.Ledger
use Modb.Replay
use Modb.Table
use Modb.Vec
use Modb.Views
use Modb.World
use WorkbenchUi

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
  allowed_views: Option(List(Text))
  allowed_releases: Option(List(Text))
  max_calls: Int
  ttl_seconds: Int
end

struct ReadProgramRequest
  grant_id: Option(Text)
  program: Views.ReadProgram
end

struct ReleaseRequest
  grant_id: Option(Text)
  args: Option(Json)
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

struct TaskRangeInput
  start_id: Option(Int)
  end_id: Option(Int)
  limit: Option(Int)
end

struct ChildWorldOpenInput
  id: Text
  grant_id: Text
  ttl_seconds: Int
end

struct PriorityClaimInput
  buckets: List(Text)
  min_stale_threshold: Option(Int)
  hold_seconds: Int
end

struct WorldTelemetryResponse
  telemetry: World.WorldTelemetry
  active_tickets: List(World.PriorityTicket)
  links: List(World.WorldLink)
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

struct DemoResponse
  ok: Bool
  summary: Text
  txid: Int
end

struct SearchRequest
  query: Text
  mode: Option(Text)
  project_id: Option(Text)
  limit: Option(Int)
  prefix_last_term: Option(Bool)
  vector: Option(List(Float))
end

struct SearchStatsResponse
  fts: Fts.FtsStats
  vec: Vec.VecStats
end

struct SearchResponse
  mode: Text
  query: Text
  project_id: Option(Text)
  hits: List(Vec.HybridHit)
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
  ViewMissing(name: Text)
  ViewFieldBlocked(detail: Text)
  ReleaseBlocked(detail: Text)
  WorkBudgetBlocked(detail: Text)
  StorageFailed(message: Text)
end

api
  port 8092
  cors "*"
  auth Caller via authenticate

  get "/" get_ui
  get "/ui" get_ui
  get "/health" get_health
  get "/describe" get_describe
  post "/views/query" post_view_query
  post "/releases/:name" post_release
  get "/reads" get_reads
  post "/search" post_search
  get "/search/stats" get_search_stats
  post "/mcp" post_mcp

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
    get "" list_grants
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
    get "" list_worlds
    get "/metrics" get_world_metrics
    get "/telemetry" get_world_telemetry
    post "/:id/children" post_world_child
    get "/:id/children" list_world_children
    post "/:id/query" post_world_query
    post "/:id/call" post_world_call
    get "/:id/diff" get_world_diff
    post "/:id/land" post_world_land
    post "/:id/land-fair" post_world_land_fair
    post "/:id/land-child" post_world_land_child
    post "/:id/priority" post_world_priority
    delete "/:id" delete_world
  end

  get "/audit" get_audit
  post "/admin/init" post_admin_init
  post "/admin/demo" post_admin_demo
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
  status ViewMissing(_) = 404
  status ViewFieldBlocked(_) = 403
  status ReleaseBlocked(_) = 403
  status WorkBudgetBlocked(_) = 429
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

fn workbench_fts_index() : Fts.FtsIndex
  Fts.index("workbench")
end

fn workbench_vec_index() : Vec.VecIndex
  Vec.index("workbench", 32)
end

fn wrap_search_table_err(e: Fts.FtsError) : Table.TableError
  case e
    Fts.Storage(me): Table.Storage(me)
    Fts.TableFailure(te): te
    Fts.InvalidConfig(reason: r) | Fts.InvalidDocument(reason: r): Table.DecodeKey(reason: r)
  end
end

fn wrap_vec_table_err(e: Vec.VecError) : Table.TableError
  case e
    Vec.Storage(me): Table.Storage(me)
    Vec.TableFailure(te): te
    Vec.FtsFailure(fe): wrap_search_table_err(fe)
    Vec.InvalidConfig(reason: r) | Vec.InvalidVector(reason: r): Table.DecodeKey(reason: r)
    Vec.DimensionMismatch(expected: exp, actual: act): Table.DecodeKey(
      reason: "vector dimension mismatch: #{exp} vs #{act}"
    )
  end
end

fn tx_index_workbench_task(tx: Modb.WriteTx, task_id: Int, task: Task) : Result(
  Modb.WriteTx,
  Table.TableError
)
  doc_id = "task:#{task_id}"
  asg = task.assignee or ""
  st_label = task_status_label(task.status)
  fdoc = Fts.DocumentInput(
    doc_id: doc_id,
    scope: task.project_id,
    fields: [
      Fts.FieldInput(name: "title", text: task.title, weight: 3),
      Fts.FieldInput(name: "project_id", text: task.project_id, weight: 1),
      Fts.FieldInput(name: "status", text: st_label, weight: 1),
      Fts.FieldInput(name: "assignee", text: asg, weight: 1)
    ]
  )
  t1 = try Fts.tx_index_document(tx, workbench_fts_index(), fdoc).map_error(wrap_search_table_err)
  sketch = Vec.text_sketch_embedding("#{task.title} #{task.project_id} #{st_label} #{asg}", 32)
  Vec.tx_put_vector(
    t1,
    workbench_vec_index(),
    Vec.VectorInput(doc_id: doc_id, scope: task.project_id, values: sketch)
  ).map_error(wrap_vec_table_err)
end

fn tx_index_workbench_artifact(
  tx: Modb.WriteTx,
  art_id: Text,
  project_id: Text,
  art: Artifact
) : Result(Modb.WriteTx, Table.TableError)
  doc_id = "artifact:#{art_id}"
  fdoc = Fts.DocumentInput(
    doc_id: doc_id,
    scope: project_id,
    fields: [
      Fts.FieldInput(name: "summary", text: art.summary, weight: 3),
      Fts.FieldInput(name: "author", text: art.author, weight: 1),
      Fts.FieldInput(name: "id", text: art_id, weight: 1)
    ]
  )
  t1 = try Fts.tx_index_document(tx, workbench_fts_index(), fdoc).map_error(wrap_search_table_err)
  sketch = Vec.text_sketch_embedding("#{art.summary} #{art.author} #{art_id}", 32)
  Vec.tx_put_vector(
    t1,
    workbench_vec_index(),
    Vec.VectorInput(doc_id: doc_id, scope: project_id, values: sketch)
  ).map_error(wrap_vec_table_err)
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

fn map_fts_error(err: Fts.FtsError) : WorkbenchError
  case err
    Fts.Storage(me): StorageFailed(message: me.to_text)
    Fts.TableFailure(te): map_table_error(te)
    Fts.InvalidConfig(reason: r) | Fts.InvalidDocument(reason: r): InvalidInput(reason: r)
  end
end

fn map_vec_error(err: Vec.VecError) : WorkbenchError
  case err
    Vec.Storage(me): StorageFailed(message: me.to_text)
    Vec.TableFailure(te): map_table_error(te)
    Vec.FtsFailure(fe): map_fts_error(fe)
    Vec.InvalidConfig(reason: r) | Vec.InvalidVector(reason: r): InvalidInput(reason: r)
    Vec.DimensionMismatch(expected: _, actual: _): InvalidInput(reason: Vec.to_text(err))
  end
end

fn map_grant_error(err: Grants.GrantError) : WorkbenchError
  case err
    Grants.LedgerFailure(le): map_ledger_error(le)
    Grants.GrantNotFound(id: id): GrantMissing(id: id)
    Grants.GrantAlreadyExists(id: _): GrantConflict(detail: err.to_text)
    Grants.InvalidGrant(reason: r): InvalidInput(reason: r)
    Grants.WideningDenied(field: _, detail: _) | Grants.Revoked(id: _, revoked_ancestor: _) | Grants
      .Expired(id: _, expired_ancestor: _) | Grants.ActionDenied(id: _, action: _) | Grants
      .ViewDenied(id: _, view: _) | Grants.ReleaseDenied(id: _, release: _) | Grants.BudgetExhausted(
        id: _,
        ancestor_id: _,
        max_calls: _
      ): GrantDenied(detail: err.to_text)
  end
end

fn map_views_error(err: Views.ViewsError) : WorkbenchError
  case err
    Views.LedgerFailure(le): map_ledger_error(le)
    Views.GrantFailure(ge): map_grant_error(ge)
    Views.UnknownView(name: n) | Views.UnknownRelease(name: n): ViewMissing(name: n)
    Views.FieldNotInView(view: _, field: _, allowed: _): ViewFieldBlocked(detail: err.to_text)
    Views.InvalidProgram(reason: r): InvalidInput(reason: r)
    Views.WorkBudgetExceeded(metric: _, limit: _): WorkBudgetBlocked(detail: err.to_text)
    Views.ViewLoadFailed(view: _, detail: _) | Views.ReleaseFailed(release: _, detail: _): StorageFailed(
      message: err.to_text
    )
    Views.ReleaseThresholdBlocked(release: _, min_group_size: _, actual_count: _): ReleaseBlocked(
      detail: err.to_text
    )
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
      .TargetNotEmpty(path: _) | Export.PostImportFailed(detail: _): StorageFailed(message: err.to_text)
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
    t2 = try tx_index_workbench_task(t1, body.id, task).map_error(fn(e) e.to_text end)
    Ok((t2, task_to_row(body.id, task).to_json))
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
    t3 = try tx_index_workbench_task(t2, body.task_id, next_task).map_error(fn(e) e.to_text end)
    t4 = case (body.artifact_id, body.artifact_summary, body.artifact_sha256)
      (Some(aid), Some(sum), Some(sha)):
        art = Artifact(task_id: body.task_id, author: body.assignee, summary: sum, sha256: sha)
        ta = try Table.put(t3, arts, aid, art).map_error(fn(e) e.to_text end)
        try tx_index_workbench_artifact(ta, aid, task.project_id, art).map_error(fn(e) e.to_text end)
      _: t3
    end
    Ok((t4, task_to_row(body.task_id, next_task).to_json))
  end
end

## Approved query & write action catalog exposed to speculative multi-agent Worlds.
## Includes key/range O(diff) queries (`get_task`, `get_project`, `scan_tasks_range`) and a
## coarse query (`list_project_tasks`) so real workloads can directly measure needless send-backs!
fn workbench_catalog() : World.Catalog
  projs = projects_table()
  tasks = tasks_table()
  p_idx = tasks_by_project_index()
  World.catalog().with_key_scoped_query(
    "get_project",
    "projects",
    fn(args)
      pid = try Json.decode[Text](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      Ok(Table.encode_text_key(pid))
    end,
    fn(tx, args)
      pid = try Json.decode[Text](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      p_opt = try Table.tx_get(tx, projs, pid).map_error(fn(e) e.to_text end)
      proj = try p_opt.or_fail("project '#{pid}' not found")
      Ok(project_to_row(pid, proj).to_json)
    end
  ).with_key_scoped_query(
    "get_task",
    "tasks",
    fn(args)
      tid = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      Ok(Table.encode_int_key(tid))
    end,
    fn(tx, args)
      tid = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      t_opt = try Table.tx_get(tx, tasks, tid).map_error(fn(e) e.to_text end)
      t = try t_opt.or_fail("task ##{tid} not found")
      Ok(task_to_row(tid, t).to_json)
    end
  ).with_range_scoped_query(
    "scan_tasks_range",
    "tasks",
    fn(args)
      inp = try Json.decode[TaskRangeInput](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      Ok((inp.start_id.map(Table.encode_int_key), inp.end_id.map(Table.encode_int_key)))
    end,
    fn(tx, args)
      inp = try Json.decode[TaskRangeInput](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      cap = inp.limit or 100
      rows = try Table.tx_scan(tx, tasks, inp.start_id, inp.end_id, cap).map_error(fn(e)
        e.to_text
      end)
      Ok(rows.map(fn(p) task_to_row(p.0, p.1) end).to_json)
    end
  ).with_scoped_query(
    "list_project_tasks",
    ["tasks", "tasks_by_project"],
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

## Milestone 8 View, k-Anonymous Release, and Stateless Agent Onboarding Catalog.
fn workbench_view_catalog() : Views.ViewCatalog
  projs = projects_table()
  tasks = tasks_table()
  Views.catalog().with_view(
    Views.ViewDef(
      name: "projects_finance",
      description: "Full project records including budget, spent, and remaining cents",
      source_buckets: ["projects"],
      fields: [
        Views.ViewField(name: "id", field_type: "text", description: "Project identifier"),
        Views.ViewField(name: "name", field_type: "text", description: "Display name"),
        Views.ViewField(
          name: "budget_cents",
          field_type: "int",
          description: "Total budget in cents"
        ),
        Views.ViewField(
          name: "spent_cents",
          field_type: "int",
          description: "Spent amount in cents"
        ),
        Views.ViewField(
          name: "remaining_cents",
          field_type: "int",
          description: "Remaining budget in cents"
        ),
        Views.ViewField(
          name: "active",
          field_type: "bool",
          description: "Whether project is active"
        )
      ],
      narrows: None,
      load: fn(store)
        rows = try Table.all(store, projs).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            pr = project_to_row(p.0, p.1)
            {
              "id": Json.String(pr.id),
              "name": Json.String(pr.name),
              "budget_cents": Json.int(pr.budget_cents),
              "spent_cents": Json.int(pr.spent_cents),
              "remaining_cents": Json.int(pr.remaining_cents),
              "active": Json.Boolean(pr.active)
            }
          end)
        )
      end
    )
  ).with_view(
    Views.ViewDef(
      name: "projects_public",
      description: "Public project directory (operational fields only)",
      source_buckets: ["projects"],
      fields: [
        Views.ViewField(name: "id", field_type: "text", description: "Project identifier"),
        Views.ViewField(name: "name", field_type: "text", description: "Display name"),
        Views.ViewField(
          name: "active",
          field_type: "bool",
          description: "Whether project is active"
        )
      ],
      narrows: Some("projects_finance"),
      load: fn(store)
        rows = try Table.all(store, projs).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            pr = p.1
            {
              "id": Json.String(p.0),
              "name": Json.String(pr.name),
              "active": Json.Boolean(pr.active)
            }
          end)
        )
      end
    )
  ).with_view(
    Views.ViewDef(
      name: "tasks_finance",
      description: "Full tasks including assignee, base_cost_cents, and billed_cents",
      source_buckets: ["tasks"],
      fields: [
        Views.ViewField(name: "id", field_type: "int", description: "Task ID"),
        Views.ViewField(name: "project_id", field_type: "text", description: "Owning project ID"),
        Views.ViewField(name: "title", field_type: "text", description: "Task title"),
        Views.ViewField(name: "assignee", field_type: "text", description: "Assigned principal"),
        Views.ViewField(
          name: "base_cost_cents",
          field_type: "int",
          description: "Base cost in cents"
        ),
        Views.ViewField(
          name: "billed_cents",
          field_type: "int",
          description: "Final billed cost in cents"
        ),
        Views.ViewField(
          name: "status",
          field_type: "text",
          description: "Status: open | in_progress | done | cancelled"
        )
      ],
      narrows: None,
      load: fn(store)
        rows = try Table.all(store, tasks).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            t = p.1
            asg = case t.assignee
              Some(a): Json.String(a)
              None: Json.Null
            end
            {
              "id": Json.int(p.0),
              "project_id": Json.String(t.project_id),
              "title": Json.String(t.title),
              "assignee": asg,
              "base_cost_cents": Json.int(t.base_cost_cents),
              "billed_cents": Json.int(t.billed_cents),
              "status": Json.String(task_status_label(t.status))
            }
          end)
        )
      end
    )
  ).with_view(
    Views.ViewDef(
      name: "tasks_public",
      description: "Public task queue (operational fields only)",
      source_buckets: ["tasks"],
      fields: [
        Views.ViewField(name: "id", field_type: "int", description: "Task ID"),
        Views.ViewField(name: "project_id", field_type: "text", description: "Owning project ID"),
        Views.ViewField(name: "title", field_type: "text", description: "Task title"),
        Views.ViewField(
          name: "status",
          field_type: "text",
          description: "Status: open | in_progress | done | cancelled"
        )
      ],
      narrows: Some("tasks_finance"),
      load: fn(store)
        rows = try Table.all(store, tasks).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            t = p.1
            {
              "id": Json.int(p.0),
              "project_id": Json.String(t.project_id),
              "title": Json.String(t.title),
              "status": Json.String(task_status_label(t.status))
            }
          end)
        )
      end
    )
  ).with_release(
    Views.ReleaseDef(
      name: "project_budget_summary",
      description: "Aggregate budget, spend, and remaining cents across matching projects (k-anonymous min_group_size=2)",
      source_buckets: ["projects"],
      min_group_size: 2,
      args_description: "{\"min_budget_cents\": 0} (optional filter)",
      run: fn(store, args)
        min_b = args.int_at("min_budget_cents") or 0
        rows = try Table.all(store, projs).map_error(fn(e) e.to_text end)
        var cnt = 0
        var total_budget = 0
        var total_spent = 0
        for (_pid, p) in rows
          if p.budget_cents >= min_b
            cnt += 1
            total_budget += p.budget_cents
            total_spent += p.spent_cents
          end
        end
        Ok((
          cnt,
          Json.Object({
            "project_count": Json.int(cnt),
            "total_budget_cents": Json.int(total_budget),
            "total_spent_cents": Json.int(total_spent),
            "total_remaining_cents": Json.int(total_budget - total_spent)
          })
        ))
      end
    )
  ).with_release(
    Views.ReleaseDef(
      name: "task_cost_by_status",
      description: "Aggregate task count and mean base/billed cost for a task status (k-anonymous min_group_size=2)",
      source_buckets: ["tasks"],
      min_group_size: 2,
      args_description: "{\"status\": \"done\", \"project_id\": \"infra\" (optional)}",
      run: fn(store, args)
        target_st = try args.text_at("status").or_fail("missing string argument 'status'")
        proj_filter = args.text_at("project_id")
        rows = try Table.all(store, tasks).map_error(fn(e) e.to_text end)
        var cnt = 0
        var sum_base = 0
        var sum_billed = 0
        for (_tid, t) in rows
          proj_ok = case proj_filter
            Some(pid): t.project_id == pid
            None: true
          end
          if proj_ok and task_status_label(t.status) == target_st
            cnt += 1
            sum_base += t.base_cost_cents
            sum_billed += t.billed_cents
          end
        end
        avg_base = if cnt == 0: 0 else: sum_base / cnt
        avg_billed = if cnt == 0: 0 else: sum_billed / cnt
        Ok((
          cnt,
          Json.Object({
            "status": Json.String(target_st),
            "task_count": Json.int(cnt),
            "total_billed_cents": Json.int(sum_billed),
            "avg_base_cost_cents": Json.int(avg_base),
            "avg_billed_cents": Json.int(avg_billed)
          })
        ))
      end
    )
  ).with_action_doc(
    "create_project",
    "Create or update a project and its budget ceiling (admin)",
    "{\"id\": \"ml-ops\", \"name\": \"ML Ops\", \"budget_cents\": 50000}"
  ).with_action_doc(
    "create_task",
    "Create a new open task inside an existing project (planner/admin)",
    "{\"id\": 501, \"project_id\": \"infra\", \"title\": \"...\", \"base_cost_cents\": 5000}"
  ).with_action_doc(
    "complete_task",
    "Complete an open task, billing base_cost + overhead against project budget and optionally attaching an artifact",
    "{\"task_id\": 303, \"assignee\": \"agent:sre\", \"artifact_id\": \"...\"}"
  ).with_invariant_doc(
    "budget_bounds",
    "Every project obeys 0 <= spent_cents <= budget_cents (checked incrementally on touched rows)"
  ).with_invariant_doc(
    "task_valid",
    "Every task has non-empty title and base_cost_cents >= 0, billed_cents >= 0"
  ).with_invariant_doc(
    "referential_integrity",
    "Every task references an existing project and every artifact references an existing task"
  )
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

fn get_ui() : Api.Response
  Api.html_response(200, WorkbenchUi.page_html())
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
          t2 = try tx_index_workbench_task(t1, body.id, t).map_error(map_table_error)
          (t3, _rec) = try Replay.tx_record_call(
            t2,
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
          Ok((t3, row))
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
          t3 = try tx_index_workbench_task(t2, id, next_task).map_error(map_table_error)
          t4 = case (body.artifact_id, body.artifact_summary, body.artifact_sha256)
            (Some(aid), Some(sum), Some(sha)):
              art = Artifact(task_id: id, author: body.assignee, summary: sum, sha256: sha)
              ta = try Table.put(t3, arts, aid, art).map_error(map_table_error)
              try tx_index_workbench_artifact(ta, aid, task.project_id, art).map_error(
                map_table_error
              )
            _: t3
          end
          (t5, _rec) = try Replay.tx_record_call(
            t4,
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
          Ok((t5, row))
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
  Grants.issue_root_scoped_locked(
    files,
    db_path(),
    workbench_schema(),
    meta,
    spec,
    body.allowed_views,
    body.allowed_releases
  ).map_error(map_grant_error)
end

fn list_grants(rf: ReadFiles) : Result(List(Grants.Grant), WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) Grants.list_all(Ledger.store(db)).map_error(map_grant_error) end
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
  Grants.delegate_scoped_locked(
    files,
    db_path(),
    workbench_schema(),
    meta,
    id,
    spec,
    body.allowed_views,
    body.allowed_releases,
    Views.view_narrows_map(workbench_view_catalog())
  ).map_error(map_grant_error)
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

fn list_worlds(rf: ReadFiles) : Result(List(World.WorldRecord), WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) World.list_worlds(Ledger.store(db)).map_error(map_world_error) end
  )
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

fn get_world_telemetry(rf: ReadFiles, clock: Clock) : Result(
  WorldTelemetryResponse,
  WorkbenchError
)
  now = clock.now
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      tel = try World.telemetry(st).map_error(map_world_error)
      tickets = try World.list_priority_tickets(st, now).map_error(map_world_error)
      ws = try World.list_worlds(st).map_error(map_world_error)
      var links = []
      for w in ws
        if (try World.get_world_link(st, w.id).map_error(map_world_error)) is Some(lnk)
          links = links.append(lnk)
        end
      end
      Ok(WorldTelemetryResponse(telemetry: tel, active_tickets: tickets, links: links))
    end
  )
end

fn post_world_child(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  body: ChildWorldOpenInput
) : Result(World.WorldRecord, WorkbenchError)
  _ = caller
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  now = clock.now
  exp = now + 1.second * body.ttl_seconds
  World.open_child_world_locked(
    files,
    db_path(),
    workbench_schema(),
    id,
    body.id,
    body.grant_id,
    now,
    exp
  ).map_error(map_world_error)
end

fn list_world_children(rf: ReadFiles, id: Text) : Result(List(World.WorldRecord), WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) World.list_child_worlds(Ledger.store(db), id).map_error(map_world_error) end
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

fn post_world_land_fair(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  World.LandOutcome,
  WorkbenchError
)
  reason = (caller.reason or "").trim
  return Error(MissingReason) if reason.empty?
  World.land_world_fair_locked(
    files,
    db_path(),
    workbench_schema(),
    workbench_catalog(),
    id,
    reason,
    clock.now
  ).map_error(map_world_error)
end

fn post_world_land_child(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  World.ChildLandResult,
  WorkbenchError
)
  reason = (caller.reason or "").trim
  return Error(MissingReason) if reason.empty?
  World.land_child_world_locked(
    files,
    db_path(),
    workbench_schema(),
    workbench_catalog(),
    id,
    reason,
    clock.now
  ).map_error(map_world_error)
end

fn post_world_priority(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  body: PriorityClaimInput
) : Result(World.PriorityTicket, WorkbenchError)
  _ = caller
  return Error(InvalidInput(reason: "hold_seconds must be > 0")) if body.hold_seconds <= 0
  return Error(InvalidInput(reason: "buckets cannot be empty")) if body.buckets.empty?
  threshold = body.min_stale_threshold or 1
  World.claim_priority_locked(
    files,
    db_path(),
    workbench_schema(),
    id,
    body.buckets,
    threshold,
    body.hold_seconds,
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

fn get_search_stats(rf: ReadFiles) : Result(SearchStatsResponse, WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      fst = try Fts.stats(st, workbench_fts_index()).map_error(map_fts_error)
      vst = try Vec.stats(st, workbench_vec_index()).map_error(map_vec_error)
      Ok(SearchStatsResponse(fts: fst, vec: vst))
    end
  )
end

fn post_search(rf: ReadFiles, body: SearchRequest) : Result(SearchResponse, WorkbenchError)
  raw_mode = (body.mode or "hybrid").trim
  mode = if raw_mode == "fts" or raw_mode == "vec" or raw_mode == "hybrid"
    raw_mode
  else
    return Error(InvalidInput(reason: "search mode must be 'hybrid', 'fts', or 'vec'"))
  end
  proj_opt = case body.project_id
    Some(p) if not p.trim.empty?: Some(p.trim)
    Some(_) | None: None
  end
  raw_lim = body.limit or 10
  cap = if raw_lim > 0 and raw_lim <= 50: raw_lim else: 10
  prefix? = body.prefix_last_term or true

  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      f_idx = workbench_fts_index()
      v_idx = workbench_vec_index()
      hits = if mode == "fts"
        fh = try Fts.search(
          st,
          f_idx,
          body.query,
          Fts.SearchOptions(limit: cap, prefix_last_term?: prefix?, required_scope: proj_opt)
        ).map_error(map_fts_error)
        fh.enumerate.map(fn(p)
          rank = p.0 + 1
          h = p.1
          Vec.HybridHit(
            doc_id: h.doc_id,
            scope: h.scope,
            score: h.score,
            fts_rank: Some(rank),
            fts_score: Some(h.score),
            vec_rank: None,
            vec_score: None,
            matched_terms: h.matched_terms,
            matched_fields: h.matched_fields
          )
        end)
      else if mode == "vec"
        qv = case body.vector
          Some(v): v
          None: Vec.text_sketch_embedding(body.query, 32)
        end
        vh = try Vec.search(
          st,
          v_idx,
          qv,
          Vec.VecSearchOptions(limit: cap, required_scope: proj_opt, min_score: None)
        ).map_error(map_vec_error)
        vh.enumerate.map(fn(p)
          rank = p.0 + 1
          h = p.1
          Vec.HybridHit(
            doc_id: h.doc_id,
            scope: h.scope,
            score: h.score,
            fts_rank: None,
            fts_score: None,
            vec_rank: Some(rank),
            vec_score: Some(h.score),
            matched_terms: [],
            matched_fields: []
          )
        end)
      else
        qv_opt = case body.vector
          Some(v): Some(v)
          None:
            if body.query.trim.empty?
              None
            else
              Some(Vec.text_sketch_embedding(body.query, 32))
            end
        end
        cand = if cap * 4 > 20: cap * 4 else: 20
        try Vec.hybrid_search(
          st,
          f_idx,
          v_idx,
          body.query,
          qv_opt,
          Vec.HybridOptions(
            limit: cap,
            prefix_last_term?: prefix?,
            required_scope: proj_opt,
            rrf_k: 60,
            fts_weight: 1.0.to_float,
            vec_weight: 1.0.to_float,
            candidate_limit: cand,
            min_vec_score: None
          )
        ).map_error(map_vec_error)
      end
      Ok(SearchResponse(mode: mode, query: body.query, project_id: proj_opt, hits: hits))
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

## Idempotent interactive demo seeder for the live Workbench Inspector & MCP walkthrough.
## Sets up a rogue delegated sub-agent budget drain, two refused SRE tasks (`OrigRefused`),
## an active Claim, and an open speculative World with staged CoW changes ready to inspect/land.
fn post_admin_demo(caller: Caller, files: Files, clock: Clock) : Result(
  DemoResponse,
  WorkbenchError
)
  try require_admin(caller)
  _ = try Ledger.init_locked(files, db_path(), workbench_schema(), clock.now).map_error(
    map_ledger_error
  )
  rf = files.read_only
  already = case get_project(rf, "payments")
    Ok(_): true
    Error(_): false
  end
  if already
    h = try get_health(rf)
    return Ok(
      DemoResponse(
        ok: true,
        summary: "demo already seeded (projects=infra,payments | open world=w-demo-payments-401)",
        txid: h.txid
      )
    )
  end

  admin = Caller(principal: caller.principal, role: Admin, reason: Some("seed interactive demo"))
  planner = Caller(principal: "agent:planner", role: Planner, reason: Some("seed interactive demo"))
  rogue = Caller(principal: "agent:rogue-bot", role: Worker, reason: Some("run unauthorized job"))
  sre = Caller(principal: "agent:sre", role: Worker, reason: Some("critical SRE runbook"))

  _ = try post_project(
    admin,
    files,
    clock,
    ProjectInput(id: "payments", name: "Payments Core", budget_cents: 40000)
  )
  _ = try post_task(
    planner,
    files,
    clock,
    CreateTaskInput(
      id: 301,
      project_id: "infra",
      title: "Rogue crypto-miner job 1",
      base_cost_cents: 20000
    )
  )
  _ = try post_task(
    planner,
    files,
    clock,
    CreateTaskInput(
      id: 302,
      project_id: "infra",
      title: "Rogue crypto-miner job 2",
      base_cost_cents: 20000
    )
  )
  _ = try post_task(
    planner,
    files,
    clock,
    CreateTaskInput(
      id: 303,
      project_id: "infra",
      title: "SRE database failover drill",
      base_cost_cents: 10000
    )
  )
  _ = try post_task(
    planner,
    files,
    clock,
    CreateTaskInput(
      id: 304,
      project_id: "infra",
      title: "SRE TLS certificate rotation",
      base_cost_cents: 10000
    )
  )
  _ = try post_task(
    planner,
    files,
    clock,
    CreateTaskInput(
      id: 401,
      project_id: "payments",
      title: "Ledger reconciliation audit",
      base_cost_cents: 8000
    )
  )
  _ = try post_task(
    planner,
    files,
    clock,
    CreateTaskInput(
      id: 402,
      project_id: "payments",
      title: "Webhook retry hardening",
      base_cost_cents: 6000
    )
  )

  _ = try post_grant(
    admin,
    files,
    clock,
    GrantInput(
      id: "g-team-b",
      principal: "agent:team-b-lead",
      allowed_actions: ["create_task", "complete_task"],
      allowed_views: Some(["projects_public", "tasks_public"]),
      allowed_releases: Some(["task_cost_by_status"]),
      max_calls: 25,
      ttl_seconds: 7200
    )
  )
  _ = try post_delegate_grant(
    planner,
    files,
    clock,
    "g-team-b",
    GrantInput(
      id: "g-rogue-sub",
      principal: "agent:rogue-bot",
      allowed_actions: ["complete_task"],
      allowed_views: Some(["tasks_public"]),
      allowed_releases: None,
      max_calls: 10,
      ttl_seconds: 3600
    )
  )
  _ = try post_grant(
    admin,
    files,
    clock,
    GrantInput(
      id: "g-sre",
      principal: "agent:sre",
      allowed_actions: ["complete_task"],
      allowed_views: Some(["projects_finance", "tasks_finance"]),
      allowed_releases: Some(["project_budget_summary", "task_cost_by_status"]),
      max_calls: 25,
      ttl_seconds: 7200
    )
  )

  ## Rogue sub-agent completes #301 and #302 via Worlds -> burns 44,000c of 50,000c infra budget!
  for tid in [301, 302]
    wid = "w-demo-rogue-#{tid}"
    _ = try post_world(
      rogue,
      files,
      clock,
      WorldOpenInput(id: wid, grant_id: "g-rogue-sub", ttl_seconds: 600)
    )
    _ = try post_world_call(
      rogue,
      files,
      clock,
      wid,
      WorldCallInput(
        action: "complete_task",
        args: CompleteTaskInput(
          task_id: tid,
          assignee: "agent:rogue-bot",
          artifact_id: Some("art-rogue-#{tid}"),
          artifact_summary: Some("Unauthorized workload output"),
          artifact_sha256: Some("deadbeef000#{tid}")
        ).to_json
      )
    )
    _ = try post_world_land(rogue, files, clock, wid)
  end

  ## Legitimate SRE attempts #303 and #304 -> both refused (`409 BudgetExceeded`) and recorded as OrigRefused!
  for tid in [303, 304]
    case post_complete_task(
      sre,
      files,
      clock,
      tid,
      CompleteTaskInput(
        task_id: tid,
        assignee: "agent:sre",
        artifact_id: Some("art-sre-#{tid}"),
        artifact_summary: Some("Critical SRE runbook artifact ##{tid}"),
        artifact_sha256: Some("cafebabe000#{tid}")
      )
    )
      Ok(_): Unit
      Error(BudgetExceeded(project_id: _, needed: _, remaining: _)): Unit
      Error(other): return Error(other)
    end
  end

  ## Leave a live Claim + open speculative World on payments/#401 so user/agent can inspect its O(diff) and Land!
  _ = try post_claim(
    sre,
    files,
    clock,
    ClaimInput(
      resource: "task:401",
      grant_id: "g-sre",
      world_id: Some("w-demo-payments-401"),
      ttl_seconds: 3600
    )
  )
  _ = try post_world(
    sre,
    files,
    clock,
    WorldOpenInput(id: "w-demo-payments-401", grant_id: "g-sre", ttl_seconds: 3600)
  )
  _ = try post_world_query(
    sre,
    files,
    clock,
    "w-demo-payments-401",
    WorldQueryInput(query: "get_task", args: Json.int(401))
  )
  _ = try post_world_call(
    sre,
    files,
    clock,
    "w-demo-payments-401",
    WorldCallInput(
      action: "complete_task",
      args: CompleteTaskInput(
        task_id: 401,
        assignee: "agent:sre",
        artifact_id: Some("art-pay-401"),
        artifact_summary: Some("Reconciliation passed with zero drift"),
        artifact_sha256: Some("feedface0401")
      ).to_json
    )
  )

  h = try get_health(rf)
  Ok(
    DemoResponse(
      ok: true,
      summary: "2 projects, 6 tasks, rogue drain on infra (2 SRE OrigRefused ready for Replay), open World w-demo-payments-401",
      txid: h.txid
    )
  )
end

fn role_label(role: Role) : Text
  case role
    Admin: "admin"
    Planner: "planner"
    Worker: "worker"
  end
end

fn direct_actions_for_role(role: Role) : List(Text)
  case role
    Admin: ["create_project", "create_task", "complete_task"]
    Planner: ["create_task", "complete_task"]
    Worker: ["complete_task"]
  end
end

fn get_describe(caller: Caller, rf: ReadFiles, clock: Clock, grant_id: Option(Text)) : Result(
  Views.OnboardingManifest,
  WorkbenchError
)
  now = clock.now
  is_admin? = caller.role is Admin
  vcat = workbench_view_catalog()
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      Views.describe_for_caller(
        db,
        vcat,
        caller.principal,
        role_label(caller.role),
        is_admin?,
        direct_actions_for_role(caller.role),
        grant_id,
        Views.default_limits(),
        now
      ).map_error(map_views_error)
    end
  )
end

fn post_view_query(caller: Caller, files: Files, clock: Clock, body: ReadProgramRequest) : Result(
  Views.ReadResult,
  WorkbenchError
)
  is_admin? = caller.role is Admin
  Views.execute_read_program_locked(
    files,
    db_path(),
    workbench_schema(),
    workbench_view_catalog(),
    body.program,
    caller.principal,
    body.grant_id,
    is_admin?,
    Views.default_limits(),
    clock.now
  ).map_error(map_views_error)
end

fn post_release(caller: Caller, files: Files, clock: Clock, name: Text, body: ReleaseRequest) : Result(
  Views.ReleaseResult,
  WorkbenchError
)
  is_admin? = caller.role is Admin
  Views.execute_release_locked(
    files,
    db_path(),
    workbench_schema(),
    workbench_view_catalog(),
    name,
    body.args or Json.Object({}),
    caller.principal,
    body.grant_id,
    is_admin?,
    clock.now
  ).map_error(map_views_error)
end

fn get_reads(rf: ReadFiles, limit: Option(Int)) : Result(List(Views.ReadLogEntry), WorkbenchError)
  lim = limit or 50
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) Views.list_read_log(Ledger.store(db), lim).map_error(map_views_error) end
  )
end

## ---------------------------------------------------------------------------
## Native Streamable HTTP MCP JSON-RPC 2.0 Server (`POST /mcp`)
## ---------------------------------------------------------------------------
fn mcp_json_response(payload: Json) : Api.Response
  Api.response(200, [("content-type", "application/json")], Json.encode(payload).bytes)
end

fn mcp_rpc_ok(id_val: Json, result_val: Json) : Json
  Json.Object({"jsonrpc": Json.String("2.0"), "id": id_val, "result": result_val})
end

fn mcp_rpc_error(id_val: Json, code: Int, message: Text) : Json
  Json.Object({
    "jsonrpc": Json.String("2.0"),
    "id": id_val,
    "error": Json.Object({"code": Json.int(code), "message": Json.String(message)})
  })
end

fn mcp_tool_result(text: Text, is_error?: Bool) : Json
  Json.Object({
    "content": Json.Array([Json.Object({"type": Json.String("text"), "text": Json.String(text)})]),
    "isError": Json.Boolean(is_error?)
  })
end

fn mcp_schema(props: Map(Text, Json), required: List(Text)) : Json
  Json.Object({
    "type": Json.String("object"),
    "properties": Json.Object(props),
    "required": Json.Array(required.map(fn(r) Json.String(r) end))
  })
end

fn mcp_prop(ty: Text, desc: Text) : Json
  Json.Object({"type": Json.String(ty), "description": Json.String(desc)})
end

fn mcp_tool_def(name: Text, description: Text, input_schema: Json) : Json
  Json.Object({
    "name": Json.String(name),
    "description": Json.String(description),
    "inputSchema": input_schema
  })
end

fn mcp_tools_list() : Json
  empty_schema = mcp_schema({}, [])
  reason_p = mcp_prop("string", "Accountable audit reason for this write (overrides X-Reason)")
  Json.Object({
    "tools": Json.Array([
      mcp_tool_def(
        "modb_health",
        "Check MoDB Workbench health, txid, audit count, and replay call count.",
        empty_schema
      ),
      mcp_tool_def(
        "modb_init",
        "Initialize the MoDB Workbench database (admin).",
        mcp_schema({"reason": reason_p}, [])
      ),
      mcp_tool_def(
        "modb_seed_demo",
        "Idempotently seed the interactive multi-agent demo (rogue drain, OrigRefused SRE tasks, open World, active Claim).",
        mcp_schema({"reason": reason_p}, [])
      ),
      mcp_tool_def(
        "modb_verify",
        "Run full Layer 1-3 cryptographic verification: SHA-256 pages, audit hash chain, and all invariants.",
        empty_schema
      ),
      mcp_tool_def(
        "modb_export_snapshot",
        "Export a layout-independent SHA-256 PortableSnapshot JSON.",
        mcp_schema(
          {
            "include_internal": mcp_prop(
              "boolean",
              "Include internal _modb_* buckets (default true)"
            )
          },
          []
        )
      ),
      mcp_tool_def(
        "modb_list_projects",
        "List all projects with budget, spent, and remaining cents.",
        empty_schema
      ),
      mcp_tool_def(
        "modb_create_project",
        "Create or update a project and its budget (admin).",
        mcp_schema(
          {
            "id": mcp_prop("string", "Project ID"),
            "name": mcp_prop("string", "Project display name"),
            "budget_cents": mcp_prop("integer", "Budget in cents"),
            "reason": reason_p
          },
          ["id", "name", "budget_cents"]
        )
      ),
      mcp_tool_def(
        "modb_get_project_tasks",
        "List all tasks belonging to a project via secondary index.",
        mcp_schema({"project_id": mcp_prop("string", "Project ID")}, ["project_id"])
      ),
      mcp_tool_def(
        "modb_create_task",
        "Create a new open task in a project (planner/admin).",
        mcp_schema(
          {
            "id": mcp_prop("integer", "Unique integer task ID"),
            "project_id": mcp_prop("string", "Target project ID"),
            "title": mcp_prop("string", "Task title"),
            "base_cost_cents": mcp_prop("integer", "Base task cost in cents"),
            "reason": reason_p
          },
          ["id", "project_id", "title", "base_cost_cents"]
        )
      ),
      mcp_tool_def(
        "modb_complete_task",
        "Complete a task directly (charges project budget; BudgetExceeded refusals are captured for Replay).",
        mcp_schema(
          {
            "task_id": mcp_prop("integer", "Task ID to complete"),
            "assignee": mcp_prop("string", "Agent/principal completing the task"),
            "artifact_id": mcp_prop("string", "Optional artifact ID"),
            "artifact_summary": mcp_prop("string", "Optional artifact summary"),
            "artifact_sha256": mcp_prop("string", "Optional artifact SHA-256"),
            "reason": reason_p
          },
          ["task_id", "assignee"]
        )
      ),
      mcp_tool_def(
        "modb_list_grants",
        "List all attenuated capability Grants (root and delegated children).",
        empty_schema
      ),
      mcp_tool_def(
        "modb_issue_grant",
        "Issue a new root Grant with bounded actions, optional Views/Releases, call budget, and TTL (admin).",
        mcp_schema(
          {
            "id": mcp_prop("string", "Grant ID"),
            "principal": mcp_prop("string", "Recipient agent principal"),
            "allowed_actions": Json.Object({
              "type": Json.String("array"),
              "items": Json.Object({"type": Json.String("string")})
            }),
            "allowed_views": Json.Object({
              "type": Json.String("array"),
              "items": Json.Object({"type": Json.String("string")})
            }),
            "allowed_releases": Json.Object({
              "type": Json.String("array"),
              "items": Json.Object({"type": Json.String("string")})
            }),
            "max_calls": mcp_prop("integer", "Maximum calls permitted"),
            "ttl_seconds": mcp_prop("integer", "Grant lifetime in seconds"),
            "reason": reason_p
          },
          ["id", "principal", "allowed_actions", "max_calls", "ttl_seconds"]
        )
      ),
      mcp_tool_def(
        "modb_delegate_grant",
        "Delegate a strictly attenuated child Grant from a parent Grant (narrowing actions, views, releases, budget, TTL).",
        mcp_schema(
          {
            "parent_id": mcp_prop("string", "Parent Grant ID"),
            "id": mcp_prop("string", "Child Grant ID"),
            "principal": mcp_prop("string", "Child agent principal"),
            "allowed_actions": Json.Object({
              "type": Json.String("array"),
              "items": Json.Object({"type": Json.String("string")})
            }),
            "allowed_views": Json.Object({
              "type": Json.String("array"),
              "items": Json.Object({"type": Json.String("string")})
            }),
            "allowed_releases": Json.Object({
              "type": Json.String("array"),
              "items": Json.Object({"type": Json.String("string")})
            }),
            "max_calls": mcp_prop("integer", "Child call cap (<= parent remaining)"),
            "ttl_seconds": mcp_prop("integer", "Child TTL in seconds (<= parent expiry)"),
            "reason": reason_p
          },
          ["parent_id", "id", "principal", "allowed_actions", "max_calls", "ttl_seconds"]
        )
      ),
      mcp_tool_def(
        "modb_revoke_grant",
        "Revoke a Grant (cascades automatically to every delegated descendant; admin).",
        mcp_schema({"id": mcp_prop("string", "Grant ID to revoke"), "reason": reason_p}, ["id"])
      ),
      mcp_tool_def(
        "modb_list_claims",
        "List currently active advisory Claims (leases).",
        empty_schema
      ),
      mcp_tool_def(
        "modb_acquire_claim",
        "Acquire an exclusive advisory Claim lease on a resource (e.g. task:401).",
        mcp_schema(
          {
            "resource": mcp_prop("string", "Resource key to claim"),
            "grant_id": mcp_prop("string", "Active Grant ID backing the claim"),
            "world_id": mcp_prop("string", "Optional associated World ID"),
            "ttl_seconds": mcp_prop("integer", "Lease TTL in seconds"),
            "reason": reason_p
          },
          ["resource", "grant_id", "ttl_seconds"]
        )
      ),
      mcp_tool_def(
        "modb_release_claim",
        "Release a held advisory Claim.",
        mcp_schema(
          {"resource": mcp_prop("string", "Resource key to release"), "reason": reason_p},
          ["resource"]
        )
      ),
      mcp_tool_def(
        "modb_list_worlds",
        "List all speculative Worlds and their statuses.",
        empty_schema
      ),
      mcp_tool_def(
        "modb_world_metrics",
        "Read World landing, StaleRead rejection, and needless_send_backs telemetry.",
        empty_schema
      ),
      mcp_tool_def(
        "modb_world_open",
        "Open a pinned CoW speculative World under a Grant.",
        mcp_schema(
          {
            "id": mcp_prop("string", "World ID"),
            "grant_id": mcp_prop("string", "Active Grant ID"),
            "ttl_seconds": mcp_prop("integer", "World TTL in seconds")
          },
          ["id", "grant_id", "ttl_seconds"]
        )
      ),
      mcp_tool_def(
        "modb_world_query",
        "Execute and record a snapshot query inside an open World (get_task, get_project, scan_tasks_range, list_project_tasks).",
        mcp_schema(
          {
            "world_id": mcp_prop("string", "Open World ID"),
            "query": mcp_prop(
              "string",
              "Query name: get_task | get_project | scan_tasks_range | list_project_tasks"
            ),
            "args": Json.Object({
              "description": Json.String(
                "Query argument (task int ID, project string ID, or {start_id, end_id, limit})"
              )
            })
          },
          ["world_id", "query", "args"]
        )
      ),
      mcp_tool_def(
        "modb_world_call",
        "Stage a replayable action call inside an open World without touching main state.",
        mcp_schema(
          {
            "world_id": mcp_prop("string", "Open World ID"),
            "action": mcp_prop(
              "string",
              "Action name: create_project | create_task | complete_task"
            ),
            "args": Json.Object({
              "type": Json.String("object"),
              "description": Json.String("Action JSON arguments")
            }),
            "reason": reason_p
          },
          ["world_id", "action", "args"]
        )
      ),
      mcp_tool_def(
        "modb_world_diff",
        "Inspect the exact structural CoW O(diff) of an open World against its pinned base (or parent fork watermark for Child Worlds).",
        mcp_schema({"world_id": mcp_prop("string", "Open World ID")}, ["world_id"])
      ),
      mcp_tool_def(
        "modb_world_land",
        "Re-verify recorded query checks and atomically land an open World into main state.",
        mcp_schema(
          {"world_id": mcp_prop("string", "Open World ID"), "reason": reason_p},
          ["world_id"]
        )
      ),
      mcp_tool_def(
        "modb_world_abort",
        "Abort an open speculative World and release its pinned CoW root (cascades to open Child Worlds).",
        mcp_schema({"world_id": mcp_prop("string", "Open World ID")}, ["world_id"])
      ),
      mcp_tool_def(
        "modb_world_telemetry",
        "Read Milestone 10 World telemetry (key/range O(diff) skips, child landings, active fairness PriorityTickets, and Child World links).",
        empty_schema
      ),
      mcp_tool_def(
        "modb_world_open_child",
        "Fork an attenuated Nested Child World from an open Parent World with bounded TTL and non-widening Grant.",
        mcp_schema(
          {
            "parent_world_id": mcp_prop("string", "Open Parent World ID"),
            "id": mcp_prop("string", "New Child World ID"),
            "grant_id": mcp_prop("string", "Descendant or same Grant ID (cannot widen parent Grant)"),
            "ttl_seconds": mcp_prop("integer", "Child World TTL in seconds (capped at parent expiry)")
          },
          ["parent_world_id", "id", "grant_id", "ttl_seconds"]
        )
      ),
      mcp_tool_def(
        "modb_world_list_children",
        "List all Nested Child Worlds forked from a Parent World.",
        mcp_schema(
          {"parent_world_id": mcp_prop("string", "Parent World ID")},
          ["parent_world_id"]
        )
      ),
      mcp_tool_def(
        "modb_world_land_child",
        "Validate child reads against post-fork parent mutations (via O(diff)) and atomically merge a Child World into its Parent World.",
        mcp_schema(
          {"world_id": mcp_prop("string", "Open Child World ID"), "reason": reason_p},
          ["world_id"]
        )
      ),
      mcp_tool_def(
        "modb_world_claim_priority",
        "Issue a bounded (1..60s) fairness PriorityTicket for a starved open World so competing writes yield during land_fair.",
        mcp_schema(
          {
            "world_id": mcp_prop("string", "Open World ID whose principal has starved"),
            "buckets": Json.Object({
              "type": Json.String("array"),
              "items": Json.Object({"type": Json.String("string")})
            }),
            "min_stale_threshold": mcp_prop(
              "integer",
              "Minimum consecutive StaleRead rejections required (default 1)"
            ),
            "hold_seconds": mcp_prop("integer", "Ticket hold duration in seconds (1..60)")
          },
          ["world_id", "buckets", "hold_seconds"]
        )
      ),
      mcp_tool_def(
        "modb_world_land_fair",
        "Fairness-aware World landing: checks active PriorityTickets and yields DeferredByFairness instead of clobbering starved Worlds.",
        mcp_schema(
          {"world_id": mcp_prop("string", "Open World ID"), "reason": reason_p},
          ["world_id"]
        )
      ),
      mcp_tool_def(
        "modb_audit_log",
        "Query the hash-chained Audit Ledger (optionally filtered by principal or action).",
        mcp_schema(
          {
            "principal": mcp_prop("string", "Optional principal filter"),
            "action": mcp_prop("string", "Optional action filter"),
            "limit": mcp_prop("integer", "Max entries to return (default 50)")
          },
          []
        )
      ),
      mcp_tool_def(
        "modb_replay_calls",
        "List all persisted calls in the Replay Call Log (including OrigRefused calls).",
        empty_schema
      ),
      mcp_tool_def(
        "modb_replay_simulate",
        "Simulate an offline selective-undo or bug-fix Replay proposal without modifying live state (admin).",
        mcp_schema(
          {
            "proposal_id": mcp_prop("string", "Unique proposal ID"),
            "description": mcp_prop("string", "Human description of the replay"),
            "exclude_principal": mcp_prop("string", "Optional principal to excise"),
            "exclude_grant": mcp_prop(
              "string",
              "Optional grant ID to excise (auto-expands subtree)"
            ),
            "exclude_world": mcp_prop("string", "Optional world ID to excise"),
            "stop_before_seq": mcp_prop("integer", "Optional sequence cutoff"),
            "overhead_pct_override": mcp_prop(
              "integer",
              "Optional billing overhead % override (0..100)"
            ),
            "reason": reason_p
          },
          ["proposal_id", "description"]
        )
      ),
      mcp_tool_def(
        "modb_list_proposals",
        "List all Replay Proposals with their outcome summaries.",
        empty_schema
      ),
      mcp_tool_def(
        "modb_replay_accept",
        "Atomically adopt a pending Replay Proposal (staleness-guarded; admin).",
        mcp_schema(
          {"proposal_id": mcp_prop("string", "Pending proposal ID"), "reason": reason_p},
          ["proposal_id"]
        )
      ),
      mcp_tool_def(
        "modb_replay_discard",
        "Discard a pending Replay Proposal without modifying live state (admin).",
        mcp_schema(
          {"proposal_id": mcp_prop("string", "Pending proposal ID"), "reason": reason_p},
          ["proposal_id"]
        )
      ),
      mcp_tool_def(
        "modb_describe",
        "Self-onboarding manifest for stateless agents: permitted actions, narrowed Views (visible fields only), Releases, active Claims, open Worlds, invariants, and ReadLimits.",
        mcp_schema(
          {"grant_id": mcp_prop("string", "Optional Grant ID to inspect scoped permissions for")},
          []
        )
      ),
      mcp_tool_def(
        "modb_read_program",
        "Execute a zero-approval sandboxed ad-hoc ReadProgram over an authorized View (static field check + work budget + read provenance log).",
        mcp_schema(
          {
            "grant_id": mcp_prop("string", "Optional Grant ID authorizing the View read"),
            "program": Json.Object({
              "type": Json.String("object"),
              "description": Json.String(
                "ReadProgram object: {view, where_clause?, select?, group_by?, aggregates?, order_by?, limit?}"
              )
            })
          },
          ["program"]
        )
      ),
      mcp_tool_def(
        "modb_release",
        "Invoke an approved statistical/k-anonymous Release function (project_budget_summary, task_cost_by_status).",
        mcp_schema(
          {
            "release": mcp_prop(
              "string",
              "Release name: project_budget_summary | task_cost_by_status"
            ),
            "grant_id": mcp_prop("string", "Optional Grant ID authorizing the Release"),
            "args": Json.Object({
              "type": Json.String("object"),
              "description": Json.String("Release JSON arguments")
            })
          },
          ["release"]
        )
      ),
      mcp_tool_def(
        "modb_read_log",
        "List persisted Read Provenance entries from _modb_read_log (ad-hoc ReadPrograms and Releases).",
        mcp_schema({"limit": mcp_prop("integer", "Max entries to return (default 50)")}, [])
      ),
      mcp_tool_def(
        "modb_search",
        "Search tasks and artifacts via transactional BM25+ full-text (`fts`), quantized Cosine vector (`vec`), or Reciprocal Rank Fusion (`hybrid`, default).",
        mcp_schema(
          {
            "query": mcp_prop("string", "Search query text"),
            "mode": mcp_prop("string", "Search mode: hybrid (default) | fts | vec"),
            "project_id": mcp_prop("string", "Optional project_id scope filter"),
            "limit": mcp_prop("integer", "Max ranked hits to return (default 10, max 50)")
          },
          ["query"]
        )
      ),
      mcp_tool_def(
        "modb_search_stats",
        "Return transactional FTS (BM25+) and quantized Vector corpus statistics for the Workbench.",
        empty_schema
      )
    ])
  })
end

fn caller_for_mcp(base: Caller, args: Json) : Caller
  arg_reason = args.text_at("reason")
  effective_reason = case arg_reason
    Some(r) if not r.trim.empty?: Some(r)
    Some(_) | None: base.reason
  end
  effective_principal = case base.role
    Admin: base.principal
    Planner | Worker:
      case args.text_at("agent_id")
        Some(a) if not a.trim.empty?: a.trim
        Some(_) | None: base.principal
      end
  end
  Caller(principal: effective_principal, role: base.role, reason: effective_reason)
end

fn mcp_encode_result(res: Result(T, WorkbenchError)) : Json where T: Json
  case res
    Ok(val): mcp_tool_result(Json.encode(val), false)
    Error(err): mcp_tool_result(Json.encode(err), true)
  end
end

fn mcp_req_text(args: Json, key: Text) : Result(Text, WorkbenchError)
  args.text_at(key).or_fail(InvalidInput(reason: "missing string argument '#{key}'"))
end

fn mcp_call_tool(caller: Caller, files: Files, clock: Clock, name: Text, args: Json) : Json
  rf = files.read_only
  eff = caller_for_mcp(caller, args)
  case name
    "modb_health": mcp_encode_result(get_health(rf))
    "modb_init": mcp_encode_result(post_admin_init(eff, files, clock))
    "modb_seed_demo": mcp_encode_result(post_admin_demo(eff, files, clock))
    "modb_verify": mcp_encode_result(get_admin_verify(rf))
    "modb_export_snapshot":
      inc = args.bool_at("include_internal") or true
      case Export.export_locked(rf, db_path(), workbench_schema(), inc, clock.now).map_error(
        map_export_error
      )
        Ok(snap): mcp_tool_result(Export.encode_snapshot_json(snap), false)
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_list_projects": mcp_encode_result(list_projects(rf))
    "modb_create_project":
      case Json.from_json[ProjectInput](args)
        Ok(inp): mcp_encode_result(post_project(eff, files, clock, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_get_project_tasks":
      case mcp_req_text(args, "project_id")
        Ok(pid): mcp_encode_result(get_project_tasks(rf, pid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_create_task":
      case Json.from_json[CreateTaskInput](args)
        Ok(inp): mcp_encode_result(post_task(eff, files, clock, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_complete_task":
      case Json.from_json[CompleteTaskInput](args)
        Ok(inp): mcp_encode_result(post_complete_task(eff, files, clock, inp.task_id, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_list_grants": mcp_encode_result(list_grants(rf))
    "modb_issue_grant":
      case Json.from_json[GrantInput](args)
        Ok(inp): mcp_encode_result(post_grant(eff, files, clock, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_delegate_grant":
      case (mcp_req_text(args, "parent_id"), Json.from_json[GrantInput](args))
        (Ok(pid), Ok(inp)): mcp_encode_result(post_delegate_grant(eff, files, clock, pid, inp))
        (Error(e), _): mcp_tool_result(Json.encode(e), true)
        (_, Error(e)): mcp_tool_result(e.to_text, true)
      end
    "modb_revoke_grant":
      case mcp_req_text(args, "id")
        Ok(gid): mcp_encode_result(post_revoke_grant(eff, files, clock, gid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_list_claims": mcp_encode_result(list_claims(rf, clock))
    "modb_acquire_claim":
      case Json.from_json[ClaimInput](args)
        Ok(inp): mcp_encode_result(post_claim(eff, files, clock, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_release_claim":
      case mcp_req_text(args, "resource")
        Ok(res): mcp_encode_result(delete_claim(eff, files, clock, res))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_list_worlds": mcp_encode_result(list_worlds(rf))
    "modb_world_metrics": mcp_encode_result(get_world_metrics(rf))
    "modb_world_open":
      case Json.from_json[WorldOpenInput](args)
        Ok(inp): mcp_encode_result(post_world(eff, files, clock, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_world_query":
      case (mcp_req_text(args, "world_id"), mcp_req_text(args, "query"), args.get("args"))
        (Ok(wid), Ok(qname), Some(qargs)): mcp_encode_result(
          post_world_query(eff, files, clock, wid, WorldQueryInput(query: qname, args: qargs))
        )
        (Error(e), _, _): mcp_tool_result(Json.encode(e), true)
        (_, Error(e), _): mcp_tool_result(Json.encode(e), true)
        (_, _, None): mcp_tool_result("missing argument 'args'", true)
      end
    "modb_world_call":
      case (mcp_req_text(args, "world_id"), mcp_req_text(args, "action"), args.get("args"))
        (Ok(wid), Ok(aname), Some(aargs)): mcp_encode_result(
          post_world_call(eff, files, clock, wid, WorldCallInput(action: aname, args: aargs))
        )
        (Error(e), _, _): mcp_tool_result(Json.encode(e), true)
        (_, Error(e), _): mcp_tool_result(Json.encode(e), true)
        (_, _, None): mcp_tool_result("missing argument 'args'", true)
      end
    "modb_world_diff":
      case mcp_req_text(args, "world_id")
        Ok(wid): mcp_encode_result(get_world_diff(rf, wid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_world_land":
      case mcp_req_text(args, "world_id")
        Ok(wid): mcp_encode_result(post_world_land(eff, files, clock, wid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_world_abort":
      case mcp_req_text(args, "world_id")
        Ok(wid): mcp_encode_result(delete_world(eff, files, clock, wid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_world_telemetry": mcp_encode_result(get_world_telemetry(rf, clock))
    "modb_world_open_child":
      case (mcp_req_text(args, "parent_world_id"), Json.from_json[ChildWorldOpenInput](args))
        (Ok(pwid), Ok(inp)): mcp_encode_result(post_world_child(eff, files, clock, pwid, inp))
        (Error(e), _): mcp_tool_result(Json.encode(e), true)
        (_, Error(e)): mcp_tool_result(e.to_text, true)
      end
    "modb_world_list_children":
      case mcp_req_text(args, "parent_world_id")
        Ok(pwid): mcp_encode_result(list_world_children(rf, pwid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_world_land_child":
      case mcp_req_text(args, "world_id")
        Ok(cwid): mcp_encode_result(post_world_land_child(eff, files, clock, cwid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_world_claim_priority":
      case (mcp_req_text(args, "world_id"), Json.from_json[PriorityClaimInput](args))
        (Ok(wid), Ok(inp)): mcp_encode_result(post_world_priority(eff, files, clock, wid, inp))
        (Error(e), _): mcp_tool_result(Json.encode(e), true)
        (_, Error(e)): mcp_tool_result(e.to_text, true)
      end
    "modb_world_land_fair":
      case mcp_req_text(args, "world_id")
        Ok(wid): mcp_encode_result(post_world_land_fair(eff, files, clock, wid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_audit_log": mcp_encode_result(
      get_audit(rf, args.text_at("principal"), args.text_at("action"), None, args.int_at("limit"))
    )
    "modb_replay_calls": mcp_encode_result(get_replay_calls(rf))
    "modb_replay_simulate":
      case Json.from_json[ReplaySimulateInput](args)
        Ok(inp): mcp_encode_result(post_replay_simulate(eff, files, clock, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_list_proposals": mcp_encode_result(list_replay_proposals(rf))
    "modb_replay_accept":
      case mcp_req_text(args, "proposal_id")
        Ok(pid): mcp_encode_result(post_replay_accept(eff, files, clock, pid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_replay_discard":
      case mcp_req_text(args, "proposal_id")
        Ok(pid): mcp_encode_result(delete_replay_proposal(eff, files, clock, pid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_describe": mcp_encode_result(get_describe(eff, rf, clock, args.text_at("grant_id")))
    "modb_read_program":
      prog_json = args.get("program") or args
      case Json.from_json[Views.ReadProgram](prog_json)
        Ok(prog): mcp_encode_result(
          post_view_query(
            eff,
            files,
            clock,
            ReadProgramRequest(grant_id: args.text_at("grant_id"), program: prog)
          )
        )
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_release":
      case mcp_req_text(args, "release")
        Ok(rname): mcp_encode_result(
          post_release(
            eff,
            files,
            clock,
            rname,
            ReleaseRequest(grant_id: args.text_at("grant_id"), args: args.get("args"))
          )
        )
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_read_log": mcp_encode_result(get_reads(rf, args.int_at("limit")))
    "modb_search":
      case Json.from_json[SearchRequest](args)
        Ok(inp): mcp_encode_result(post_search(rf, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_search_stats": mcp_encode_result(get_search_stats(rf))
    _: mcp_tool_result("unknown MCP tool '#{name}'", true)
  end
end

fn post_mcp(caller: Caller, files: Files, clock: Clock, body: Json) : Result(
  Api.Response,
  WorkbenchError
)
  id_val = body.get("id") or Json.Null
  method = case body.text_at("method")
    Some(m): m
    None: return Ok(mcp_json_response(mcp_rpc_error(id_val, -32600, "missing JSON-RPC method")))
  end
  params = body.get("params") or Json.Object({})

  case method
    "initialize": Ok(
      mcp_json_response(
        mcp_rpc_ok(
          id_val,
          Json.Object({
            "protocolVersion": Json.String("2025-03-26"),
            "capabilities": Json.Object({"tools": Json.Object({})}),
            "serverInfo": Json.Object({
              "name": Json.String("modb-agent-workbench"),
              "version": Json.String("0.3.0")
            })
          })
        )
      )
    )
    "notifications/initialized": Ok(
      Api.response(200, [("content-type", "application/json")], "{}".bytes)
    )
    "ping": Ok(mcp_json_response(mcp_rpc_ok(id_val, Json.Object({}))))
    "tools/list": Ok(mcp_json_response(mcp_rpc_ok(id_val, mcp_tools_list())))
    "tools/call":
      case params.text_at("name")
        None: Ok(
          mcp_json_response(mcp_rpc_error(id_val, -32602, "tools/call requires params.name"))
        )
        Some(tname):
          targs = params.get("arguments") or Json.Object({})
          res = mcp_call_tool(caller, files, clock, tname, targs)
          Ok(mcp_json_response(mcp_rpc_ok(id_val, res)))
      end
    _: Ok(mcp_json_response(mcp_rpc_error(id_val, -32601, "method not found: #{method}")))
  end
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
        allowed_views: None,
        allowed_releases: None,
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
          allowed_views: None,
          allowed_releases: None,
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

test "AgentWorkbench Milestone 7: Inspector UI, list endpoints, demo seeder, and native MCP JSON-RPC"
  files = Files.in_memory({})
  ro = files.read_only
  t0 = Time.parse("2026-11-25T19:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  env = Env.of({
    "WB_ADMIN_TOKEN": "tok-admin",
    "WB_PLANNER_TOKEN": "tok-plan",
    "WB_WORKER_TOKEN": "tok-work"
  })

  ## 1. Live Web Inspector HTML served cleanly at GET / and GET /ui
  ui = ApiTest.send(AgentWorkbench, Api.get("/"), files, ro, clock, env)
  assert ui.status == 200
  assert ui.text.contains?("MoDB AgentWorkbench")
  assert ui.text.contains?("Replay Studio")

  ## 2. MCP initialize & tools/list over POST /mcp
  init_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(1),
        "method": Json.String("initialize")
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert init_r.status == 200
  assert init_r.text.contains?("modb-agent-workbench")

  list_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(2),
        "method": Json.String("tools/list")
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert list_r.status == 200
  assert list_r.text.contains?("modb_replay_simulate")
  assert list_r.text.contains?("modb_world_diff")

  ## 3. Seed demo via MCP tool -> inspect Grants, Worlds, O(diff), Land, and Selective-Undo Replay!
  seed_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(3),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_seed_demo"),
          "arguments": Json.Object({"reason": Json.String("mcp demo seed")})
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert seed_r.status == 200
  assert seed_r.text.contains?("w-demo-payments-401")

  ## List Grants & Worlds via HTTP inspector endpoints
  gs = ApiTest.send(AgentWorkbench, Api.get("/grants"), files, ro, clock, env)
  assert gs.status == 200 and gs.text.contains?("g-rogue-sub")
  ws = ApiTest.send(AgentWorkbench, Api.get("/worlds"), files, ro, clock, env)
  assert ws.status == 200 and ws.text.contains?("w-demo-payments-401")

  ## Inspect CoW O(diff) and Land the open demo World via MCP
  diff_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(4),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_world_diff"),
          "arguments": Json.Object({"world_id": Json.String("w-demo-payments-401")})
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert diff_r.status == 200 and
    diff_r.text.contains?("\"isError\":false") and
    diff_r.text.contains?("projects")

  land_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(5),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_world_land"),
          "arguments": Json.Object({
            "world_id": Json.String("w-demo-payments-401"),
            "reason": Json.String("land audited reconciliation")
          })
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert land_r.status == 200 and land_r.text.contains?("\"isError\":false")

  ## Simulate & Accept rogue subtree excision Replay via MCP -> unblocks 2 SRE tasks (NowAccepted)!
  sim_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(6),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_replay_simulate"),
          "arguments": Json.Object({
            "proposal_id": Json.String("mcp-undo-rogue"),
            "description": Json.String("Excise rogue grant subtree via MCP"),
            "exclude_grant": Json.String("g-team-b")
          })
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert sim_r.status == 200 and
    sim_r.text.contains?("\"isError\":false") and
    sim_r.text.contains?("now_accepted\\\":2")

  acc_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(7),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_replay_accept"),
          "arguments": Json.Object({
            "proposal_id": Json.String("mcp-undo-rogue"),
            "reason": Json.String("adopt rogue excision via MCP")
          })
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert acc_r.status == 200 and acc_r.text.contains?("\"isError\":false")

  ## Verify integrity via MCP
  ver_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(8),
        "method": Json.String("tools/call"),
        "params": Json.Object({"name": Json.String("modb_verify"), "arguments": Json.Object({})})
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert ver_r.status == 200 and
    ver_r.text.contains?("\"isError\":false") and
    ver_r.text.contains?("ok\\\":true")

  ## Milestone 8: Stateless agent onboarding (`modb_describe`), View field hiding, k-anonymous Release, & Read Log
  desc_rogue = ApiTest.send(
    AgentWorkbench,
    Api.get("/describe?grant_id=g-rogue-sub").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  )
  assert desc_rogue.status == 200
  assert Json.decode_strict[Views.OnboardingManifest](desc_rogue.text) is Ok(dm)
  assert dm.allowed_views.size == 1 and dm.allowed_releases.empty?
  dm_v0 = dm.allowed_views.first or stop "dm_v0"
  assert dm_v0.name == "tasks_public" and dm_v0.fields.size == 4

  ## Negative control: querying hidden field `billed_cents` on `tasks_public` via `g-rogue-sub` -> 403!
  bad_read = ApiTest.send(
    AgentWorkbench,
    Api.post("/views/query").with_bearer("tok-work").with_json(
      ReadProgramRequest(
        grant_id: Some("g-rogue-sub"),
        program: Views.ReadProgram(
          view: "tasks_public",
          where_clause: Some(Views.Gt(field: "billed_cents", value: Json.int(0))),
          select: None,
          group_by: None,
          aggregates: None,
          order_by: None,
          limit: None
        )
      )
    ),
    files,
    ro,
    clock,
    env
  )
  assert bad_read.status == 403

  ## Valid ad-hoc ReadProgram via MCP (`modb_read_program`) on `tasks_public` succeeds
  good_read = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-work").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(9),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_read_program"),
          "arguments": Json.Object({
            "grant_id": Json.String("g-rogue-sub"),
            "program": Views.ReadProgram(
              view: "tasks_public",
              where_clause: Some(Views.Eq(field: "project_id", value: Json.String("infra"))),
              select: Some(["id", "status"]),
              group_by: None,
              aggregates: None,
              order_by: Some(Views.SortSpec(field: "id", desc: false)),
              limit: Some(10)
            ).to_json
          })
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert good_read.status == 200 and good_read.text.contains?("\"isError\":false")

  ## Approved k-anonymous Release via MCP (`modb_release`)
  rel_ok = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-work").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(10),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_release"),
          "arguments": Json.Object({
            "grant_id": Json.String("g-sre"),
            "release": Json.String("project_budget_summary"),
            "args": Json.Object({})
          })
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert rel_ok.status == 200 and
    rel_ok.text.contains?("\"isError\":false") and
    rel_ok.text.contains?("project_count\\\":3")

  reads_r = ApiTest.send(AgentWorkbench, Api.get("/reads"), files, ro, clock, env)
  assert reads_r.status == 200 and reads_r.text.contains?("tasks_public")
end

test "AgentWorkbench Milestone 10: Key/Range O(diff) skipping, Fairness Tickets, Nested Child Worlds & MCP"
  files = Files.in_memory({})
  ro = files.read_only
  t0 = Time.parse("2026-11-25T20:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  env = Env.of({
    "WB_ADMIN_TOKEN": "tok-admin",
    "WB_PLANNER_TOKEN": "tok-plan",
    "WB_WORKER_TOKEN": "tok-work"
  })

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
    Api.post("/projects").with_bearer("tok-admin").with_header("X-Reason", "init-pay").with_json(
      ProjectInput(id: "payments", name: "Payments", budget_cents: 100000)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/projects").with_bearer("tok-admin").with_header("X-Reason", "init-sub").with_json(
      ProjectInput(id: "subproj", name: "Subproj", budget_cents: 50000)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  for tid in [401, 402, 403, 404, 405]
    assert ApiTest.send(
      AgentWorkbench,
      Api.post("/tasks").with_bearer("tok-plan").with_header("X-Reason", "seed-pay").with_json(
        CreateTaskInput(id: tid, project_id: "payments", title: "Task ##{tid}", base_cost_cents: 1000)
      ),
      files,
      ro,
      clock,
      env
    ).status ==
      200
  end
  for tid in [501, 502]
    assert ApiTest.send(
      AgentWorkbench,
      Api.post("/tasks").with_bearer("tok-plan").with_header("X-Reason", "seed-sub").with_json(
        CreateTaskInput(id: tid, project_id: "subproj", title: "Subtask ##{tid}", base_cost_cents: 2000)
      ),
      files,
      ro,
      clock,
      env
    ).status ==
      200
  end

  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/grants").with_bearer("tok-admin").with_header("X-Reason", "g-root").with_json(
      GrantInput(
        id: "g-root",
        principal: "agent:lead",
        allowed_actions: ["create_task", "complete_task"],
        allowed_views: None,
        allowed_releases: None,
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
    Api.post("/grants").with_bearer("tok-admin").with_header("X-Reason", "g-worker").with_json(
      GrantInput(
        id: "g-worker",
        principal: "agent:w1",
        allowed_actions: ["complete_task"],
        allowed_views: None,
        allowed_releases: None,
        max_calls: 10,
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
    Api.post("/grants/g-root/delegate").with_bearer("tok-plan").with_header("X-Reason", "g-child")
      .with_json(
        GrantInput(
          id: "g-child",
          principal: "agent:child",
          allowed_actions: ["complete_task"],
          allowed_views: None,
          allowed_releases: None,
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
    Api.post("/grants").with_bearer("tok-admin").with_header("X-Reason", "g-other").with_json(
      GrantInput(
        id: "g-other",
        principal: "agent:other",
        allowed_actions: ["complete_task"],
        allowed_views: None,
        allowed_releases: None,
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

  ## 1. Key-scoped & half-open range-scoped O(diff) read skipping + negative control
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds").with_bearer("tok-work").with_json(
      WorldOpenInput(id: "w-range-skip", grant_id: "g-root", ttl_seconds: 600)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-range-skip/query").with_bearer("tok-work").with_json(
      WorldQueryInput(query: "get_task", args: Json.int(401))
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-range-skip/query").with_bearer("tok-work").with_json(
      WorldQueryInput(
        query: "scan_tasks_range",
        args: TaskRangeInput(start_id: Some(402), end_id: Some(404), limit: Some(10)).to_json
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
    Api.post("/worlds/w-range-skip/call").with_bearer("tok-work").with_header("X-Reason", "skip-call")
      .with_json(
        WorldCallInput(
          action: "complete_task",
          args: CompleteTaskInput(
            task_id: 405,
            assignee: "agent:lead",
            artifact_id: None,
            artifact_summary: None,
            artifact_sha256: None
          ).to_json
        )
      ),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  ## Mutate disjoint task #404 on main line -> both get_task(401) and scan_tasks_range [402, 404) skip!
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/tasks/404/complete").with_bearer("tok-work").with_header("X-Agent-Id", "agent:direct")
      .with_header("X-Reason", "disjoint-404").with_json(
        CompleteTaskInput(
          task_id: 404,
          assignee: "agent:direct",
          artifact_id: None,
          artifact_summary: None,
          artifact_sha256: None
        )
      ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  land1 = ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-range-skip/land").with_bearer("tok-work").with_header("X-Reason", "land-skip"),
    files,
    ro,
    clock,
    env
  )
  assert land1.status == 200 and Json.decode_strict[World.LandResult](land1.text) is Ok(lr1)
  assert lr1.reads_verified == 2 and lr1.reads_skipped == 2

  ## Negative control: modifying #402 inside [401, 404) rejects stale world cleanly (409)
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds").with_bearer("tok-work").with_json(
      WorldOpenInput(id: "w-range-stale", grant_id: "g-worker", ttl_seconds: 600)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-range-stale/query").with_bearer("tok-work").with_json(
      WorldQueryInput(
        query: "scan_tasks_range",
        args: TaskRangeInput(start_id: Some(401), end_id: Some(404), limit: Some(10)).to_json
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
    Api.post("/worlds/w-range-stale/call").with_bearer("tok-work").with_header("X-Reason", "stale-call")
      .with_json(
        WorldCallInput(
          action: "complete_task",
          args: CompleteTaskInput(
            task_id: 403,
            assignee: "agent:w1",
            artifact_id: None,
            artifact_summary: None,
            artifact_sha256: None
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
    Api.post("/tasks/402/complete").with_bearer("tok-work").with_header("X-Agent-Id", "agent:direct")
      .with_header("X-Reason", "overlap-402").with_json(
        CompleteTaskInput(
          task_id: 402,
          assignee: "agent:direct",
          artifact_id: None,
          artifact_summary: None,
          artifact_sha256: None
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
    Api.post("/worlds/w-range-stale/land").with_bearer("tok-work").with_header("X-Reason", "land-stale"),
    files,
    ro,
    clock,
    env
  ).status ==
    409

  ## 2. Fairness PriorityTicket: competitor yields `deferred_by_fairness`, starved rescues cleanly
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds").with_bearer("tok-work").with_json(
      WorldOpenInput(id: "w-starved", grant_id: "g-worker", ttl_seconds: 600)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-starved/call").with_bearer("tok-work").with_header("X-Reason", "starved-call")
      .with_json(
        WorldCallInput(
          action: "complete_task",
          args: CompleteTaskInput(
            task_id: 403,
            assignee: "agent:w1",
            artifact_id: None,
            artifact_summary: None,
            artifact_sha256: None
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
    Api.post("/worlds").with_bearer("tok-work").with_json(
      WorldOpenInput(id: "w-comp", grant_id: "g-root", ttl_seconds: 600)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-comp/call").with_bearer("tok-work").with_header("X-Reason", "comp-call")
      .with_json(
        WorldCallInput(
          action: "complete_task",
          args: CompleteTaskInput(
            task_id: 401,
            assignee: "agent:lead",
            artifact_id: None,
            artifact_summary: None,
            artifact_sha256: None
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
    Api.post("/worlds/w-starved/priority").with_bearer("tok-work").with_json(
      PriorityClaimInput(buckets: ["tasks", "projects"], min_stale_threshold: Some(1), hold_seconds: 15)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  comp_defer = ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-comp/land-fair").with_bearer("tok-work").with_header("X-Reason", "comp-try"),
    files,
    ro,
    clock,
    env
  )
  assert comp_defer.status == 200 and comp_defer.text.contains?("deferred_by_fairness")
  starved_ok = ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-starved/land-fair").with_bearer("tok-work").with_header("X-Reason", "rescue-me"),
    files,
    ro,
    clock,
    env
  )
  assert starved_ok.status == 200 and starved_ok.text.contains?("landed_ok")
  comp_ok = ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-comp/land-fair").with_bearer("tok-work").with_header("X-Reason", "comp-retry"),
    files,
    ro,
    clock,
    env
  )
  assert comp_ok.status == 200 and comp_ok.text.contains?("landed_ok")

  ## 3. Nested Child Worlds + widening negative control + MCP + Replay excision
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds").with_bearer("tok-work").with_json(
      WorldOpenInput(id: "w-parent", grant_id: "g-root", ttl_seconds: 600)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-parent/children").with_bearer("tok-work").with_json(
      ChildWorldOpenInput(id: "w-bad-child", grant_id: "g-other", ttl_seconds: 300)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    403
  fork_mcp = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-work").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(100),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_world_open_child"),
          "arguments": Json.Object({
            "parent_world_id": Json.String("w-parent"),
            "id": Json.String("w-child"),
            "grant_id": Json.String("g-child"),
            "ttl_seconds": Json.int(300)
          })
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert fork_mcp.status == 200 and fork_mcp.text.contains?("\"isError\":false")

  kids_mcp = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-work").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(101),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_world_list_children"),
          "arguments": Json.Object({"parent_world_id": Json.String("w-parent")})
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert kids_mcp.status == 200 and kids_mcp.text.contains?("w-child")

  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-parent/call").with_bearer("tok-work").with_header("X-Reason", "parent-501")
      .with_json(
        WorldCallInput(
          action: "complete_task",
          args: CompleteTaskInput(
            task_id: 501,
            assignee: "agent:lead",
            artifact_id: None,
            artifact_summary: None,
            artifact_sha256: None
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
    Api.post("/worlds/w-child/query").with_bearer("tok-work").with_json(
      WorldQueryInput(query: "get_task", args: Json.int(502))
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-child/call").with_bearer("tok-work").with_header("X-Reason", "child-502")
      .with_json(
        WorldCallInput(
          action: "complete_task",
          args: CompleteTaskInput(
            task_id: 502,
            assignee: "agent:child",
            artifact_id: Some("art-502"),
            artifact_summary: Some("Child artifact"),
            artifact_sha256: Some("child502sha")
          ).to_json
        )
      ),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  cdiff_r = ApiTest.send(AgentWorkbench, Api.get("/worlds/w-child/diff"), files, ro, clock, env)
  assert cdiff_r.status == 200 and
    Json.decode_strict[List(World.BucketDiffSummary)](cdiff_r.text) is Ok(cdiff)
  assert not cdiff.empty?

  merge_mcp = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-work").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(102),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_world_land_child"),
          "arguments": Json.Object({
            "world_id": Json.String("w-child"),
            "reason": Json.String("merge child into parent")
          })
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert merge_mcp.status == 200 and
    merge_mcp.text.contains?("\"isError\":false") and
    merge_mcp.text.contains?("calls_merged\\\":1")

  land_p = ApiTest.send(
    AgentWorkbench,
    Api.post("/worlds/w-parent/land").with_bearer("tok-work").with_header("X-Reason", "land-parent"),
    files,
    ro,
    clock,
    env
  )
  assert land_p.status == 200 and Json.decode_strict[World.LandResult](land_p.text) is Ok(lr_p)
  assert lr_p.calls_replayed == 2

  tel_r = ApiTest.send(AgentWorkbench, Api.get("/worlds/telemetry"), files, ro, clock, env)
  assert tel_r.status == 200 and Json.decode_strict[WorldTelemetryResponse](tel_r.text) is Ok(tel)
  assert tel.telemetry.key_level_reads_skipped >= 2
  assert tel.telemetry.child_worlds_landed == 1
  assert tel.telemetry.fairness_tickets_issued >= 1
  assert tel.telemetry.fairness_deferrals >= 1
  assert tel.telemetry.starved_worlds_rescued >= 1
  assert tel.links.any?(fn(l) l.child_world_id == "w-child" and l.merged_into_parent? end)

  sim_child = ApiTest.send(
    AgentWorkbench,
    Api.post("/admin/replay/simulate").with_bearer("tok-admin").with_header("X-Reason", "excise-child")
      .with_json(
        ReplaySimulateInput(
          proposal_id: "prop-excise-child",
          description: "Excise attributed child grant g-child",
          exclude_principal: None,
          exclude_grant: Some("g-child"),
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
  assert sim_child.status == 200 and
    Json.decode_strict[Replay.ReplayProposal](sim_child.text) is Ok(prop_c)
  assert prop_c.summary.excluded == 1

  ## Milestone 11B: Transactional BM25 FTS, Vector, and Hybrid RRF search over tasks & artifacts
  s_stats_r = ApiTest.send(AgentWorkbench, Api.get("/search/stats"), files, ro, clock, env)
  assert s_stats_r.status == 200 and
    Json.decode_strict[SearchStatsResponse](s_stats_r.text) is Ok(s_stats)
  assert s_stats.fts.doc_count >= 2 and s_stats.vec.doc_count == s_stats.fts.doc_count

  hyb_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/search").with_json(
      SearchRequest(
        query: "failover",
        mode: Some("hybrid"),
        project_id: None,
        limit: Some(5),
        prefix_last_term: Some(true),
        vector: None
      )
    ),
    files,
    ro,
    clock,
    env
  )
  assert hyb_r.status == 200 and Json.decode_strict[SearchResponse](hyb_r.text) is Ok(hyb_res)
  assert not hyb_res.hits.empty?

  fts_mcp = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-work").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(103),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_search"),
          "arguments": Json.Object({"query": Json.String("patch"), "mode": Json.String("fts")})
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert fts_mcp.status == 200 and fts_mcp.text.contains?("\"isError\":false")
end
