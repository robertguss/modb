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
use Modb.Erasure
use Modb.Export
use Modb.Feeds
use Modb.Fts
use Modb.Grants
use Modb.Ledger
use Modb.Matview
use Modb.Policy
use Modb.Proposals
use Modb.Replay
use Modb.Table
use Modb.Taint
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

struct ClearanceInput
  grant_id: Text
  max_sensitivity: Text
end

struct PolicySummaryResponse
  clearances: List(Policy.ClearanceRecord)
  dynamic_views: List(Proposals.DynamicViewSpec)
  dynamic_releases: List(Proposals.DynamicReleaseSpec)
  dynamic_invariants: List(Proposals.DynamicInvariantSpec)
end

struct GovProposalInput
  id: Text
  kind: Text
  proposer_grant_id: Option(Text)
  description: Option(Text)
  view_name: Option(Text)
  base_view: Option(Text)
  fields: Option(List(Text))
  field_sensitivities: Option(Map(Text, Text))
  release_name: Option(Text)
  input_sensitivity: Option(Text)
  output_sensitivity: Option(Text)
  min_group_size: Option(Int)
  target_grant_id: Option(Text)
  target_clearance: Option(Text)
  invariant_name: Option(Text)
  bucket: Option(Text)
  rule_kind: Option(Text)
  field: Option(Text)
  min: Option(Int)
  max: Option(Int)
  allowed_values: Option(List(Text))
end

struct FeedSubscribeInput
  id: Text
  grant_id: Option(Text)
  buckets: Option(List(Text))
  include_internal: Option(Bool)
  from_beginning: Option(Bool)
end

struct FeedAckInput
  up_to_txid: Int
  delivered_count: Option(Int)
end

struct FeedConsumeResponse
  batch: Feeds.FeedBatch
  subscription: Feeds.FeedSubscription
end

struct TaintUntrustedInput
  source: Text
  principal: Option(Text)
  grant_id: Option(Text)
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
  ClearanceBlocked(detail: Text)
  FeedMissing(id: Text)
  FeedConflict(detail: Text)
  TaintMissing(id: Text)
  TaintBlocked(detail: Text)
  ErasureBlocked(detail: Text)
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
  get "/events/stream" get_events_stream
  get "/describe" get_describe
  post "/views/query" post_view_query
  post "/views/explain" post_view_explain
  get "/matviews" get_matviews
  post "/matviews/:name/refresh" post_matview_refresh
  get "/matviews/:name/query" get_matview_query
  post "/releases/:name" post_release
  get "/reads" get_reads
  post "/search" post_search
  get "/search/stats" get_search_stats
  post "/mcp" post_mcp

  scope "/projects"
    post "" http_post_project
    get "" list_projects
    get "/:id" get_project
    get "/:id/tasks" get_project_tasks
  end

  scope "/tasks"
    post "" http_post_task
    get "/:id" get_task
    post "/:id/complete" http_post_complete_task
    get "/:id/artifacts" get_task_artifacts
  end

  scope "/grants"
    post "" http_post_grant
    get "" list_grants
    get "/:id" get_grant
    post "/:id/delegate" http_post_delegate_grant
    post "/:id/revoke" http_post_revoke_grant
  end

  scope "/claims"
    post "" http_post_claim
    get "" list_claims
    post "/:resource/heartbeat" http_post_claim_heartbeat
    delete "/:resource" http_delete_claim
  end

  scope "/worlds"
    post "" http_post_world
    get "" list_worlds
    get "/metrics" get_world_metrics
    get "/telemetry" get_world_telemetry
    post "/:id/children" http_post_world_child
    get "/:id/children" list_world_children
    post "/:id/query" post_world_query
    post "/:id/call" http_post_world_call
    get "/:id/diff" get_world_diff
    post "/:id/land" http_post_world_land
    post "/:id/land-fair" http_post_world_land_fair
    post "/:id/land-child" http_post_world_land_child
    post "/:id/priority" http_post_world_priority
    delete "/:id" http_delete_world
  end

  get "/audit" get_audit
  post "/admin/init" http_post_admin_init
  post "/admin/demo" http_post_admin_demo
  get "/admin/verify" get_admin_verify
  get "/admin/export" get_admin_export

  scope "/admin/replay"
    get "/calls" get_replay_calls
    post "/simulate" http_post_replay_simulate
    get "/proposals" list_replay_proposals
    get "/proposals/:id" get_replay_proposal
    post "/proposals/:id/accept" http_post_replay_accept
    delete "/proposals/:id" http_delete_replay_proposal
  end

  scope "/policy"
    get "" get_policy
    post "/clearances" http_post_policy_clearance
  end

  scope "/proposals"
    get "" list_gov_proposals
    post "" http_post_gov_proposal
    post "/:id/approve" http_post_gov_proposal_approve
    post "/:id/reject" http_post_gov_proposal_reject
    post "/:id/withdraw" http_post_gov_proposal_withdraw
  end

  scope "/feeds"
    get "" list_gov_feeds
    post "" http_post_gov_feed
    get "/:id/poll" get_gov_feed_poll
    get "/:id/stream" get_gov_feed_stream
    post "/:id/ack" http_post_gov_feed_ack
    post "/:id/consume" http_post_gov_feed_consume
    delete "/:id" http_delete_gov_feed
  end

  scope "/taint"
    get "/sessions" list_taint_sessions
    post "/sessions/:id/untrusted" http_post_taint_untrusted
    post "/sessions/:id/clear" http_post_taint_clear
  end

  get "/erasures" list_erasures

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
  status ClearanceBlocked(_) = 403
  status FeedMissing(_) = 404
  status FeedConflict(_) = 409
  status TaintMissing(_) = 404
  status TaintBlocked(_) = 403
  status ErasureBlocked(_) = 403
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
  Vec.VecIndex(
    prefix: "workbench",
    config: Vec.VecConfig(dimensions: 16, metric: Vec.Cosine, encoding: Vec.Quantized8)
  )
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
  sketch = Vec.text_sketch_embedding("#{task.title} #{task.project_id} #{st_label} #{asg}", 16)
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
  sketch = Vec.text_sketch_embedding("#{art.summary} #{art.author} #{art_id}", 16)
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

fn map_policy_error(err: Policy.PolicyError) : WorkbenchError
  case err
    Policy.LedgerFailure(le): map_ledger_error(le)
    Policy.GrantFailure(ge): map_grant_error(ge)
    Policy.ViewsFailure(ve): map_views_error(ve)
    Policy.ExportFailure(ee): map_export_error(ee)
    Policy.FtsFailure(fe): map_fts_error(fe)
    Policy.VecFailure(ve): map_vec_error(ve)
    Policy.InvalidPolicy(reason: r): InvalidInput(reason: r)
    Policy.ClearanceDenied(subject: _, required: _, actual: _) | Policy.ClearanceWideningDenied(
      grant_id: _,
      parent_id: _,
      requested: _,
      parent_clearance: _
    ) | Policy.ExportBlocked(bucket: _, required: _, actual: _): ClearanceBlocked(
      detail: Policy.to_text(err)
    )
    Policy.DeclassificationDenied(
      release: _,
      input_sensitivity: _,
      output_sensitivity: _,
      min_group_size: _
    ): ReleaseBlocked(detail: Policy.to_text(err))
  end
end

fn map_proposal_error(err: Proposals.ProposalError) : WorkbenchError
  case err
    Proposals.LedgerFailure(le): map_ledger_error(le)
    Proposals.GrantFailure(ge): map_grant_error(ge)
    Proposals.PolicyFailure(pe): map_policy_error(pe)
    Proposals.InvalidProposal(reason: r): InvalidInput(reason: r)
    Proposals.ProposalAlreadyExists(id: _) | Proposals.ProposalNotPending(id: _, status: _) | Proposals
      .ExistingDataViolatesInvariant(
        name: _,
        bucket: _,
        violation_count: _,
        sample: _
      ): ProposalConflict(detail: Proposals.to_text(err))
    Proposals.ProposalNotFound(id: id): ProposalMissing(id: id)
    Proposals.ApprovalDenied(reason: r): Forbidden(required: r)
  end
end

fn map_feed_error(err: Feeds.FeedError) : WorkbenchError
  case err
    Feeds.LedgerFailure(le): map_ledger_error(le)
    Feeds.GrantFailure(ge): map_grant_error(ge)
    Feeds.PolicyFailure(pe): map_policy_error(pe)
    Feeds.InvalidFeed(reason: r): InvalidInput(reason: r)
    Feeds.FeedNotFound(id: id): FeedMissing(id: id)
    Feeds.FeedAlreadyExists(id: _) | Feeds.PinMissing(feed_id: _, pin_id: _) | Feeds.CursorStale(
      feed_id: _,
      expected_txid: _,
      actual_txid: _
    ): FeedConflict(detail: Feeds.to_text(err))
  end
end

fn map_taint_error(err: Taint.TaintError) : WorkbenchError
  case err
    Taint.LedgerFailure(le): map_ledger_error(le)
    Taint.GrantFailure(ge): map_grant_error(ge)
    Taint.PolicyFailure(pe): map_policy_error(pe)
    Taint.ViewsFailure(_) | Taint.FtsFailure(_) | Taint.VecFailure(_): StorageFailed(
      message: Taint.to_text(err)
    )
    Taint.InvalidSession(reason: _) | Taint.SessionAlreadyExists(id: _) | Taint.SessionClosed(
      id: _
    ): InvalidInput(reason: Taint.to_text(err))
    Taint.SessionNotFound(id: sid): TaintMissing(id: sid)
    Taint.ClearDenied(reason: r): Forbidden(required: r)
    Taint.TaintedReadEscalationBlocked(
      session_id: _,
      subject: _,
      required: _,
      capped_clearance: _,
      untrusted_sources: _
    ) | Taint.LethalTrifectaBlocked(
      session_id: _,
      target: _,
      max_sensitivity_read: _,
      untrusted_sources: _,
      reason: _
    ): TaintBlocked(detail: Taint.to_text(err))
  end
end

fn map_erasure_error(err: Erasure.ErasureError) : WorkbenchError
  case err
    Erasure.LedgerFailure(le): map_ledger_error(le)
    Erasure.ExportFailure(_) | Erasure.FtsFailure(_) | Erasure.VecFailure(_) | Erasure
      .CryptoFailure(detail: _): StorageFailed(message: Erasure.to_text(err))
    Erasure.InvalidRequest(reason: _) | Erasure.KeyNotFound(subject_id: _) | Erasure
      .ReceiptAlreadyExists(id: _) | Erasure.ReceiptNotFound(id: _): InvalidInput(
      reason: Erasure.to_text(err)
    )
    Erasure.KeyShredded(subject_id: _): ErasureBlocked(detail: Erasure.to_text(err))
    Erasure.ErasureDenied(reason: r): Forbidden(required: r)
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
    t3 = case (body.artifact_id, body.artifact_summary, body.artifact_sha256)
      (Some(aid), Some(sum), Some(sha)):
        art = Artifact(task_id: body.task_id, author: body.assignee, summary: sum, sha256: sha)
        ta = try Table.put(t2, arts, aid, art).map_error(fn(e) e.to_text end)
        try tx_index_workbench_artifact(ta, aid, task.project_id, art).map_error(fn(e) e.to_text end)
      _: t2
    end
    Ok((t3, task_to_row(body.task_id, next_task).to_json))
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
  cat_with_docs = Views.catalog().with_view(
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
  # Register Milestone 15 ViewIndexes on secondary & primary keys for O(k) ReadPrograms
  with_task_view_indexes(with_project_view_indexes(cat_with_docs))
end

fn task_map_full(tid: Int, t: Task) : Map(Text, Json)
  asg = case t.assignee
    Some(a): Json.String(a)
    None: Json.Null
  end
  {
    "id": Json.int(tid),
    "project_id": Json.String(t.project_id),
    "title": Json.String(t.title),
    "assignee": asg,
    "base_cost_cents": Json.int(t.base_cost_cents),
    "billed_cents": Json.int(t.billed_cents),
    "status": Json.String(task_status_label(t.status))
  }
end

fn task_map_public(tid: Int, t: Task) : Map(Text, Json)
  {
    "id": Json.int(tid),
    "project_id": Json.String(t.project_id),
    "title": Json.String(t.title),
    "status": Json.String(task_status_label(t.status))
  }
end

fn json_text_key(jv: Json) : Text
  case jv
    Json.String(s): s
    Json.Null | Json.Boolean(_) | Json.Number(_) | Json.Array(_) | Json.Object(_): jv.to_text
  end
end

fn proj_map_full(pid: Text, p: Project) : Map(Text, Json)
  pr = project_to_row(pid, p)
  {
    "id": Json.String(pr.id),
    "name": Json.String(pr.name),
    "budget_cents": Json.int(pr.budget_cents),
    "spent_cents": Json.int(pr.spent_cents),
    "remaining_cents": Json.int(pr.remaining_cents),
    "active": Json.Boolean(pr.active)
  }
end

fn proj_map_public(pid: Text, p: Project) : Map(Text, Json)
  {"id": Json.String(pid), "name": Json.String(p.name), "active": Json.Boolean(p.active)}
end

fn reg_project_view_index(
  cat: Views.ViewCatalog,
  vname: Text,
  map_fn: fn(Text, Project) : Map(Text, Json)
) : Views.ViewCatalog
  projs = projects_table()
  Views.with_view_range_index(
    cat,
    vname,
    "id",
    fn(store, jv)
      k = json_text_key(jv)
      case try Table.get(store, projs, k).map_error(fn(e) e.to_text end)
        Some(p): Ok([map_fn(k, p)])
        None: Ok([])
      end
    end,
    fn(store, lo_opt, hi_opt, _lo_inc, hi_inc)
      lo_k = lo_opt.map(json_text_key)
      hi_k = case hi_opt
        Some(jv):
          s = json_text_key(jv)
          Some(if hi_inc: "#{s}\u{10ffff}" else: s)
        None: None
      end
      rows = try Table.scan(store, projs, lo_k, hi_k, 0).map_error(fn(e) e.to_text end)
      Ok(rows.map(fn(pair) map_fn(pair.0, pair.1) end))
    end
  )
end

fn with_project_view_indexes(cat: Views.ViewCatalog) : Views.ViewCatalog
  reg_project_view_index(
    reg_project_view_index(cat, "projects_finance", proj_map_full),
    "projects_public",
    proj_map_public
  )
end

fn reg_task_view_indexes(
  cat: Views.ViewCatalog,
  vname: Text,
  map_fn: fn(Int, Task) : Map(Text, Json)
) : Views.ViewCatalog
  tasks = tasks_table()
  p_idx = tasks_by_project_index()
  s_idx = tasks_by_status_index()
  c1 = Views.with_view_range_index(
    cat,
    vname,
    "id",
    fn(store, jv)
      case Json.Object({"v": jv}).int_at("v")
        None: Ok([])
        Some(tid):
          case try Table.get(store, tasks, tid).map_error(fn(e) e.to_text end)
            Some(t): Ok([map_fn(tid, t)])
            None: Ok([])
          end
      end
    end,
    fn(store, lo_opt, hi_opt, lo_inc, hi_inc)
      lo_k = case lo_opt
        Some(jv):
          case Json.Object({"v": jv}).int_at("v")
            Some(iv): Some(if lo_inc: iv else: iv + 1)
            None: None
          end
        None: None
      end
      hi_k = case hi_opt
        Some(jv):
          case Json.Object({"v": jv}).int_at("v")
            Some(iv): Some(if hi_inc: iv + 1 else: iv)
            None: None
          end
        None: None
      end
      rows = try Table.scan(store, tasks, lo_k, hi_k, 0).map_error(fn(e) e.to_text end)
      Ok(rows.map(fn(pair) map_fn(pair.0, pair.1) end))
    end
  )
  c2 = Views.with_view_eq_index(
    c1,
    vname,
    "project_id",
    fn(store, jv)
      rows = try Table.lookup(store, tasks, p_idx, json_text_key(jv)).map_error(fn(e) e.to_text end)
      Ok(rows.map(fn(pair) map_fn(pair.0, pair.1) end))
    end
  )
  Views.with_view_eq_index(
    c2,
    vname,
    "status",
    fn(store, jv)
      rows = try Table.lookup(store, tasks, s_idx, json_text_key(jv)).map_error(fn(e) e.to_text end)
      Ok(rows.map(fn(pair) map_fn(pair.0, pair.1) end))
    end
  )
end

fn with_task_view_indexes(cat: Views.ViewCatalog) : Views.ViewCatalog
  reg_task_view_indexes(
    reg_task_view_indexes(cat, "tasks_finance", task_map_full),
    "tasks_public",
    task_map_public
  )
end

## Milestone 12 Sensitivity & Declassification Policy for AgentWorkbench.
fn workbench_policy() : Policy.SensitivityPolicy
  Policy.policy().with_default_clearance(Policy.Public).with_bucket_sensitivity(
    "projects",
    Policy.Internal
  ).with_bucket_sensitivity("tasks", Policy.Internal).with_bucket_sensitivity(
    "artifacts",
    Policy.Internal
  ).with_bucket_sensitivity("secrets", Policy.Secret).with_view_field_sensitivity(
    "tasks_finance",
    "assignee",
    Policy.Internal
  ).with_view_field_sensitivity("tasks_finance", "base_cost_cents", Policy.Confidential)
    .with_view_field_sensitivity("tasks_finance", "billed_cents", Policy.Confidential)
    .with_view_field_sensitivity("projects_finance", "budget_cents", Policy.Confidential)
    .with_view_field_sensitivity("projects_finance", "spent_cents", Policy.Confidential)
    .with_view_field_sensitivity("projects_finance", "remaining_cents", Policy.Confidential)
    .with_scope_sensitivity("restricted", Policy.Confidential).with_scope_sensitivity(
      "vault",
      Policy.Secret
    ).with_release_policy(
      "project_budget_summary",
      Policy.ReleasePolicy(
        input_sensitivity: Policy.Confidential,
        output_sensitivity: Policy.Public,
        min_group_size: 2
      )
    ).with_release_policy(
      "task_cost_by_status",
      Policy.ReleasePolicy(
        input_sensitivity: Policy.Confidential,
        output_sensitivity: Policy.Public,
        min_group_size: 2
      )
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
          t3 = case (body.artifact_id, body.artifact_summary, body.artifact_sha256)
            (Some(aid), Some(sum), Some(sha)):
              art = Artifact(task_id: id, author: body.assignee, summary: sum, sha256: sha)
              ta = try Table.put(t2, arts, aid, art).map_error(map_table_error)
              try tx_index_workbench_artifact(ta, aid, task.project_id, art).map_error(
                map_table_error
              )
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
          None: Vec.text_sketch_embedding(body.query, 16)
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
              Some(Vec.text_sketch_embedding(body.query, 16))
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
  _ = try Policy.set_clearance_locked(
    files,
    db_path(),
    workbench_schema(),
    workbench_policy(),
    Ledger.WriteMeta(
      principal: admin.principal,
      action: "policy_set_clearance",
      reason: "seed SRE confidential clearance",
      at: clock.now
    ),
    "g-sre",
    Policy.Confidential,
    clock.now
  ).map_error(map_policy_error)

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
  base_cat = workbench_view_catalog()
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      live_cat = try Proposals.materialize_catalog(Ledger.store(db), base_cat).map_error(
        map_proposal_error
      )
      Views.describe_for_caller(
        db,
        live_cat,
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
  now = clock.now
  base_cat = workbench_view_catalog()
  base_pol = workbench_policy()
  Ledger.locked(
    files,
    db_path(),
    workbench_schema(),
    now,
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      live_cat = try Proposals.materialize_catalog(st, base_cat).map_error(map_proposal_error)
      live_pol = try Proposals.materialize_policy(st, base_pol).map_error(map_proposal_error)
      (_next, gov, _log) = try Policy.execute_read_program_governed_recorded(
        db,
        live_cat,
        live_pol,
        body.program,
        caller.principal,
        body.grant_id,
        is_admin?,
        Views.default_limits(),
        now
      ).map_error(map_policy_error)
      Ok(gov.result)
    end
  )
end

fn post_view_explain(
  caller: Caller,
  files: Files,
  clock: Clock,
  body: ReadProgramRequest
) : Result(Json, WorkbenchError)
  is_admin? = caller.role is Admin
  now = clock.now
  base_cat = workbench_view_catalog()
  Ledger.read_locked(
    files.read_only,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      live_cat = try Proposals.materialize_catalog(st, base_cat).map_error(map_proposal_error)
      narrows = Views.view_narrows_map(live_cat)
      _g = case body.grant_id
        Some(gid): Some(
          try Grants.verify_view(st, gid, body.program.view, narrows, now).map_error(map_grant_error)
        )
        None:
          if not is_admin?
            return Error(Forbidden(required: "Admin role or valid scoped Grant required for View explain"))
          end
          None
      end
      Views.explain_read_program(live_cat, body.program).map_error(map_views_error)
    end
  )
end

fn map_matview_error(err: Matview.MatViewError) : WorkbenchError
  case err
    Matview.Storage(e): StorageFailed(message: e.to_text)
    Matview.TableFailure(te): map_table_error(te)
    Matview.UnknownMatView(name: n): ViewMissing(name: n)
    Matview.InvalidDefinition(reason: r): InvalidInput(reason: r)
  end
end

fn default_workbench_matview_defs() : List(Matview.MatViewDef)
  [
    Matview.MatViewDef(
      name: "tasks_by_status",
      description: "Incremental materialized summary of tasks grouped by status (count, total billed_cents, min/max base_cost_cents)",
      source_bucket: "tasks",
      group_by: "status",
      aggregates: [
        Matview.MatAggSpec(alias: "cnt", op: Matview.MatCount),
        Matview.MatAggSpec(alias: "total_billed_cents", op: Matview.MatSum(field: "billed_cents")),
        Matview.MatAggSpec(alias: "min_base_cents", op: Matview.MatMin(field: "base_cost_cents")),
        Matview.MatAggSpec(alias: "max_base_cents", op: Matview.MatMax(field: "base_cost_cents"))
      ]
    ),
    Matview.MatViewDef(
      name: "tasks_by_project",
      description: "Incremental materialized task rollup grouped by project_id",
      source_bucket: "tasks",
      group_by: "project_id",
      aggregates: [
        Matview.MatAggSpec(alias: "cnt", op: Matview.MatCount),
        Matview.MatAggSpec(alias: "total_billed_cents", op: Matview.MatSum(field: "billed_cents")),
        Matview.MatAggSpec(alias: "total_base_cents", op: Matview.MatSum(field: "base_cost_cents"))
      ]
    )
  ]
end

fn ensure_default_matviews_store(store: Modb.Store) : Result(Modb.Store, WorkbenchError)
  var cur = store
  for mdef in default_workbench_matview_defs()
    ex = try Matview.get_matview(cur, mdef.name).map_error(map_matview_error)
    if ex is None
      (next_st, _meta) = try Matview.define_matview(cur, mdef).map_error(map_matview_error)
      cur = next_st
    end
  end
  Ok(cur)
end

fn ensure_default_matviews_files(files: Files) : Result(List(Matview.MatViewMeta), WorkbenchError)
  cur_mvs = try Modb.with_shared_lock(
    files.read_only,
    db_path(),
    fn(e) StorageFailed(message: e.to_text) end,
    fn(st) Matview.list_matviews(st).map_error(map_matview_error) end
  )
  if cur_mvs.size >= default_workbench_matview_defs().size
    return Ok(cur_mvs)
  end
  Modb.with_exclusive_lock(
    files,
    db_path(),
    fn(e) StorageFailed(message: e.to_text) end,
    fn(st)
      s2 = try ensure_default_matviews_store(st)
      Matview.list_matviews(s2).map_error(map_matview_error)
    end
  )
end

fn get_matviews(files: Files) : Result(
  List(Matview.MatViewMeta),
  WorkbenchError
)
  ensure_default_matviews_files(files)
end

fn post_matview_refresh(caller: Caller, files: Files, name: Text) : Result(
  Api.Response,
  WorkbenchError
)
  _auth = caller
  rep = try Modb.with_exclusive_lock(
    files,
    db_path(),
    fn(e) StorageFailed(message: e.to_text) end,
    fn(st)
      s1 = try ensure_default_matviews_store(st)
      (_s2, r) = try Matview.refresh_matview(s1, name).map_error(map_matview_error)
      Ok(r)
    end
  )
  Ok(
    Api.with_sse_publish_json(
      Api.json_response(200, rep),
      "workbench",
      "matview.refreshed",
      rep.to_json
    )
  )
end

fn get_matview_query(
  files: Files,
  name: Text,
  min_k: Option(Int)
) : Result(Matview.MatQueryResult, WorkbenchError)
  _ = try ensure_default_matviews_files(files)
  Modb.with_shared_lock(
    files.read_only,
    db_path(),
    fn(e) StorageFailed(message: e.to_text) end,
    fn(st) Matview.query_matview(st, name, min_k).map_error(map_matview_error) end
  )
end

fn post_release(caller: Caller, files: Files, clock: Clock, name: Text, body: ReleaseRequest) : Result(
  Views.ReleaseResult,
  WorkbenchError
)
  is_admin? = caller.role is Admin
  now = clock.now
  base_cat = workbench_view_catalog()
  base_pol = workbench_policy()
  args = body.args or Json.Object({})
  Ledger.locked(
    files,
    db_path(),
    workbench_schema(),
    now,
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      live_cat = try Proposals.materialize_catalog(st, base_cat).map_error(map_proposal_error)
      live_pol = try Proposals.materialize_policy(st, base_pol).map_error(map_proposal_error)
      (_next, res, _log) = try Policy.execute_release_governed_recorded(
        db,
        live_cat,
        live_pol,
        name,
        args,
        caller.principal,
        body.grant_id,
        is_admin?,
        now
      ).map_error(map_policy_error)
      Ok(res)
    end
  )
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
## Milestone 12: Sensitivity Clearances, Governance Proposals, & Reactive Feeds
## ---------------------------------------------------------------------------
fn parse_sensitivity_arg(raw: Text) : Result(Policy.Sensitivity, WorkbenchError)
  Policy.sensitivity_from_text(raw).or_fail(
    InvalidInput(reason: "invalid sensitivity '#{raw}' (expected public|internal|confidential|secret)")
  )
end

fn get_policy(rf: ReadFiles) : Result(PolicySummaryResponse, WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      clrs = try Policy.list_clearances(st).map_error(map_policy_error)
      dviews = try Proposals.list_dynamic_views(st).map_error(map_proposal_error)
      drels = try Proposals.list_dynamic_releases(st).map_error(map_proposal_error)
      dinvs = try Proposals.list_dynamic_invariants(st).map_error(map_proposal_error)
      Ok(
        PolicySummaryResponse(
          clearances: clrs,
          dynamic_views: dviews,
          dynamic_releases: drels,
          dynamic_invariants: dinvs
        )
      )
    end
  )
end

fn post_policy_clearance(caller: Caller, files: Files, clock: Clock, body: ClearanceInput) : Result(
  Policy.ClearanceRecord,
  WorkbenchError
)
  try require_admin(caller)
  sens = try parse_sensitivity_arg(body.max_sensitivity)
  meta = try write_meta(caller, "policy_set_clearance", clock)
  Policy.set_clearance_locked(
    files,
    db_path(),
    workbench_schema(),
    workbench_policy(),
    meta,
    body.grant_id,
    sens,
    clock.now
  ).map_error(map_policy_error)
end

fn parse_proposal_kind(inp: GovProposalInput) : Result(Proposals.ProposalKind, WorkbenchError)
  k = Text.from_chars(inp.kind.trim.chars.map(fn(c) c.ascii_lowercase end))
  desc = inp.description or "agent proposal"
  if k == "view"
    vname = try inp.view_name.or_fail(InvalidInput(reason: "view proposal requires 'view_name'"))
    bview = try inp.base_view.or_fail(InvalidInput(reason: "view proposal requires 'base_view'"))
    flds = try inp.fields.or_fail(InvalidInput(reason: "view proposal requires 'fields'"))
    var fsens = {}
    case inp.field_sensitivities
      Some(m):
        for (fname, sval) in m.entries
          ps = try parse_sensitivity_arg(sval)
          fsens = fsens.set(fname, ps)
        end
      None: Unit
    end
    Ok(
      Proposals.ProposeView(
        spec: Proposals.DynamicViewSpec(
          name: vname,
          description: desc,
          base_view: bview,
          fields: flds,
          field_sensitivities: fsens
        )
      )
    )
  else if k == "release_policy"
    rname = try inp.release_name.or_fail(
      InvalidInput(reason: "release_policy proposal requires 'release_name'")
    )
    in_s = try parse_sensitivity_arg(inp.input_sensitivity or "confidential")
    out_s = try parse_sensitivity_arg(inp.output_sensitivity or "public")
    min_k = inp.min_group_size or 2
    Ok(
      Proposals.ProposeReleasePolicy(
        spec: Proposals.DynamicReleaseSpec(
          release_name: rname,
          description: desc,
          input_sensitivity: in_s,
          output_sensitivity: out_s,
          min_group_size: min_k
        )
      )
    )
  else if k == "clearance"
    tg = case inp.target_grant_id
      Some(g): g
      None: try inp.proposer_grant_id.or_fail(
        InvalidInput(reason: "clearance proposal requires 'target_grant_id'")
      )
    end
    tc = try parse_sensitivity_arg(
      try inp.target_clearance.or_fail(
        InvalidInput(reason: "clearance proposal requires 'target_clearance'")
      )
    )
    Ok(Proposals.ProposeClearance(grant_id: tg, target_clearance: tc, justification: desc))
  else if k == "invariant"
    iname = try inp.invariant_name.or_fail(
      InvalidInput(reason: "invariant proposal requires 'invariant_name'")
    )
    bname = try inp.bucket.or_fail(InvalidInput(reason: "invariant proposal requires 'bucket'"))
    rk = Text.from_chars((inp.rule_kind or "non_empty").trim.chars.map(fn(c) c.ascii_lowercase end))
    fld = try inp.field.or_fail(InvalidInput(reason: "invariant proposal requires 'field'"))
    rule = if rk == "non_empty"
      Proposals.FieldNonEmpty(field: fld)
    else if rk == "int_range"
      Proposals.IntRange(field: fld, min: inp.min, max: inp.max)
    else if rk == "allowed_values"
      vs = try inp.allowed_values.or_fail(
        InvalidInput(reason: "allowed_values rule requires 'allowed_values'")
      )
      Proposals.AllowedValues(field: fld, values: vs)
    else
      return Error(
        InvalidInput(
          reason: "unknown invariant rule_kind '#{rk}' (expected non_empty|int_range|allowed_values)"
        )
      )
    end
    Ok(
      Proposals.ProposeInvariant(
        spec: Proposals.DynamicInvariantSpec(
          name: iname,
          description: desc,
          bucket: bname,
          rule: rule
        )
      )
    )
  else
    Error(
      InvalidInput(
        reason: "unknown proposal kind '#{inp.kind}' (expected view|release_policy|clearance|invariant)"
      )
    )
  end
end

fn list_gov_proposals(rf: ReadFiles, status: Option(Text)) : Result(
  List(Proposals.GovernanceProposal),
  WorkbenchError
)
  st_opt = case status
    None: None
    Some(raw) if raw.trim.empty?: None
    Some(raw):
      norm = Text.from_chars(raw.trim.chars.map(fn(c) c.ascii_lowercase end))
      if norm == "pending"
        Some(Proposals.Pending)
      else if norm == "approved"
        Some(Proposals.Approved)
      else if norm == "rejected"
        Some(Proposals.Rejected)
      else if norm == "withdrawn"
        Some(Proposals.Withdrawn)
      else
        return Error(InvalidInput(reason: "unknown proposal status '#{raw}'"))
      end
  end
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) Proposals.list_proposals(Ledger.store(db), st_opt).map_error(map_proposal_error) end
  )
end

fn post_gov_proposal(caller: Caller, files: Files, clock: Clock, body: GovProposalInput) : Result(
  Proposals.GovernanceProposal,
  WorkbenchError
)
  kind = try parse_proposal_kind(body)
  reason = (caller.reason or "").trim
  eff_reason = if reason.empty?: "submit proposal" else: reason
  base_cat = workbench_view_catalog()
  base_pol = workbench_policy()
  now = clock.now
  Ledger.locked(
    files,
    db_path(),
    workbench_schema(),
    now,
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      live_cat = try Proposals.materialize_catalog(st, base_cat).map_error(map_proposal_error)
      live_pol = try Proposals.materialize_policy(st, base_pol).map_error(map_proposal_error)
      (_next, prop) = try Proposals.submit_proposal(
        db,
        live_cat,
        live_pol,
        body.id,
        kind,
        caller.principal,
        body.proposer_grant_id,
        eff_reason,
        now
      ).map_error(map_proposal_error)
      Ok(prop)
    end
  )
end

fn post_gov_proposal_approve(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Proposals.GovernanceProposal,
  WorkbenchError
)
  try require_admin(caller)
  note = (caller.reason or "").trim
  eff_note = if note.empty?: "approved by #{caller.principal}" else: note
  base_cat = workbench_view_catalog()
  base_pol = workbench_policy()
  now = clock.now
  Ledger.locked(
    files,
    db_path(),
    workbench_schema(),
    now,
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      live_cat = try Proposals.materialize_catalog(st, base_cat).map_error(map_proposal_error)
      live_pol = try Proposals.materialize_policy(st, base_pol).map_error(map_proposal_error)
      (_next, prop) = try Proposals.approve_proposal(
        db,
        live_cat,
        live_pol,
        id,
        caller.principal,
        true,
        eff_note,
        now
      ).map_error(map_proposal_error)
      Ok(prop)
    end
  )
end

fn post_gov_proposal_reject(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Proposals.GovernanceProposal,
  WorkbenchError
)
  try require_admin(caller)
  note = (caller.reason or "").trim
  eff_note = if note.empty?: "rejected by #{caller.principal}" else: note
  Proposals.reject_proposal_locked(
    files,
    db_path(),
    workbench_schema(),
    id,
    caller.principal,
    true,
    eff_note,
    clock.now
  ).map_error(map_proposal_error)
end

fn post_gov_proposal_withdraw(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Proposals.GovernanceProposal,
  WorkbenchError
)
  is_admin? = caller.role is Admin
  note = (caller.reason or "").trim
  eff_note = if note.empty?: "withdrawn by #{caller.principal}" else: note
  Proposals.withdraw_proposal_locked(
    files,
    db_path(),
    workbench_schema(),
    id,
    caller.principal,
    is_admin?,
    eff_note,
    clock.now
  ).map_error(map_proposal_error)
end

fn list_gov_feeds(rf: ReadFiles) : Result(List(Feeds.FeedSubscription), WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) Feeds.list_feeds(Ledger.store(db)).map_error(map_feed_error) end
  )
end

fn post_gov_feed(caller: Caller, files: Files, clock: Clock, body: FeedSubscribeInput) : Result(
  Feeds.FeedSubscription,
  WorkbenchError
)
  reason = (caller.reason or "").trim
  eff_reason = if reason.empty?: "subscribe change feed '#{body.id}'" else: reason
  spec = Feeds.FeedSpec(
    id: body.id,
    principal: caller.principal,
    grant_id: body.grant_id,
    buckets: body.buckets or [],
    include_internal: body.include_internal or false,
    from_beginning: body.from_beginning or false
  )
  Feeds.subscribe_locked(files, db_path(), workbench_schema(), spec, eff_reason, clock.now).map_error(
    map_feed_error
  )
end

fn get_gov_feed_poll(caller: Caller, rf: ReadFiles, clock: Clock, id: Text, limit: Option(Int)) : Result(
  Feeds.FeedBatch,
  WorkbenchError
)
  is_admin? = caller.role is Admin
  lim = limit or 100
  base_pol = workbench_policy()
  now = clock.now
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      live_pol = try Proposals.materialize_policy(st, base_pol).map_error(map_proposal_error)
      Feeds.poll_feed(st, live_pol, id, is_admin?, lim, now).map_error(map_feed_error)
    end
  )
end

fn post_gov_feed_ack(caller: Caller, files: Files, clock: Clock, id: Text, body: FeedAckInput) : Result(
  Feeds.FeedSubscription,
  WorkbenchError
)
  _ = caller
  Feeds.ack_feed_locked(
    files,
    db_path(),
    workbench_schema(),
    id,
    body.up_to_txid,
    body.delivered_count or 0,
    clock.now
  ).map_error(map_feed_error)
end

fn post_gov_feed_consume(caller: Caller, files: Files, clock: Clock, id: Text, limit: Option(Int)) : Result(
  FeedConsumeResponse,
  WorkbenchError
)
  is_admin? = caller.role is Admin
  lim = limit or 100
  base_pol = workbench_policy()
  now = clock.now
  Ledger.locked(
    files,
    db_path(),
    workbench_schema(),
    now,
    map_ledger_error,
    fn(db)
      live_pol = try Proposals.materialize_policy(Ledger.store(db), base_pol).map_error(
        map_proposal_error
      )
      (_next, batch, sub) = try Feeds.consume_feed(db, live_pol, id, is_admin?, lim, now).map_error(
        map_feed_error
      )
      Ok(FeedConsumeResponse(batch: batch, subscription: sub))
    end
  )
end

fn delete_gov_feed(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  OkStatus,
  WorkbenchError
)
  meta = try write_meta(caller, "feed_unsubscribe", clock)
  _ = try Feeds.unsubscribe_locked(files, db_path(), workbench_schema(), id, meta).map_error(
    map_feed_error
  )
  Ok(OkStatus(ok: true))
end

fn list_taint_sessions(rf: ReadFiles) : Result(List(Taint.TaintSession), WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) Taint.list_sessions(Ledger.store(db)).map_error(map_taint_error) end
  )
end

fn post_taint_untrusted(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  body: TaintUntrustedInput
) : Result(Taint.TaintSession, WorkbenchError)
  now = clock.now
  eff_p = case body.principal
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: caller.principal
  end
  _s0 = try Taint.ensure_session_locked(
    files,
    db_path(),
    workbench_schema(),
    id,
    eff_p,
    body.grant_id,
    now
  ).map_error(map_taint_error)
  Taint.record_untrusted_read_locked(files, db_path(), workbench_schema(), id, body.source, now)
    .map_error(map_taint_error)
end

fn post_taint_clear(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Taint.TaintSession,
  WorkbenchError
)
  try require_admin(caller)
  note = (caller.reason or "").trim
  eff_reason = if note.empty?: "admin cleared taint on '#{id}'" else: note
  Taint.clear_session_taint_locked(
    files,
    db_path(),
    workbench_schema(),
    id,
    caller.principal,
    true,
    eff_reason,
    clock.now
  ).map_error(map_taint_error)
end

fn list_erasures(rf: ReadFiles) : Result(List(Erasure.ErasureReceipt), WorkbenchError)
  Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db) Erasure.list_erasure_receipts(Ledger.store(db)).map_error(map_erasure_error) end
  )
end

## ---------------------------------------------------------------------------
## Milestone 14: Cross-Worker Real-Time SSE Push (`SseBroker`)
## ---------------------------------------------------------------------------
fn current_txid_quiet(rf: ReadFiles) : Int
  case Ledger.read_locked(rf, db_path(), workbench_schema(), map_ledger_error, fn(db)
    Ok(Ledger.txid(db))
  end)
    Ok(n): n
    Error(_): 0
  end
end

fn publish_workbench_commit(
  res: Api.Response,
  rf: ReadFiles,
  event: Text,
  action: Text,
  buckets: List(Text),
  extra_topic: Option((Text, Text))
) : Api.Response
  txid = current_txid_quiet(rf)
  sig = Feeds.commit_signal_json(txid, buckets, action)
  var out = Api.with_sse_publish_json(res, "workbench", event, sig)
  var pub_wild? = false
  for b in buckets
    clean = b.trim
    if not clean.empty?
      out = Api.with_sse_publish_json(out, Feeds.bucket_topic(clean), "feed.delta", sig)
      if clean != Feeds.feeds_bucket and clean != Modb.pins_bucket
        pub_wild? = true
      end
    end
  end
  if pub_wild?
    out = Api.with_sse_publish_json(out, "bucket:*", "feed.delta", sig)
  end
  case extra_topic
    Some((topic, tevt)): Api.with_sse_publish_json(out, topic, tevt, sig)
    None: out
  end
end

fn json_ok_response(val: T) : Api.Response where T: Json
  Api.response(200, [("content-type", "application/json")], Json.encode(val).bytes)
end

fn json_sse(
  val: T,
  rf: ReadFiles,
  event: Text,
  action: Text,
  buckets: List(Text)
) : Api.Response where T: Json
  publish_workbench_commit(json_ok_response(val), rf, event, action, buckets, None)
end

fn req_last_event_id(req: Api.Request) : Option(Text)
  case req.header("Last-Event-ID")
    Some(v): Some(v)
    None: req.header("last-event-id")
  end
end

fn get_events_stream(rf: ReadFiles, req: Api.Request) : Result(Api.Response, WorkbenchError)
  h = try get_health(rf)
  last_id = req_last_event_id(req)
  Ok(
    Api.sse_stream_with(
      ["workbench"],
      last_id,
      Some(2000),
      [(Some("health"), Json.encode(h))]
    )
  )
end

fn get_gov_feed_stream(
  caller: Caller,
  rf: ReadFiles,
  clock: Clock,
  req: Api.Request,
  id: Text,
  limit: Option(Int)
) : Result(Api.Response, WorkbenchError)
  is_admin? = caller.role is Admin
  lim = limit or 100
  now = clock.now
  pol = workbench_policy()
  (sub, batch) = try Ledger.read_locked(
    rf,
    db_path(),
    workbench_schema(),
    map_ledger_error,
    fn(db)
      st = Ledger.store(db)
      sub_opt = try Feeds.get_feed(st, id).map_error(map_feed_error)
      sub = try sub_opt.or_fail(FeedMissing(id: id))
      batch = try Feeds.poll_feed(st, pol, id, is_admin?, lim, now).map_error(map_feed_error)
      Ok((sub, batch))
    end
  )
  topics = Feeds.feed_subscribe_topics(sub)
  last_id = req_last_event_id(req)
  Ok(
    Api.sse_stream_with(
      topics,
      last_id,
      Some(2000),
      [(Some("feed.snapshot"), Json.encode(batch))]
    )
  )
end

fn http_post_project(caller: Caller, files: Files, clock: Clock, body: ProjectInput) : Result(
  Api.Response,
  WorkbenchError
)
  row = try post_project(caller, files, clock, body)
  Ok(json_sse(row, files.read_only, "project.created", "create_project", ["projects"]))
end

fn http_post_task(caller: Caller, files: Files, clock: Clock, body: CreateTaskInput) : Result(
  Api.Response,
  WorkbenchError
)
  row = try post_task(caller, files, clock, body)
  Ok(json_sse(row, files.read_only, "task.created", "create_task", ["tasks"]))
end

fn http_post_complete_task(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Int,
  body: CompleteTaskInput
) : Result(Api.Response, WorkbenchError)
  row = try post_complete_task(caller, files, clock, id, body)
  Ok(
    json_sse(
      row,
      files.read_only,
      "task.completed",
      "complete_task",
      ["tasks", "projects", "artifacts"]
    )
  )
end

fn http_post_grant(caller: Caller, files: Files, clock: Clock, body: GrantInput) : Result(
  Api.Response,
  WorkbenchError
)
  g = try post_grant(caller, files, clock, body)
  Ok(json_sse(g, files.read_only, "grant.issued", "issue_grant", [Grants.grants_bucket]))
end

fn http_post_delegate_grant(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  body: GrantInput
) : Result(Api.Response, WorkbenchError)
  g = try post_delegate_grant(caller, files, clock, id, body)
  Ok(json_sse(g, files.read_only, "grant.delegated", "delegate_grant", [Grants.grants_bucket]))
end

fn http_post_revoke_grant(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  g = try post_revoke_grant(caller, files, clock, id)
  Ok(json_sse(g, files.read_only, "grant.revoked", "revoke_grant", [Grants.grants_bucket]))
end

fn http_post_claim(caller: Caller, files: Files, clock: Clock, body: ClaimInput) : Result(
  Api.Response,
  WorkbenchError
)
  c = try post_claim(caller, files, clock, body)
  Ok(json_sse(c, files.read_only, "claim.acquired", "acquire_claim", [Claims.claims_bucket]))
end

fn http_post_claim_heartbeat(
  caller: Caller,
  files: Files,
  clock: Clock,
  resource: Text,
  body: HeartbeatInput
) : Result(Api.Response, WorkbenchError)
  c = try post_claim_heartbeat(caller, files, clock, resource, body)
  Ok(json_sse(c, files.read_only, "claim.heartbeat", "heartbeat_claim", [Claims.claims_bucket]))
end

fn http_delete_claim(caller: Caller, files: Files, clock: Clock, resource: Text) : Result(
  Api.Response,
  WorkbenchError
)
  st = try delete_claim(caller, files, clock, resource)
  Ok(json_sse(st, files.read_only, "claim.released", "release_claim", [Claims.claims_bucket]))
end

fn http_post_world(caller: Caller, files: Files, clock: Clock, body: WorldOpenInput) : Result(
  Api.Response,
  WorkbenchError
)
  w = try post_world(caller, files, clock, body)
  Ok(json_sse(w, files.read_only, "world.opened", "open_world", [World.worlds_bucket]))
end

fn http_post_world_child(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  body: ChildWorldOpenInput
) : Result(Api.Response, WorkbenchError)
  w = try post_world_child(caller, files, clock, id, body)
  Ok(
    json_sse(
      w,
      files.read_only,
      "world.child_opened",
      "open_child_world",
      [World.worlds_bucket, World.world_links_bucket]
    )
  )
end

fn http_post_world_call(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  body: WorldCallInput
) : Result(Api.Response, WorkbenchError)
  r = try post_world_call(caller, files, clock, id, body)
  Ok(json_sse(r, files.read_only, "world.called", "world_call", [World.worlds_bucket]))
end

fn http_post_world_land(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  r = try post_world_land(caller, files, clock, id)
  Ok(
    json_sse(
      r,
      files.read_only,
      "world.landed",
      "land_world",
      ["tasks", "projects", "artifacts", World.worlds_bucket, Grants.grants_bucket, Claims.claims_bucket]
    )
  )
end

fn http_post_world_land_fair(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  out = try post_world_land_fair(caller, files, clock, id)
  (evt, act, bkts) = case out
    World.LandedOk(result: _): (
      "world.land_fair",
      "land_world_fair",
      ["tasks", "projects", "artifacts", World.worlds_bucket, Claims.claims_bucket]
    )
    World.DeferredByFairness(ticket: _, retry_after: _): (
      "world.deferred",
      "defer_world_fair",
      [World.worlds_bucket, World.world_fairness_bucket]
    )
  end
  Ok(json_sse(out, files.read_only, evt, act, bkts))
end

fn http_post_world_land_child(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  r = try post_world_land_child(caller, files, clock, id)
  Ok(
    json_sse(
      r,
      files.read_only,
      "world.child_landed",
      "land_child_world",
      [World.worlds_bucket, World.world_links_bucket]
    )
  )
end

fn http_post_world_priority(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  body: PriorityClaimInput
) : Result(Api.Response, WorkbenchError)
  t = try post_world_priority(caller, files, clock, id, body)
  Ok(json_sse(t, files.read_only, "world.priority", "claim_priority", [World.world_fairness_bucket]))
end

fn http_delete_world(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  st = try delete_world(caller, files, clock, id)
  Ok(json_sse(st, files.read_only, "world.aborted", "drop_world", [World.worlds_bucket]))
end

fn http_post_admin_init(caller: Caller, files: Files, clock: Clock) : Result(
  Api.Response,
  WorkbenchError
)
  h = try post_admin_init(caller, files, clock)
  Ok(json_sse(h, files.read_only, "admin.init", "admin_init", ["projects"]))
end

fn http_post_admin_demo(caller: Caller, files: Files, clock: Clock) : Result(
  Api.Response,
  WorkbenchError
)
  d = try post_admin_demo(caller, files, clock)
  Ok(
    json_sse(
      d,
      files.read_only,
      "admin.demo",
      "seed_demo",
      ["projects", "tasks", "artifacts", Grants.grants_bucket, Claims.claims_bucket, World.worlds_bucket]
    )
  )
end

fn http_post_replay_simulate(
  caller: Caller,
  files: Files,
  clock: Clock,
  body: ReplaySimulateInput
) : Result(Api.Response, WorkbenchError)
  p = try post_replay_simulate(caller, files, clock, body)
  Ok(
    json_sse(
      p,
      files.read_only,
      "replay.simulated",
      "simulate_replay",
      [Replay.replay_proposals_bucket]
    )
  )
end

fn http_post_replay_accept(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  p = try post_replay_accept(caller, files, clock, id)
  Ok(
    json_sse(
      p,
      files.read_only,
      "replay.accepted",
      "accept_replay_proposal",
      ["projects", "tasks", "artifacts", Grants.grants_bucket, Replay.replay_proposals_bucket]
    )
  )
end

fn http_delete_replay_proposal(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  p = try delete_replay_proposal(caller, files, clock, id)
  Ok(
    json_sse(
      p,
      files.read_only,
      "replay.discarded",
      "discard_replay_proposal",
      [Replay.replay_proposals_bucket]
    )
  )
end

fn http_post_policy_clearance(caller: Caller, files: Files, clock: Clock, body: ClearanceInput) : Result(
  Api.Response,
  WorkbenchError
)
  r = try post_policy_clearance(caller, files, clock, body)
  Ok(json_sse(r, files.read_only, "policy.clearance", "set_clearance", [Policy.clearances_bucket]))
end

fn http_post_gov_proposal(caller: Caller, files: Files, clock: Clock, body: GovProposalInput) : Result(
  Api.Response,
  WorkbenchError
)
  p = try post_gov_proposal(caller, files, clock, body)
  Ok(
    json_sse(
      p,
      files.read_only,
      "proposal.submitted",
      "submit_proposal",
      [Proposals.proposals_bucket]
    )
  )
end

fn http_post_gov_proposal_approve(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  p = try post_gov_proposal_approve(caller, files, clock, id)
  Ok(
    json_sse(
      p,
      files.read_only,
      "proposal.approved",
      "approve_proposal",
      [Proposals.proposals_bucket, Policy.clearances_bucket]
    )
  )
end

fn http_post_gov_proposal_reject(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  p = try post_gov_proposal_reject(caller, files, clock, id)
  Ok(
    json_sse(
      p,
      files.read_only,
      "proposal.rejected",
      "reject_proposal",
      [Proposals.proposals_bucket]
    )
  )
end

fn http_post_gov_proposal_withdraw(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  p = try post_gov_proposal_withdraw(caller, files, clock, id)
  Ok(
    json_sse(
      p,
      files.read_only,
      "proposal.withdrawn",
      "withdraw_proposal",
      [Proposals.proposals_bucket]
    )
  )
end

fn http_post_gov_feed(caller: Caller, files: Files, clock: Clock, body: FeedSubscribeInput) : Result(
  Api.Response,
  WorkbenchError
)
  sub = try post_gov_feed(caller, files, clock, body)
  Ok(
    publish_workbench_commit(
      json_ok_response(sub),
      files.read_only,
      "feed.subscribed",
      "feed_subscribe",
      [Feeds.feeds_bucket],
      Some((Feeds.feed_topic(sub.id), "feed.subscribed"))
    )
  )
end

fn http_post_gov_feed_ack(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  body: FeedAckInput
) : Result(Api.Response, WorkbenchError)
  sub = try post_gov_feed_ack(caller, files, clock, id, body)
  Ok(
    publish_workbench_commit(
      json_ok_response(sub),
      files.read_only,
      "feed.acked",
      "feed_ack",
      [Feeds.feeds_bucket],
      Some((Feeds.feed_topic(id), "feed.acked"))
    )
  )
end

fn http_post_gov_feed_consume(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  limit: Option(Int)
) : Result(Api.Response, WorkbenchError)
  r = try post_gov_feed_consume(caller, files, clock, id, limit)
  Ok(
    publish_workbench_commit(
      json_ok_response(r),
      files.read_only,
      "feed.consumed",
      "feed_consume",
      [Feeds.feeds_bucket],
      Some((Feeds.feed_topic(id), "feed.consumed"))
    )
  )
end

fn http_delete_gov_feed(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  st = try delete_gov_feed(caller, files, clock, id)
  Ok(
    publish_workbench_commit(
      json_ok_response(st),
      files.read_only,
      "feed.unsubscribed",
      "feed_unsubscribe",
      [Feeds.feeds_bucket],
      Some((Feeds.feed_topic(id), "feed.unsubscribed"))
    )
  )
end

fn http_post_taint_untrusted(
  caller: Caller,
  files: Files,
  clock: Clock,
  id: Text,
  body: TaintUntrustedInput
) : Result(Api.Response, WorkbenchError)
  s = try post_taint_untrusted(caller, files, clock, id, body)
  Ok(
    json_sse(
      s,
      files.read_only,
      "taint.untrusted",
      "record_untrusted",
      [Taint.taint_sessions_bucket]
    )
  )
end

fn http_post_taint_clear(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Api.Response,
  WorkbenchError
)
  s = try post_taint_clear(caller, files, clock, id)
  Ok(
    json_sse(s, files.read_only, "taint.cleared", "clear_taint", [Taint.taint_sessions_bucket])
  )
end

fn feed_extra_topic(args: Json, evt: Text) : Option((Text, Text))
  fid = (args.text_at("id") or "").trim
  if fid.empty?
    None
  else
    Some((Feeds.feed_topic(fid), evt))
  end
end

fn mcp_tool_sse_spec(name: Text, args: Json) : Option((Text, List(Text), Option((Text, Text))))
  case name
    "modb_init": Some(("admin.init", ["projects"], None))
    "modb_seed_demo": Some((
      "admin.demo",
      ["projects", "tasks", "artifacts", Grants.grants_bucket, Claims.claims_bucket, World.worlds_bucket],
      None
    ))
    "modb_create_project": Some(("project.created", ["projects"], None))
    "modb_create_task": Some(("task.created", ["tasks"], None))
    "modb_complete_task": Some(("task.completed", ["tasks", "projects", "artifacts"], None))
    "modb_issue_grant": Some(("grant.issued", [Grants.grants_bucket], None))
    "modb_delegate_grant": Some(("grant.delegated", [Grants.grants_bucket], None))
    "modb_revoke_grant": Some(("grant.revoked", [Grants.grants_bucket], None))
    "modb_acquire_claim": Some(("claim.acquired", [Claims.claims_bucket], None))
    "modb_release_claim": Some(("claim.released", [Claims.claims_bucket], None))
    "modb_world_open": Some(("world.opened", [World.worlds_bucket], None))
    "modb_world_call": Some(("world.called", [World.worlds_bucket], None))
    "modb_world_land": Some((
      "world.landed",
      ["tasks", "projects", "artifacts", World.worlds_bucket, Grants.grants_bucket, Claims.claims_bucket],
      None
    ))
    "modb_world_abort": Some(("world.aborted", [World.worlds_bucket], None))
    "modb_world_open_child": Some((
      "world.child_opened",
      [World.worlds_bucket, World.world_links_bucket],
      None
    ))
    "modb_world_land_child": Some((
      "world.child_landed",
      [World.worlds_bucket, World.world_links_bucket],
      None
    ))
    "modb_world_claim_priority": Some(("world.priority", [World.world_fairness_bucket], None))
    "modb_world_land_fair": Some((
      "world.land_fair",
      ["tasks", "projects", "artifacts", World.worlds_bucket, Claims.claims_bucket],
      None
    ))
    "modb_replay_simulate": Some(("replay.simulated", [Replay.replay_proposals_bucket], None))
    "modb_replay_accept": Some((
      "replay.accepted",
      ["projects", "tasks", "artifacts", Grants.grants_bucket, Replay.replay_proposals_bucket],
      None
    ))
    "modb_replay_discard": Some(("replay.discarded", [Replay.replay_proposals_bucket], None))
    "modb_clearance_set": Some(("policy.clearance", [Policy.clearances_bucket], None))
    "modb_proposal_submit": Some(("proposal.submitted", [Proposals.proposals_bucket], None))
    "modb_proposal_approve": Some((
      "proposal.approved",
      [Proposals.proposals_bucket, Policy.clearances_bucket],
      None
    ))
    "modb_proposal_reject": Some(("proposal.rejected", [Proposals.proposals_bucket], None))
    "modb_feed_subscribe": Some(
      ("feed.subscribed", [Feeds.feeds_bucket], feed_extra_topic(args, "feed.subscribed"))
    )
    "modb_feed_consume": Some(
      ("feed.consumed", [Feeds.feeds_bucket], feed_extra_topic(args, "feed.consumed"))
    )
    "modb_feed_unsubscribe": Some(
      ("feed.unsubscribed", [Feeds.feeds_bucket], feed_extra_topic(args, "feed.unsubscribed"))
    )
    "modb_taint_record_untrusted": Some(("taint.untrusted", [Taint.taint_sessions_bucket], None))
    "modb_taint_clear": Some(("taint.cleared", [Taint.taint_sessions_bucket], None))
    _: None
  end
end

fn mcp_publish_if_mutation(
  http_res: Api.Response,
  rf: ReadFiles,
  name: Text,
  args: Json,
  tool_res: Json
) : Api.Response
  return http_res if tool_res.get("isError") == Some(Json.Boolean(true))
  case mcp_tool_sse_spec(name, args)
    Some((evt, buckets, extra)): publish_workbench_commit(
      http_res,
      rf,
      evt,
      name,
      buckets,
      extra
    )
    None: http_res
  end
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
      ),
      mcp_tool_def(
        "modb_policy_get",
        "List persisted Grant Sensitivity clearances and approved dynamic views/releases/invariants.",
        empty_schema
      ),
      mcp_tool_def(
        "modb_clearance_set",
        "Set Sensitivity clearance (public|internal|confidential|secret) on a Grant (admin, non-widening below parent).",
        mcp_schema(
          {
            "grant_id": mcp_prop("string", "Grant ID"),
            "max_sensitivity": mcp_prop(
              "string",
              "Clearance ceiling: public | internal | confidential | secret"
            ),
            "reason": reason_p
          },
          ["grant_id", "max_sensitivity"]
        )
      ),
      mcp_tool_def(
        "modb_proposal_submit",
        "Submit a declarative governance proposal (view, release_policy, clearance, or invariant); computes a machine-checked CapabilityDiff for human approval.",
        mcp_schema(
          {
            "id": mcp_prop("string", "Unique governance proposal ID"),
            "kind": mcp_prop(
              "string",
              "Proposal kind: view | release_policy | clearance | invariant"
            ),
            "proposer_grant_id": mcp_prop("string", "Optional active proposer Grant ID"),
            "description": mcp_prop("string", "Human-readable proposal description"),
            "view_name": mcp_prop("string", "For kind=view: new view name"),
            "base_view": mcp_prop("string", "For kind=view: existing wider view"),
            "fields": Json.Object({
              "type": Json.String("array"),
              "items": Json.Object({"type": Json.String("string")})
            }),
            "release_name": mcp_prop("string", "For kind=release_policy: release name"),
            "min_group_size": mcp_prop("integer", "For kind=release_policy: k-anonymity floor"),
            "target_grant_id": mcp_prop("string", "For kind=clearance: target Grant ID"),
            "target_clearance": mcp_prop("string", "For kind=clearance: target sensitivity"),
            "invariant_name": mcp_prop("string", "For kind=invariant: invariant name"),
            "bucket": mcp_prop("string", "For kind=invariant: target user bucket"),
            "rule_kind": mcp_prop("string", "For kind=invariant: non_empty | int_range | allowed_values"),
            "field": mcp_prop("string", "For kind=invariant: JSON field name"),
            "reason": reason_p
          },
          ["id", "kind"]
        )
      ),
      mcp_tool_def(
        "modb_proposals_list",
        "List human-reviewed Governance Proposals and their CapabilityDiffs (optional status filter).",
        mcp_schema(
          {"status": mcp_prop("string", "Optional filter: pending | approved | rejected | withdrawn")},
          []
        )
      ),
      mcp_tool_def(
        "modb_proposal_approve",
        "Human-only atomic approval of a Pending governance proposal (admin); applies View/Release/Clearance/Invariant atomically.",
        mcp_schema(
          {
            "proposal_id": mcp_prop("string", "Pending proposal ID"),
            "note": mcp_prop("string", "Optional approval review note"),
            "reason": reason_p
          },
          ["proposal_id"]
        )
      ),
      mcp_tool_def(
        "modb_proposal_reject",
        "Human-only rejection of a Pending governance proposal (admin).",
        mcp_schema(
          {
            "proposal_id": mcp_prop("string", "Pending proposal ID"),
            "note": mcp_prop("string", "Optional rejection reason"),
            "reason": reason_p
          },
          ["proposal_id"]
        )
      ),
      mcp_tool_def(
        "modb_feed_subscribe",
        "Subscribe to a persistent CoW-pinned txid-cursor reactive Change Feed over specific or all buckets.",
        mcp_schema(
          {
            "id": mcp_prop("string", "Unique feed subscription ID"),
            "grant_id": mcp_prop("string", "Optional Grant ID enforcing clearance + revocation"),
            "buckets": Json.Object({
              "type": Json.String("array"),
              "items": Json.Object({"type": Json.String("string")})
            }),
            "include_internal": mcp_prop("boolean", "Include _modb_* buckets (default false)"),
            "from_beginning": mcp_prop("boolean", "Bootstrap full history first (default false)"),
            "reason": reason_p
          },
          ["id"]
        )
      ),
      mcp_tool_def(
        "modb_feeds_list",
        "List all active reactive Change Feed subscriptions and their pinned txid cursors.",
        empty_schema
      ),
      mcp_tool_def(
        "modb_feed_poll",
        "Poll structural O(diff) bucket/key changes since a feed's pinned cursor (read-only; sensitivity-filtered).",
        mcp_schema(
          {
            "feed_id": mcp_prop("string", "Feed ID"),
            "limit": mcp_prop("integer", "Max events to return (default 100, 0=unlimited)")
          },
          ["feed_id"]
        )
      ),
      mcp_tool_def(
        "modb_feed_consume",
        "Atomically poll O(diff) changes and advance the feed's persistent CoW cursor + graduate deferred pages.",
        mcp_schema(
          {
            "feed_id": mcp_prop("string", "Feed ID"),
            "limit": mcp_prop("integer", "Max events to consume (default 100)")
          },
          ["feed_id"]
        )
      ),
      mcp_tool_def(
        "modb_feed_unsubscribe",
        "Unsubscribe a reactive Change Feed and unpin its persistent CoW root.",
        mcp_schema({"feed_id": mcp_prop("string", "Feed ID"), "reason": reason_p}, ["feed_id"])
      ),
      mcp_tool_def(
        "modb_taint_sessions",
        "List all persisted dynamic session taint trackers (Lethal Trifecta defense).",
        empty_schema
      ),
      mcp_tool_def(
        "modb_taint_record_untrusted",
        "Ensure a taint session exists and monotonically record ingestion from an untrusted source.",
        mcp_schema(
          {
            "session_id": mcp_prop("string", "Taint session ID"),
            "source": mcp_prop("string", "Untrusted source label"),
            "principal": mcp_prop("string", "Optional principal override"),
            "grant_id": mcp_prop("string", "Optional bound Grant ID")
          },
          ["session_id", "source"]
        )
      ),
      mcp_tool_def(
        "modb_taint_clear",
        "Admin-only explicit human-reviewed reset of untrusted taint on a session (audited).",
        mcp_schema(
          {"session_id": mcp_prop("string", "Taint session ID"), "reason": reason_p},
          ["session_id"]
        )
      ),
      mcp_tool_def(
        "modb_erasure_receipts",
        "List all verifiable right-to-be-forgotten ErasureReceipts (zero raw PII).",
        empty_schema
      ),
      mcp_tool_def(
        "modb_explain_view",
        "Inspect the chosen QueryPlan (index_eq | index_in_list | index_range | full_scan) for a ReadProgram without scanning data rows.",
        mcp_schema(
          {
            "grant_id": mcp_prop("string", "Optional Grant ID authorizing the View"),
            "program": Json.Object({
              "type": Json.String("object"),
              "description": Json.String("ReadProgram object to explain")
            })
          },
          ["program"]
        )
      ),
      mcp_tool_def(
        "modb_matviews_list",
        "List all CoW incremental materialized views (`tasks_by_status`, `tasks_by_project`) and their watermark txids.",
        empty_schema
      ),
      mcp_tool_def(
        "modb_matview_refresh",
        "Incrementally refresh one materialized view in O(diff) using its persistent `mv:<name>` pin.",
        mcp_schema({"name": mcp_prop("string", "Materialized view name")}, ["name"])
      ),
      mcp_tool_def(
        "modb_matview_query",
        "Query materialized view groups with optional k-anonymity minimum cohort filter (`min_k`).",
        mcp_schema(
          {
            "name": mcp_prop("string", "Materialized view name"),
            "min_k": mcp_prop("integer", "Optional k-anonymity minimum row count filter")
          },
          ["name"]
        )
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
    "modb_policy_get": mcp_encode_result(get_policy(rf))
    "modb_clearance_set":
      case Json.from_json[ClearanceInput](args)
        Ok(inp): mcp_encode_result(post_policy_clearance(eff, files, clock, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_proposal_submit":
      case Json.from_json[GovProposalInput](args)
        Ok(inp): mcp_encode_result(post_gov_proposal(eff, files, clock, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_proposals_list": mcp_encode_result(list_gov_proposals(rf, args.text_at("status")))
    "modb_proposal_approve":
      case mcp_req_text(args, "proposal_id")
        Ok(pid):
          note_eff = case args.text_at("note")
            Some(n) if not n.trim.empty?: Caller(
              principal: eff.principal,
              role: eff.role,
              reason: Some(n)
            )
            Some(_) | None: eff
          end
          mcp_encode_result(post_gov_proposal_approve(note_eff, files, clock, pid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_proposal_reject":
      case mcp_req_text(args, "proposal_id")
        Ok(pid):
          note_eff = case args.text_at("note")
            Some(n) if not n.trim.empty?: Caller(
              principal: eff.principal,
              role: eff.role,
              reason: Some(n)
            )
            Some(_) | None: eff
          end
          mcp_encode_result(post_gov_proposal_reject(note_eff, files, clock, pid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_feed_subscribe":
      case Json.from_json[FeedSubscribeInput](args)
        Ok(inp): mcp_encode_result(post_gov_feed(eff, files, clock, inp))
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_feeds_list": mcp_encode_result(list_gov_feeds(rf))
    "modb_feed_poll":
      case mcp_req_text(args, "feed_id")
        Ok(fid): mcp_encode_result(get_gov_feed_poll(eff, rf, clock, fid, args.int_at("limit")))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_feed_consume":
      case mcp_req_text(args, "feed_id")
        Ok(fid): mcp_encode_result(post_gov_feed_consume(eff, files, clock, fid, args.int_at("limit")))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_feed_unsubscribe":
      case mcp_req_text(args, "feed_id")
        Ok(fid): mcp_encode_result(delete_gov_feed(eff, files, clock, fid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_taint_sessions": mcp_encode_result(list_taint_sessions(rf))
    "modb_taint_record_untrusted":
      case mcp_req_text(args, "session_id")
        Ok(sid):
          case mcp_req_text(args, "source")
            Ok(src): mcp_encode_result(
              post_taint_untrusted(
                eff,
                files,
                clock,
                sid,
                TaintUntrustedInput(
                  source: src,
                  principal: args.text_at("principal"),
                  grant_id: args.text_at("grant_id")
                )
              )
            )
            Error(e): mcp_tool_result(Json.encode(e), true)
          end
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_taint_clear":
      case mcp_req_text(args, "session_id")
        Ok(sid): mcp_encode_result(post_taint_clear(eff, files, clock, sid))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_erasure_receipts": mcp_encode_result(list_erasures(rf))
    "modb_explain_view":
      prog_json = args.get("program") or args
      case Json.from_json[Views.ReadProgram](prog_json)
        Ok(prog): mcp_encode_result(
          post_view_explain(
            eff,
            files,
            clock,
            ReadProgramRequest(grant_id: args.text_at("grant_id"), program: prog)
          )
        )
        Error(e): mcp_tool_result(e.to_text, true)
      end
    "modb_matviews_list": mcp_encode_result(get_matviews(files))
    "modb_matview_refresh":
      case mcp_req_text(args, "name")
        Ok(mname):
          case post_matview_refresh(eff, files, mname)
            Ok(resp):
              pub = Api.sse_published_events(resp)
              data = case pub.first
                Some(ev): ev.data
                None: "{}"
              end
              mcp_tool_result(data, false)
            Error(err): mcp_tool_result(Json.encode(err), true)
          end
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
    "modb_matview_query":
      case mcp_req_text(args, "name")
        Ok(mname): mcp_encode_result(get_matview_query(files, mname, args.int_at("min_k")))
        Error(e): mcp_tool_result(Json.encode(e), true)
      end
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
              "version": Json.String("0.7.0")
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
          Ok(
            mcp_publish_if_mutation(
              mcp_json_response(mcp_rpc_ok(id_val, res)),
              files.read_only,
              tname,
              targs,
              res
            )
          )
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

test "AgentWorkbench Milestone 12: Sensitivity Policy, Governance Proposals, and Reactive Change Feeds (REST + MCP)"
  files = Files.in_memory({})
  ro = files.read_only
  t0 = Time.parse("2026-11-26T17:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  env = Env.of({
    "WB_ADMIN_TOKEN": "tok-admin",
    "WB_PLANNER_TOKEN": "tok-plan",
    "WB_WORKER_TOKEN": "tok-work"
  })

  ## Seed demo via MCP -> g-sre gets Confidential clearance, g-rogue-sub stays Public
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/admin/demo").with_bearer("tok-admin").with_header("X-Reason", "seed m12"),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  ## Check GET /policy shows g-sre clearance
  pol_r = ApiTest.send(AgentWorkbench, Api.get("/policy"), files, ro, clock, env)
  assert pol_r.status == 200 and
    Json.decode_strict[PolicySummaryResponse](pol_r.text) is Ok(pol_sum)
  assert pol_sum.clearances.any?(fn(c)
    c.grant_id == "g-sre" and c.max_sensitivity is Policy.Confidential
  end)

  ## Planner proposes narrowed View `tasks_triage` (low risk); worker cannot approve (403); admin approves atomically!
  sub_prop = ApiTest.send(
    AgentWorkbench,
    Api.post("/proposals").with_bearer("tok-plan").with_header("X-Reason", "triage view").with_json(
      GovProposalInput(
        id: "gov-triage",
        kind: "view",
        proposer_grant_id: Some("g-sre"),
        description: Some("Triage view without base_cost_cents"),
        view_name: Some("tasks_triage"),
        base_view: Some("tasks_finance"),
        fields: Some(["id", "project_id", "title", "status"]),
        field_sensitivities: None,
        release_name: None,
        input_sensitivity: None,
        output_sensitivity: None,
        min_group_size: None,
        target_grant_id: None,
        target_clearance: None,
        invariant_name: None,
        bucket: None,
        rule_kind: None,
        field: None,
        min: None,
        max: None,
        allowed_values: None
      )
    ),
    files,
    ro,
    clock,
    env
  )
  assert sub_prop.status == 200 and
    Json.decode_strict[Proposals.GovernanceProposal](sub_prop.text) is Ok(gp0)
  assert gp0.diff.narrows_only and gp0.diff.risk_level == "low"

  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/proposals/gov-triage/approve").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  ).status ==
    403
  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/proposals/gov-triage/approve").with_bearer("tok-admin").with_header(
      "X-Reason",
      "approve triage"
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  ## Approved dynamic View is immediately queryable via `/views/query`!
  dyn_q = ApiTest.send(
    AgentWorkbench,
    Api.post("/views/query").with_bearer("tok-admin").with_json(
      ReadProgramRequest(
        grant_id: None,
        program: Views.ReadProgram(
          view: "tasks_triage",
          where_clause: None,
          select: None,
          group_by: None,
          aggregates: None,
          order_by: Some(Views.SortSpec(field: "id", desc: false)),
          limit: Some(10)
        )
      )
    ),
    files,
    ro,
    clock,
    env
  )
  assert dyn_q.status == 200 and dyn_q.text.contains?("failover")

  ## Subscribe a reactive Change Feed via MCP -> mutate task -> Poll -> Consume -> Unsubscribe!
  sub_f = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(201),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_feed_subscribe"),
          "arguments": Json.Object({
            "id": Json.String("wb-tasks-feed"),
            "grant_id": Json.String("g-sre"),
            "buckets": Json.Array([Json.String("tasks")]),
            "reason": Json.String("watch tasks")
          })
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert sub_f.status == 200 and sub_f.text.contains?("\"isError\":false")

  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/tasks").with_bearer("tok-plan").with_header("X-Reason", "trigger feed").with_json(
      CreateTaskInput(id: 901, project_id: "infra", title: "Feed watch task", base_cost_cents: 500)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  poll_f = ApiTest.send(
    AgentWorkbench,
    Api.get("/feeds/wb-tasks-feed/poll").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  )
  assert poll_f.status == 200 and
    Json.decode_strict[Feeds.FeedBatch](poll_f.text) is Ok(fb0)
  assert fb0.events.size == 1 and fb0.clearance is Policy.Confidential

  cons_f = ApiTest.send(
    AgentWorkbench,
    Api.post("/feeds/wb-tasks-feed/consume").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  )
  assert cons_f.status == 200 and
    Json.decode_strict[FeedConsumeResponse](cons_f.text) is Ok(fcr)
  assert fcr.subscription.events_delivered == 1

  ## Subsequent idle poll reads 0 pages and emits 0 events
  poll_idle = ApiTest.send(
    AgentWorkbench,
    Api.get("/feeds/wb-tasks-feed/poll").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  )
  assert poll_idle.status == 200 and
    Json.decode_strict[Feeds.FeedBatch](poll_idle.text) is Ok(fb_idle)
  assert fb_idle.events.empty? and fb_idle.pages_read == 0

  assert ApiTest.send(
    AgentWorkbench,
    Api.delete("/feeds/wb-tasks-feed").with_bearer("tok-admin").with_header("X-Reason", "done"),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  ## Milestone 13 HTTP + MCP: Taint Sessions & Erasure Receipts
  t_mark = ApiTest.send(
    AgentWorkbench,
    Api.post("/taint/sessions/wb-sess-1/untrusted").with_bearer("tok-work").with_json(
      TaintUntrustedInput(source: "ticket:evil", principal: None, grant_id: Some("g-team-b"))
    ),
    files,
    ro,
    clock,
    env
  )
  assert t_mark.status == 200 and
    Json.decode_strict[Taint.TaintSession](t_mark.text) is Ok(ts_m) and
    ts_m.untrusted_tainted

  t_list = ApiTest.send(
    AgentWorkbench,
    Api.get("/taint/sessions").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  )
  assert t_list.status == 200 and t_list.text.contains?("wb-sess-1")

  assert ApiTest.send(
    AgentWorkbench,
    Api.post("/taint/sessions/wb-sess-1/clear").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  ).status ==
    403

  t_clr = ApiTest.send(
    AgentWorkbench,
    Api.post("/taint/sessions/wb-sess-1/clear").with_bearer("tok-admin").with_header(
      "X-Reason",
      "human clear"
    ),
    files,
    ro,
    clock,
    env
  )
  assert t_clr.status == 200 and
    Json.decode_strict[Taint.TaintSession](t_clr.text) is Ok(ts_c) and
    not ts_c.untrusted_tainted

  e_list = ApiTest.send(
    AgentWorkbench,
    Api.get("/erasures").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  )
  assert e_list.status == 200 and e_list.text.trim == "[]"

  mcp_ers = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-work").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(1301),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_taint_sessions"),
          "arguments": Json.Object({})
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert mcp_ers.status == 200 and mcp_ers.text.contains?("wb-sess-1")

  ver = ApiTest.send(AgentWorkbench, Api.get("/admin/verify"), files, ro, clock, env)
  assert ver.status == 200 and Json.decode_strict[VerifySummary](ver.text) is Ok(vs) and vs.ok
end

test "AgentWorkbench Milestone 14: SSE /events/stream, /feeds/:id/stream & cross-worker delta publish"
  files = Files.in_memory({})
  ro = files.read_only
  t0 = Time.parse("2026-11-26T20:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  env = Env.of({
    "WB_ADMIN_TOKEN": "tok-admin",
    "WB_PLANNER_TOKEN": "tok-plan",
    "WB_WORKER_TOKEN": "tok-work"
  })

  init_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/admin/init").with_bearer("tok-admin").with_header("X-Reason", "m14 init"),
    files,
    ro,
    clock,
    env
  )
  assert init_r.status == 200
  init_pubs = Api.sse_published_events(init_r)
  assert init_pubs.any?(fn(p) p.topic == "workbench" and p.event == Some("admin.init") end)

  ev_r = ApiTest.send(
    AgentWorkbench,
    Api.get("/events/stream").with_header("Last-Event-ID", "7"),
    files,
    ro,
    clock,
    env
  )
  assert ev_r.status == 200
  assert Api.sse_subscribe_topics(ev_r) == ["workbench"]
  assert ev_r.text.contains?("event: health")

  f1 = ApiTest.send(
    AgentWorkbench,
    Api.post("/feeds").with_bearer("tok-work").with_header("X-Reason", "sub tasks").with_json(
      FeedSubscribeInput(
        id: "sse-tasks",
        grant_id: None,
        buckets: Some(["tasks"]),
        include_internal: Some(false),
        from_beginning: Some(false)
      )
    ),
    files,
    ro,
    clock,
    env
  )
  assert f1.status == 200
  f1_pubs = Api.sse_published_events(f1)
  assert f1_pubs.any?(fn(p) p.topic == "feed:sse-tasks" and p.event == Some("feed.subscribed") end)

  f2 = ApiTest.send(
    AgentWorkbench,
    Api.post("/feeds").with_bearer("tok-work").with_header("X-Reason", "sub wild").with_json(
      FeedSubscribeInput(
        id: "sse-wild",
        grant_id: None,
        buckets: None,
        include_internal: Some(false),
        from_beginning: Some(true)
      )
    ),
    files,
    ro,
    clock,
    env
  )
  assert f2.status == 200

  t_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/tasks").with_bearer("tok-plan").with_header("X-Reason", "sse task").with_json(
      CreateTaskInput(id: 951, project_id: "infra", title: "Live SSE delta task", base_cost_cents: 1200)
    ),
    files,
    ro,
    clock,
    env
  )
  assert t_r.status == 200
  t_pubs = Api.sse_published_events(t_r)
  assert t_pubs.any?(fn(p) p.topic == "workbench" and p.event == Some("task.created") end)
  assert t_pubs.any?(fn(p) p.topic == "bucket:tasks" and p.event == Some("feed.delta") end)
  assert t_pubs.any?(fn(p) p.topic == "bucket:*" and p.event == Some("feed.delta") end)

  s1 = ApiTest.send(
    AgentWorkbench,
    Api.get("/feeds/sse-tasks/stream").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  )
  assert s1.status == 200
  assert Api.sse_subscribe_topics(s1) == ["bucket:tasks", "feed:sse-tasks"]
  assert s1.text.contains?("event: feed.snapshot") and s1.text.contains?("\"feed_id\":\"sse-tasks\"")

  s2 = ApiTest.send(
    AgentWorkbench,
    Api.get("/feeds/sse-wild/stream").with_bearer("tok-work"),
    files,
    ro,
    clock,
    env
  )
  assert s2.status == 200
  assert Api.sse_subscribe_topics(s2) == ["bucket:*", "feed:sse-wild"]
  assert s2.text.contains?("event: feed.snapshot")

  mcp_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/mcp").with_bearer("tok-admin").with_header("X-Reason", "mcp sse").with_json(
      Json.Object({
        "jsonrpc": Json.String("2.0"),
        "id": Json.int(99),
        "method": Json.String("tools/call"),
        "params": Json.Object({
          "name": Json.String("modb_create_project"),
          "arguments": Json.Object({
            "id": Json.String("sse-proj"),
            "name": Json.String("SSE Proj"),
            "budget_cents": Json.int(25000)
          })
        })
      })
    ),
    files,
    ro,
    clock,
    env
  )
  assert mcp_r.status == 200
  mcp_pubs = Api.sse_published_events(mcp_r)
  assert mcp_pubs.any?(fn(p) p.topic == "workbench" and p.event == Some("project.created") end)
  assert mcp_pubs.any?(fn(p) p.topic == "bucket:projects" and p.event == Some("feed.delta") end)

  # Milestone 15: ViewIndex query planner explain/execution + incremental CoW MatViews
  exp_r = ApiTest.send(
    AgentWorkbench,
    Api.post("/views/explain").with_bearer("tok-admin").with_json(
      ReadProgramRequest(
        grant_id: None,
        program: Views.ReadProgram(
          view: "tasks_public",
          where_clause: Some(Views.Eq(field: "project_id", value: Json.String("infra"))),
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
  assert exp_r.status == 200 and exp_r.text.contains?("\"strategy\":\"index_eq\"")

  q_idx = ApiTest.send(
    AgentWorkbench,
    Api.post("/views/query").with_bearer("tok-admin").with_header("X-Reason", "m15 idx").with_json(
      ReadProgramRequest(
        grant_id: None,
        program: Views.ReadProgram(
          view: "tasks_public",
          where_clause: Some(Views.Eq(field: "project_id", value: Json.String("infra"))),
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
  assert q_idx.status == 200 and q_idx.text.contains?("\"rows_scanned\":1") and
    q_idx.text.contains?("951")

  mv_l = ApiTest.send(
    AgentWorkbench,
    Api.get("/matviews").with_bearer("tok-admin"),
    files,
    ro,
    clock,
    env
  )
  assert mv_l.status == 200 and mv_l.text.contains?("tasks_by_status") and
    mv_l.text.contains?("tasks_by_project")

  mv_q = ApiTest.send(
    AgentWorkbench,
    Api.get("/matviews/tasks_by_project/query").with_bearer("tok-admin"),
    files,
    ro,
    clock,
    env
  )
  assert mv_q.status == 200 and mv_q.text.contains?("infra")
end
