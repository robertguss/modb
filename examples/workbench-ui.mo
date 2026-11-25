## Self-contained HTML/CSS/JS live visual inspector for `AgentWorkbench` (`GET /` and `GET /ui`).
## Zero external CDN or build dependencies; served directly by `mo serve --workers 8`.
module WorkbenchUi
expose page_html

fn page_html() : Text
  """
  <!doctype html>
  <html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>MoDB AgentWorkbench — Live Multi-Agent Inspector</title>
    <style>
      :root {
        --bg: #0b0f14;
        --panel: #121821;
        --panel-2: #18202c;
        --border: #263244;
        --text: #e6edf3;
        --muted: #8b9bb0;
        --accent: #4ea1ff;
        --accent-soft: rgba(78, 161, 255, 0.14);
        --green: #3fb950;
        --green-soft: rgba(63, 185, 80, 0.16);
        --amber: #d29922;
        --amber-soft: rgba(210, 153, 34, 0.16);
        --red: #f85149;
        --red-soft: rgba(248, 81, 73, 0.16);
        --purple: #bc8cff;
        --purple-soft: rgba(188, 140, 255, 0.16);
        --radius: 10px;
        --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        --sans: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        background: var(--bg);
        color: var(--text);
        font-family: var(--sans);
        font-size: 14px;
        line-height: 1.45;
      }
      header {
        position: sticky;
        top: 0;
        z-index: 20;
        background: rgba(11, 15, 20, 0.94);
        backdrop-filter: blur(8px);
        border-bottom: 1px solid var(--border);
        padding: 12px 20px;
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        align-items: center;
        justify-content: space-between;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .brand h1 {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
        letter-spacing: -0.01em;
      }
      .pill {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 2px 9px;
        border-radius: 999px;
        font-size: 12px;
        font-weight: 600;
        border: 1px solid var(--border);
        background: var(--panel-2);
        color: var(--text);
        font-family: var(--mono);
      }
      .pill.ok { background: var(--green-soft); border-color: var(--green); color: var(--green); }
      .pill.warn { background: var(--amber-soft); border-color: var(--amber); color: var(--amber); }
      .pill.err { background: var(--red-soft); border-color: var(--red); color: var(--red); }
      .pill.info { background: var(--accent-soft); border-color: var(--accent); color: var(--accent); }
      .pill.purple { background: var(--purple-soft); border-color: var(--purple); color: var(--purple); }
      .toolbar {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        align-items: center;
      }
      input, select, button {
        font-family: inherit;
        font-size: 13px;
        border-radius: 7px;
        border: 1px solid var(--border);
        background: var(--panel-2);
        color: var(--text);
        padding: 6px 10px;
      }
      input:focus, select:focus { outline: 1px solid var(--accent); border-color: var(--accent); }
      button {
        cursor: pointer;
        font-weight: 600;
        transition: background 0.12s ease, border-color 0.12s ease;
      }
      button:hover { background: #222e40; border-color: #3a4c66; }
      button.primary { background: var(--accent); color: #08101c; border-color: var(--accent); }
      button.primary:hover { background: #73b6ff; }
      button.success { background: var(--green-soft); color: var(--green); border-color: var(--green); }
      button.danger { background: var(--red-soft); color: var(--red); border-color: var(--red); }
      button.small { padding: 3px 8px; font-size: 12px; }
      main { max-width: 1360px; margin: 0 auto; padding: 18px 20px 48px; }
      .stats {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
        gap: 12px;
        margin-bottom: 16px;
      }
      .stat {
        background: var(--panel);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: 12px 14px;
      }
      .stat .label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted); }
      .stat .val { font-size: 20px; font-weight: 700; margin-top: 4px; font-family: var(--mono); }
      .stat .sub {
        font-size: 12px;
        color: var(--muted);
        margin-top: 2px;
        font-family: var(--mono);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .actions-cell { display: flex; flex-wrap: nowrap; gap: 4px; align-items: center; }
      .tabs {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        border-bottom: 1px solid var(--border);
        padding-bottom: 10px;
        margin-bottom: 16px;
      }
      .tab {
        background: transparent;
        border: 1px solid transparent;
        color: var(--muted);
        padding: 7px 13px;
        border-radius: 8px;
      }
      .tab.active {
        background: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
      }
      .grid-2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 16px; }
      .card {
        background: var(--panel);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: 14px 16px;
        margin-bottom: 16px;
      }
      .card h2, .card h3 {
        margin: 0 0 10px;
        font-size: 15px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }
      .form-row {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        margin-bottom: 10px;
        align-items: center;
      }
      .form-row input, .form-row select { flex: 1 1 130px; min-width: 110px; }
      table {
        width: 100%;
        border-collapse: collapse;
        font-size: 13px;
      }
      th, td {
        text-align: left;
        padding: 7px 8px;
        border-bottom: 1px solid var(--border);
        vertical-align: top;
      }
      th { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; }
      tr:last-child td { border-bottom: none; }
      .mono { font-family: var(--mono); font-size: 12px; }
      .muted { color: var(--muted); }
      .bar {
        width: 100%;
        height: 8px;
        border-radius: 999px;
        background: var(--panel-2);
        border: 1px solid var(--border);
        overflow: hidden;
        margin: 6px 0;
      }
      .bar > span { display: block; height: 100%; background: var(--accent); }
      .bar > span.warn { background: var(--amber); }
      .bar > span.high { background: var(--red); }
      pre {
        margin: 8px 0 0;
        padding: 10px 12px;
        border-radius: 8px;
        background: #090d12;
        border: 1px solid var(--border);
        font-family: var(--mono);
        font-size: 12px;
        overflow-x: auto;
        max-height: 360px;
      }
      #toast {
        position: fixed;
        right: 18px;
        bottom: 18px;
        z-index: 40;
        max-width: 460px;
        padding: 10px 14px;
        border-radius: 9px;
        background: var(--panel-2);
        border: 1px solid var(--accent);
        box-shadow: 0 10px 30px rgba(0,0,0,0.45);
        display: none;
        font-size: 13px;
      }
      #toast.err { border-color: var(--red); color: #ffd0cd; }
      #toast.ok { border-color: var(--green); color: #cef5d4; }
      .hidden { display: none; }
      .tree-indent { padding-left: 20px; border-left: 2px solid var(--border); margin-left: 6px; }
      .summary-pills { display: flex; flex-wrap: wrap; gap: 6px; margin: 8px 0; }
    </style>
  </head>
  <body>
    <header>
      <div class="brand">
        <h1>MoDB AgentWorkbench</h1>
        <span id="health-pill" class="pill">connecting...</span>
        <span class="pill info">MCP: POST /mcp</span>
      </div>
      <div class="toolbar">
        <select id="role-select" title="Auth role">
          <option value="wb-admin">Role: Admin</option>
          <option value="wb-planner">Role: Planner</option>
          <option value="wb-worker">Role: Worker</option>
        </select>
        <input id="token-input" value="wb-admin" placeholder="Bearer token" style="width:115px" />
        <input id="agent-input" value="agent:ui-operator" placeholder="X-Agent-Id" style="width:135px" />
        <input id="reason-input" value="interactive workbench action" placeholder="X-Reason" style="width:170px" />
        <label class="mono muted" style="display:flex;align-items:center;gap:4px;cursor:pointer">
          <input id="auto-refresh" type="checkbox" checked /> Live 2s
        </label>
        <button id="btn-refresh">Refresh</button>
        <button id="btn-demo" class="primary">Seed Demo</button>
        <button id="btn-verify" class="success">Verify SHA-256</button>
        <button id="btn-export">Export JSON</button>
      </div>
    </header>

    <main>
      <section class="stats" id="stats-row">
        <div class="stat"><div class="label">Transaction</div><div class="val" id="st-txid">-</div><div class="sub" id="st-schema">schema v-</div></div>
        <div class="stat"><div class="label">Audit Ledger</div><div class="val" id="st-audit">-</div><div class="sub" id="st-hash">unverified</div></div>
        <div class="stat"><div class="label">Replay Calls</div><div class="val" id="st-calls">-</div><div class="sub" id="st-props">0 proposals</div></div>
        <div class="stat"><div class="label">Worlds Landed</div><div class="val" id="st-worlds">-</div><div class="sub" id="st-open-worlds">0 open</div></div>
        <div class="stat"><div class="label">Send-Backs</div><div class="val" id="st-retries">-</div><div class="sub" id="st-needless">0 needless</div></div>
        <div class="stat"><div class="label">Active Claims</div><div class="val" id="st-claims">-</div><div class="sub" id="st-grants">0 grants</div></div>
      </section>

      <nav class="tabs" id="tabs">
        <button class="tab active" data-tab="projects">Projects &amp; Tasks</button>
        <button class="tab" data-tab="grants">Grants &amp; Claims</button>
        <button class="tab" data-tab="worlds">Speculative Worlds &amp; Diffs</button>
        <button class="tab" data-tab="views">Views, Reads &amp; Onboarding</button>
        <button class="tab" data-tab="replay">Replay Studio</button>
        <button class="tab" data-tab="audit">Audit Ledger</button>
      </nav>

      <section id="tab-projects" class="tab-panel">
        <div class="grid-2">
          <div class="card">
            <h2>Projects &amp; Budgets</h2>
            <div class="form-row">
              <input id="p-id" placeholder="id (e.g. ml-ops)" />
              <input id="p-name" placeholder="Project name" />
              <input id="p-budget" type="number" value="50000" placeholder="budget cents" />
              <button class="primary" onclick="createProject()">Create Project</button>
            </div>
            <div id="projects-list" class="muted">No projects yet. Click "Seed Demo" above to populate.</div>
          </div>
          <div class="card">
            <h2>Tasks <span id="tasks-proj-label" class="pill">select a project</span></h2>
            <div class="form-row">
              <input id="t-id" type="number" placeholder="task id" />
              <input id="t-title" placeholder="Task title" />
              <input id="t-cost" type="number" value="10000" placeholder="base cost cents" />
              <button class="primary" onclick="createTask()">Create Task</button>
            </div>
            <div id="tasks-list" class="muted">Select a project on the left to inspect tasks &amp; artifacts.</div>
          </div>
        </div>
      </section>

      <section id="tab-grants" class="tab-panel hidden">
        <div class="grid-2">
          <div class="card">
            <h2>Attenuated Grants &amp; Delegation Tree</h2>
            <div class="form-row">
              <input id="g-id" placeholder="grant id" />
              <input id="g-parent" placeholder="parent id (blank=root)" />
              <input id="g-principal" placeholder="principal (agent:x)" />
              <input id="g-actions" value="complete_task" placeholder="actions csv" />
              <input id="g-max" type="number" value="20" style="max-width:80px" />
              <button class="primary" onclick="issueOrDelegateGrant()">Issue / Delegate</button>
            </div>
            <div id="grants-list" class="muted">No grants yet.</div>
          </div>
          <div class="card">
            <h2>Active Claims (Advisory Leases)</h2>
            <div class="form-row">
              <input id="c-res" placeholder="resource (e.g. task:303)" />
              <input id="c-grant" placeholder="grant id" />
              <input id="c-ttl" type="number" value="120" style="max-width:85px" />
              <button class="primary" onclick="acquireClaim()">Acquire Claim</button>
            </div>
            <div id="claims-list" class="muted">No active claims.</div>
          </div>
        </div>
      </section>

      <section id="tab-worlds" class="tab-panel hidden">
        <div class="card">
          <h2>Open, Query &amp; Stage Speculative World</h2>
          <div class="form-row">
            <input id="w-id" placeholder="world id (e.g. w-exp-1)" />
            <input id="w-grant" placeholder="grant id" />
            <button class="primary" onclick="openWorld()">Open World</button>
            <select id="w-qname">
              <option value="get_task">Query: get_task (fine)</option>
              <option value="get_project">Query: get_project (fine)</option>
              <option value="list_project_tasks">Query: list_project_tasks (coarse)</option>
            </select>
            <input id="w-qarg" placeholder="query arg (task id or project id)" />
            <button onclick="queryWorld()">Run Query</button>
          </div>
          <div class="form-row">
            <input id="w-call-tid" type="number" placeholder="complete task_id" />
            <input id="w-call-assignee" value="agent:worker" placeholder="assignee" />
            <input id="w-call-art" placeholder="artifact_id (optional)" />
            <button onclick="stageWorldComplete()">Stage complete_task Call</button>
          </div>
        </div>
        <div class="grid-2">
          <div class="card">
            <h2>Worlds Registry</h2>
            <div id="worlds-list" class="muted">No worlds yet.</div>
          </div>
          <div class="card">
            <h2>Structural CoW O(diff) Inspector <span id="diff-world-label" class="pill">none</span></h2>
            <pre id="world-diff-out">Click "Diff" on any open World to inspect its exact CoW bucket changes before landing.</pre>
          </div>
        </div>
      </section>

      <section id="tab-views" class="tab-panel hidden">
        <div class="grid-2">
          <div class="card">
            <h2>Stateless Agent Onboarding <span class="pill info">GET /describe</span></h2>
            <div class="form-row">
              <input id="v-desc-grant" placeholder="grant_id (blank=caller role, e.g. g-rogue-sub)" />
              <button class="primary" onclick="loadDescribe()">Inspect Manifest</button>
              <button onclick="loadDescribePreset('g-sre')">g-sre</button>
              <button onclick="loadDescribePreset('g-rogue-sub')">g-rogue-sub</button>
            </div>
            <pre id="describe-out">Click "Inspect Manifest" or a Grant preset to see the exact Views, visible fields, Releases, Claims, and Invariants exposed to a stateless agent.</pre>
          </div>
          <div class="card">
            <h2>Sandboxed Ad-Hoc Read Program <span class="pill ok">POST /views/query</span></h2>
            <div class="form-row">
              <select id="v-q-view">
                <option value="tasks_public">tasks_public (narrowed)</option>
                <option value="tasks_finance">tasks_finance (full)</option>
                <option value="projects_public">projects_public (narrowed)</option>
                <option value="projects_finance">projects_finance (full)</option>
              </select>
              <input id="v-q-grant" placeholder="grant_id (blank=admin, e.g. g-rogue-sub)" />
              <button class="primary" onclick="runReadProgram()">Run Read Program</button>
              <button class="danger" onclick="testHiddenFieldGate()">Test Hidden Field</button>
            </div>
            <textarea id="v-q-json" rows="4" style="width:100%;font-family:var(--mono);font-size:12px;background:#090d12;color:var(--text);border:1px solid var(--border);border-radius:8px;padding:8px">{"view":"tasks_public","where_clause":{"eq":{"field":"project_id","value":"infra"}},"order_by":{"field":"id","desc":false},"limit":20}</textarea>
            <pre id="read-program-out">Results and work telemetry (rows_scanned, ops_used, answer_hash) appear here.</pre>
          </div>
        </div>
        <div class="grid-2">
          <div class="card">
            <h2>Approved k-Anonymous Releases <span class="pill purple">min_group_size=2</span></h2>
            <div class="form-row">
              <select id="v-rel-name">
                <option value="project_budget_summary">project_budget_summary</option>
                <option value="task_cost_by_status">task_cost_by_status</option>
              </select>
              <input id="v-rel-grant" placeholder="grant_id (blank=admin, e.g. g-sre)" />
              <input id="v-rel-args" value="{}" placeholder="args JSON" />
              <button class="primary" onclick="runRelease()">Run Release</button>
            </div>
            <pre id="release-out">Select a Release above and click "Run Release" to verify cohort threshold gating.</pre>
          </div>
          <div class="card">
            <h2>Read Provenance Log <span id="reads-count" class="pill">0</span></h2>
            <div id="reads-list" class="muted" style="max-height:360px;overflow:auto">No ad-hoc reads or releases recorded yet.</div>
          </div>
        </div>
      </section>

      <section id="tab-replay" class="tab-panel hidden">
        <div class="card">
          <h2>Simulate Offline Replay Proposal</h2>
          <div class="form-row">
            <input id="r-id" value="proposal-1" placeholder="proposal_id" />
            <input id="r-desc" value="Excise rogue grant subtree" placeholder="description" />
            <input id="r-ex-grant" placeholder="exclude_grant (e.g. g-team-b)" />
            <input id="r-ex-principal" placeholder="exclude_principal" />
            <input id="r-ex-world" placeholder="exclude_world" />
            <input id="r-overhead" type="number" placeholder="overhead_pct_override (e.g. 0)" />
            <button class="primary" onclick="simulateReplay()">Simulate Replay</button>
          </div>
        </div>
        <div class="grid-2">
          <div class="card">
            <h2>Replay Proposals</h2>
            <div id="proposals-list" class="muted">No replay proposals yet.</div>
          </div>
          <div class="card">
            <h2>Persisted Call Log <span id="calls-count" class="pill">0</span></h2>
            <div id="calls-list" class="muted" style="max-height:460px;overflow:auto">No calls recorded yet.</div>
          </div>
        </div>
      </section>

      <section id="tab-audit" class="tab-panel hidden">
        <div class="card">
          <h2>Hash-Chained Audit Ledger</h2>
          <div class="form-row">
            <input id="a-principal" placeholder="Filter by principal (optional)" />
            <input id="a-action" placeholder="Filter by action (optional)" />
            <button onclick="refreshAll(true)">Apply Filter</button>
          </div>
          <div id="audit-list" class="muted">No audit entries yet.</div>
        </div>
      </section>
    </main>

    <div id="toast"></div>

    <script>
      const state = {
        activeTab: 'projects',
        selectedProject: null,
        selectedDiffWorld: null,
        lastVerify: null,
        initialized: false,
        lastRenderKey: null,
      };

      const $ = (id) => document.getElementById(id);

      function esc(s) {
        return String(s == null ? '' : s)
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;');
      }

      function cents(c) {
        return '$' + (Number(c || 0) / 100).toFixed(2);
      }

      function toast(msg, kind = 'ok') {
        const el = $('toast');
        el.textContent = msg;
        el.className = kind;
        el.style.display = 'block';
        clearTimeout(toast._t);
        toast._t = setTimeout(() => { el.style.display = 'none'; }, 4200);
      }

      function authHeaders(withReason = true) {
        const h = { 'Authorization': 'Bearer ' + $('token-input').value.trim() };
        const agent = $('agent-input').value.trim();
        if (agent) h['X-Agent-Id'] = agent;
        if (withReason) h['X-Reason'] = $('reason-input').value.trim() || 'ui action';
        return h;
      }

      async function api(method, path, body = null, auth = false) {
        const opts = { method, headers: {} };
        if (auth) Object.assign(opts.headers, authHeaders(true));
        if (body !== null) {
          opts.headers['Content-Type'] = 'application/json';
          opts.body = JSON.stringify(body);
        }
        const res = await fetch(path, opts);
        const text = await res.text();
        let data = null;
        try { data = text ? JSON.parse(text) : null; } catch (_) { data = text; }
        if (!res.ok) {
          const msg = typeof data === 'object' && data ? JSON.stringify(data) : String(data);
          throw new Error(res.status + ' ' + msg);
        }
        return data;
      }

      $('role-select').addEventListener('change', (e) => {
        $('token-input').value = e.target.value;
      });

      document.querySelectorAll('.tab').forEach((btn) => {
        btn.addEventListener('click', () => {
          state.activeTab = btn.dataset.tab;
          document.querySelectorAll('.tab').forEach((b) => b.classList.toggle('active', b === btn));
          document.querySelectorAll('.tab-panel').forEach((p) => {
            p.classList.toggle('hidden', p.id !== 'tab-' + state.activeTab);
          });
        });
      });

      $('btn-refresh').onclick = () => refreshAll(true);

      $('btn-demo').onclick = async () => {
        try {
          const r = await api('POST', '/admin/demo', null, true);
          toast('Demo seeded: ' + r.summary, 'ok');
          state.selectedProject = 'infra';
          if (!$('r-ex-grant').value.trim()) $('r-ex-grant').value = 'g-team-b';
          await refreshAll(true);
        } catch (e) { toast('Seed demo failed: ' + e.message, 'err'); }
      };

      $('btn-verify').onclick = async () => {
        try {
          const v = await api('GET', '/admin/verify');
          state.lastVerify = v;
          $('st-hash').textContent = v.last_audit_hash.slice(0, 10) + '... · ' + v.page_count + 'p';
          $('st-hash').title = 'Verified SHA-256: ' + v.last_audit_hash;
          toast('Verified OK: txid=' + v.txid + ', ' + v.audit_entries + ' audit entries, ' + v.invariants_checked + ' invariants', 'ok');
        } catch (e) { toast('Verify failed: ' + e.message, 'err'); }
      };

      $('btn-export').onclick = async () => {
        try {
          const snap = await api('GET', '/admin/export');
          const blob = new Blob([JSON.stringify(snap, null, 2)], { type: 'application/json' });
          const url = URL.createObjectURL(blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = 'modb-snapshot-tx' + snap.source_txid + '.json';
          a.click();
          URL.revokeObjectURL(url);
          toast('Exported ' + snap.bucket_count + ' buckets / ' + snap.entry_count + ' entries (sha256 ' + snap.sha256.slice(0, 12) + '...)', 'ok');
        } catch (e) { toast('Export failed: ' + e.message, 'err'); }
      };

      async function createProject() {
        try {
          const id = $('p-id').value.trim();
          const name = $('p-name').value.trim();
          const budget_cents = Number($('p-budget').value);
          await api('POST', '/projects', { id, name, budget_cents }, true);
          state.selectedProject = id;
          toast('Project ' + id + ' saved', 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function createTask() {
        if (!state.selectedProject) return toast('Select a project first', 'err');
        try {
          await api('POST', '/tasks', {
            id: Number($('t-id').value),
            project_id: state.selectedProject,
            title: $('t-title').value.trim(),
            base_cost_cents: Number($('t-cost').value),
          }, true);
          toast('Task created', 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function completeTaskDirect(tid) {
        try {
          const who = $('agent-input').value.trim() || 'agent:ui';
          await api('POST', '/tasks/' + tid + '/complete', {
            task_id: tid,
            assignee: who,
            artifact_id: 'art-ui-' + tid,
            artifact_summary: 'Completed from Workbench UI',
            artifact_sha256: 'ui000000' + tid,
          }, true);
          toast('Task #' + tid + ' completed', 'ok');
          await refreshAll(true);
        } catch (e) {
          toast('Refused (recorded for Replay!): ' + e.message, 'err');
          await refreshAll(true);
        }
      }

      async function issueOrDelegateGrant() {
        try {
          const parent = $('g-parent').value.trim();
          const body = {
            id: $('g-id').value.trim(),
            principal: $('g-principal').value.trim(),
            allowed_actions: $('g-actions').value.split(',').map((s) => s.trim()).filter(Boolean),
            max_calls: Number($('g-max').value),
            ttl_seconds: 3600,
          };
          const path = parent ? ('/grants/' + encodeURIComponent(parent) + '/delegate') : '/grants';
          await api('POST', path, body, true);
          toast('Grant ' + body.id + ' saved', 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function revokeGrant(id) {
        try {
          await api('POST', '/grants/' + encodeURIComponent(id) + '/revoke', null, true);
          toast('Revoked grant ' + id + ' (cascades to descendants)', 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function acquireClaim() {
        try {
          await api('POST', '/claims', {
            resource: $('c-res').value.trim(),
            grant_id: $('c-grant').value.trim(),
            world_id: null,
            ttl_seconds: Number($('c-ttl').value),
          }, true);
          toast('Claim acquired', 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function releaseClaim(res) {
        try {
          await api('DELETE', '/claims/' + encodeURIComponent(res), null, true);
          toast('Released claim ' + res, 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function openWorld() {
        try {
          const id = $('w-id').value.trim();
          const grant_id = $('w-grant').value.trim();
          await api('POST', '/worlds', { id, grant_id, ttl_seconds: 600 }, true);
          toast('Opened World ' + id, 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function queryWorld() {
        try {
          const id = $('w-id').value.trim();
          const query = $('w-qname').value;
          const rawArg = $('w-qarg').value.trim();
          const args = query === 'get_task' ? Number(rawArg) : rawArg;
          const out = await api('POST', '/worlds/' + encodeURIComponent(id) + '/query', { query, args }, true);
          $('diff-world-label').textContent = id + ' query';
          $('world-diff-out').textContent = JSON.stringify(out, null, 2);
          toast('World query recorded on ' + id, 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function stageWorldComplete() {
        try {
          const id = $('w-id').value.trim();
          const tid = Number($('w-call-tid').value);
          const assignee = $('w-call-assignee').value.trim();
          const artId = $('w-call-art').value.trim() || null;
          await api('POST', '/worlds/' + encodeURIComponent(id) + '/call', {
            action: 'complete_task',
            args: {
              task_id: tid,
              assignee,
              artifact_id: artId,
              artifact_summary: artId ? ('Staged in world ' + id) : null,
              artifact_sha256: artId ? ('world-' + tid) : null,
            },
          }, true);
          toast('Staged complete_task(#' + tid + ') in ' + id, 'ok');
          await inspectDiff(id);
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function inspectDiff(id) {
        try {
          state.selectedDiffWorld = id;
          const diff = await api('GET', '/worlds/' + encodeURIComponent(id) + '/diff');
          $('diff-world-label').textContent = id;
          $('world-diff-out').textContent = JSON.stringify(diff, null, 2);
        } catch (e) { toast('Diff error: ' + e.message, 'err'); }
      }

      async function landWorld(id) {
        try {
          const r = await api('POST', '/worlds/' + encodeURIComponent(id) + '/land', null, true);
          toast('Landed world ' + id + ' (txid=' + r.commit_txid + ')', 'ok');
          await refreshAll(true);
        } catch (e) { toast('Land failed: ' + e.message, 'err'); await refreshAll(true); }
      }

      async function abortWorld(id) {
        try {
          await api('DELETE', '/worlds/' + encodeURIComponent(id), null, true);
          toast('Aborted world ' + id, 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      async function loadDescribe() {
        try {
          const gid = $('v-desc-grant').value.trim();
          const path = gid ? ('/describe?grant_id=' + encodeURIComponent(gid)) : '/describe';
          const out = await api('GET', path, null, true);
          $('describe-out').textContent = JSON.stringify(out, null, 2);
          toast('Loaded OnboardingManifest (' + out.allowed_views.length + ' views, ' + out.allowed_releases.length + ' releases)', 'ok');
        } catch (e) {
          $('describe-out').textContent = 'Error: ' + e.message;
          toast(e.message, 'err');
        }
      }

      async function loadDescribePreset(gid) {
        $('v-desc-grant').value = gid;
        await loadDescribe();
      }

      async function runReadProgram() {
        try {
          const prog = JSON.parse($('v-q-json').value);
          prog.view = $('v-q-view').value;
          const gid = $('v-q-grant').value.trim() || null;
          const out = await api('POST', '/views/query', { grant_id: gid, program: prog }, true);
          $('read-program-out').textContent = JSON.stringify(out, null, 2);
          toast('ReadProgram OK: ' + out.result_count + ' rows (' + out.rows_scanned + ' scanned, ' + out.ops_used + ' ops)', 'ok');
          await refreshAll(true);
        } catch (e) {
          $('read-program-out').textContent = 'Blocked: ' + e.message;
          toast('ReadProgram blocked: ' + e.message, 'err');
        }
      }

      async function testHiddenFieldGate() {
        $('v-q-view').value = 'tasks_public';
        $('v-q-grant').value = 'g-rogue-sub';
        $('v-q-json').value = JSON.stringify({
          view: 'tasks_public',
          where_clause: { gt: { field: 'billed_cents', value: 0 } }
        });
        await runReadProgram();
      }

      async function runRelease() {
        try {
          const name = $('v-rel-name').value;
          const gid = $('v-rel-grant').value.trim() || null;
          const args = JSON.parse($('v-rel-args').value || '{}');
          const out = await api('POST', '/releases/' + encodeURIComponent(name), { grant_id: gid, args }, true);
          $('release-out').textContent = JSON.stringify(out, null, 2);
          toast('Release ' + name + ' OK (cohort=' + out.cohort_size + ' >= ' + out.min_group_size + ')', 'ok');
          await refreshAll(true);
        } catch (e) {
          $('release-out').textContent = 'Blocked: ' + e.message;
          toast('Release blocked: ' + e.message, 'err');
        }
      }

      function renderReads(entries) {
        $('reads-count').textContent = String(entries.length);
        if (!entries.length) {
          $('reads-list').innerHTML = '<div class="muted">No ad-hoc reads or releases recorded yet.</div>';
          return;
        }
        $('reads-list').innerHTML = '<table><thead><tr><th>Seq</th><th>TX</th><th>Principal / Grant</th><th>Kind</th><th>Target</th><th>Scanned / Out</th></tr></thead><tbody>'
          + entries.slice().reverse().map((r) => {
            const kind = enumTag(r.kind);
            const cls = kind === 'approved_release' ? 'purple' : 'info';
            return '<tr><td class="mono">#' + r.seq + '</td><td class="mono">' + r.txid + '</td>'
              + '<td class="mono">' + esc(r.principal) + ' <span class="muted">' + esc(r.grant_id || '') + '</span></td>'
              + '<td><span class="pill ' + cls + '">' + esc(kind) + '</span></td>'
              + '<td class="mono">' + esc(r.target) + '</td>'
              + '<td class="mono">' + r.rows_scanned + ' / ' + r.result_count + '</td></tr>';
          }).join('') + '</tbody></table>';
      }

      async function simulateReplay() {
        try {
          const ov = $('r-overhead').value.trim();
          const body = {
            proposal_id: $('r-id').value.trim(),
            description: $('r-desc').value.trim() || 'replay simulation',
            exclude_principal: $('r-ex-principal').value.trim() || null,
            exclude_grant: $('r-ex-grant').value.trim() || null,
            exclude_world: $('r-ex-world').value.trim() || null,
            exclude_seqs: null,
            stop_before_seq: null,
            overhead_pct_override: ov === '' ? null : Number(ov),
          };
          const prop = await api('POST', '/admin/replay/simulate', body, true);
          const s = prop.summary;
          toast('Simulated ' + prop.id + ': excluded=' + s.excluded + ', reply_changed=' + s.reply_changed + ', now_accepted=' + s.now_accepted, 'ok');
          const m = body.proposal_id.match(/^(.*?)([0-9]+)$/);
          if (m) $('r-id').value = m[1] + String(Number(m[2]) + 1);
          await refreshAll(true);
        } catch (e) { toast('Replay simulate failed: ' + e.message, 'err'); }
      }

      async function acceptProposal(id) {
        try {
          await api('POST', '/admin/replay/proposals/' + encodeURIComponent(id) + '/accept', null, true);
          toast('Proposal ' + id + ' accepted atomically!', 'ok');
          await refreshAll(true);
        } catch (e) { toast('Accept failed: ' + e.message, 'err'); }
      }

      async function discardProposal(id) {
        try {
          await api('DELETE', '/admin/replay/proposals/' + encodeURIComponent(id), null, true);
          toast('Discarded proposal ' + id, 'ok');
          await refreshAll(true);
        } catch (e) { toast(e.message, 'err'); }
      }

      function renderProjects(projects) {
        if (!projects.length) {
          $('projects-list').innerHTML = '<div class="muted">No projects yet. Click Seed Demo above.</div>';
          return;
        }
        if (!state.selectedProject || !projects.some((p) => p.id === state.selectedProject)) {
          state.selectedProject = projects[0].id;
        }
        $('projects-list').innerHTML = projects.map((p) => {
          const pct = p.budget_cents > 0 ? Math.min(100, Math.round((p.spent_cents * 100) / p.budget_cents)) : 0;
          const barCls = pct >= 90 ? 'high' : (pct >= 70 ? 'warn' : '');
          const sel = p.id === state.selectedProject;
          return '<div class="card" style="margin-bottom:10px;cursor:pointer;border-color:' + (sel ? 'var(--accent)' : 'var(--border)') + '" data-action="select-project" data-id="' + esc(p.id) + '">'
            + '<div style="display:flex;justify-content:space-between;align-items:center">'
            + '<strong>' + esc(p.name) + ' <span class="mono muted">(' + esc(p.id) + ')</span></strong>'
            + '<span class="pill ' + (pct >= 90 ? 'err' : 'info') + '">' + pct + '% spent</span>'
            + '</div>'
            + '<div class="bar"><span class="' + barCls + '" style="width:' + pct + '%"></span></div>'
            + '<div class="mono muted">spent ' + cents(p.spent_cents) + ' / ' + cents(p.budget_cents) + ' | remaining ' + cents(p.remaining_cents) + '</div>'
            + '</div>';
        }).join('');
      }

      async function selectProject(pid) {
        state.selectedProject = pid;
        await refreshAll(true);
      }

      async function refreshTasks() {
        if (!state.selectedProject) return;
        $('tasks-proj-label').textContent = state.selectedProject;
        const tasks = await api('GET', '/projects/' + encodeURIComponent(state.selectedProject) + '/tasks');
        if (!tasks.length) {
          $('tasks-list').innerHTML = '<div class="muted">No tasks in this project.</div>';
          return;
        }
        $('tasks-list').innerHTML = '<table><thead><tr><th>ID</th><th>Title</th><th>Status</th><th>Cost / Billed</th><th>Assignee</th><th></th></tr></thead><tbody>'
          + tasks.map((t) => {
            const st = typeof t.status === 'string' ? t.status : JSON.stringify(t.status);
            const pillCls = st === 'done' ? 'ok' : (st === 'open' ? 'info' : 'warn');
            const btn = st === 'open'
              ? '<button class="small success" data-action="complete-task" data-id="' + esc(t.id) + '">Complete</button>'
              : '<span class="mono muted">done</span>';
            return '<tr><td class="mono">#' + t.id + '</td><td>' + esc(t.title) + '</td>'
              + '<td><span class="pill ' + pillCls + '">' + esc(st) + '</span></td>'
              + '<td class="mono">' + cents(t.base_cost_cents) + ' / ' + cents(t.billed_cents) + '</td>'
              + '<td class="mono">' + esc(t.assignee || '-') + '</td><td>' + btn + '</td></tr>';
          }).join('') + '</tbody></table>';
      }

      function renderGrants(grants) {
        $('st-grants').textContent = grants.length + ' grants';
        if (!grants.length) {
          $('grants-list').innerHTML = '<div class="muted">No grants issued.</div>';
          return;
        }
        const byParent = new Map();
        grants.forEach((g) => {
          const k = g.parent_id || '__root__';
          if (!byParent.has(k)) byParent.set(k, []);
          byParent.get(k).push(g);
        });
        function renderNode(g, depth) {
          const rev = Boolean(g.revoked);
          const badge = rev ? '<span class="pill err">revoked</span>' : '<span class="pill ok">active</span>';
          const btn = rev ? '' : '<button class="small danger" data-action="revoke-grant" data-id="' + esc(g.id) + '">Revoke</button>';
          const kids = (byParent.get(g.id) || []).map((c) => renderNode(c, depth + 1)).join('');
          const viewsInfo = (g.allowed_views && g.allowed_views.length) ? (' views=[' + esc(g.allowed_views.join(', ')) + ']') : '';
          const relInfo = (g.allowed_releases && g.allowed_releases.length) ? (' releases=[' + esc(g.allowed_releases.join(', ')) + ']') : '';
          return '<div class="' + (depth > 0 ? 'tree-indent' : '') + '" style="margin-bottom:8px">'
            + '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;padding:7px 9px;background:var(--panel-2);border:1px solid var(--border);border-radius:7px">'
            + '<div><span class="mono"><strong>' + esc(g.id) + '</strong></span> ' + badge
            + ' <span class="mono muted">' + esc(g.principal) + '</span>'
            + '<div class="mono muted">actions=[' + esc((g.allowed_actions || []).join(', ')) + '] calls=' + g.used_calls + '/' + g.max_calls + viewsInfo + relInfo + '</div></div>'
            + btn + '</div>' + kids + '</div>';
        }
        const roots = byParent.get('__root__') || grants;
        $('grants-list').innerHTML = roots.map((g) => renderNode(g, 0)).join('');
      }

      function enumTag(v) {
        if (typeof v === 'string') return v;
        if (v && typeof v === 'object') return Object.keys(v)[0] || 'unknown';
        return 'unknown';
      }

      function renderClaims(claims) {
        $('st-claims').textContent = String(claims.length);
        if (!claims.length) {
          $('claims-list').innerHTML = '<div class="muted">No active claims.</div>';
          return;
        }
        $('claims-list').innerHTML = '<table><thead><tr><th>Resource</th><th>Holder</th><th>Grant</th><th>Expires</th><th></th></tr></thead><tbody>'
          + claims.map((c) => '<tr><td class="mono">' + esc(c.resource) + '</td>'
            + '<td class="mono">' + esc(c.holder) + '</td>'
            + '<td class="mono">' + esc(c.grant_id) + '</td>'
            + '<td class="mono muted">' + esc(c.expires_at) + '</td>'
            + '<td><button class="small danger" data-action="release-claim" data-id="' + esc(c.resource) + '">Release</button></td></tr>').join('')
          + '</tbody></table>';
      }

      function renderWorlds(worlds, metrics) {
        const openCount = worlds.filter((w) => enumTag(w.status) === 'open').length;
        const skipped = metrics.total_reads_skipped || 0;
        const verified = metrics.total_reads_verified || 0;
        $('st-worlds').textContent = String(metrics.total_landed || 0);
        $('st-open-worlds').textContent = openCount + ' open · ' + skipped + '/' + verified + ' reads skipped';
        $('st-retries').textContent = String(metrics.stale_read_rejections || 0);
        $('st-needless').textContent = (metrics.needless_send_backs || 0) + ' needless';
        if (!worlds.length) {
          $('worlds-list').innerHTML = '<div class="muted">No worlds opened yet.</div>';
          return;
        }
        $('worlds-list').innerHTML = '<table><thead><tr><th>World</th><th>Status</th><th>Grant</th><th>Base TX</th><th>Steps</th><th>Actions</th></tr></thead><tbody>'
          + worlds.slice().reverse().map((w) => {
            const st = enumTag(w.status);
            const stText = (w.status && w.status.landed) ? ('landed #' + w.status.landed.commit_txid) : st;
            const cls = st === 'open' ? 'info' : (st === 'landed' ? 'ok' : 'warn');
            const steps = w.steps || [];
            const qCount = steps.filter((s) => s && typeof s === 'object' && 'read_step' in s).length;
            const cCount = steps.filter((s) => s && typeof s === 'object' && 'call_step' in s).length;
            const acts = st === 'open'
              ? '<div class="actions-cell">'
                + '<button class="small" data-action="world-diff" data-id="' + esc(w.id) + '">Diff</button>'
                + '<button class="small success" data-action="world-land" data-id="' + esc(w.id) + '">Land</button>'
                + '<button class="small danger" data-action="world-abort" data-id="' + esc(w.id) + '">Abort</button>'
                + '</div>'
              : '<span class="mono muted">closed</span>';
            return '<tr><td class="mono">' + esc(w.id) + '</td>'
              + '<td><span class="pill ' + cls + '">' + esc(stText) + '</span></td>'
              + '<td class="mono">' + esc(w.grant_id) + '</td>'
              + '<td class="mono">' + w.base_txid + '</td>'
              + '<td class="mono">' + qCount + 'q / ' + cCount + 'c</td>'
              + '<td>' + acts + '</td></tr>';
          }).join('') + '</tbody></table>';
      }

      function outcomeInfo(o) {
        const tag = enumTag(o);
        const data = (o && typeof o === 'object' && o[tag] && typeof o[tag] === 'object') ? o[tag] : (o || {});
        const cls = tag === 'now_accepted' ? 'ok' : (tag === 'excluded' ? 'purple' : (tag === 'reply_changed' ? 'info' : (tag === 'unchanged' ? '' : 'err')));
        return { tag, cls, data };
      }

      function renderProposals(proposals) {
        $('st-props').textContent = proposals.length + ' proposals';
        if (!proposals.length) {
          $('proposals-list').innerHTML = '<div class="muted">Simulate a replay above to inspect diffs and outcomes before accepting.</div>';
          return;
        }
        $('proposals-list').innerHTML = proposals.slice().reverse().map((p) => {
          const s = p.summary;
          const st = enumTag(p.status);
          const stLabel = (p.status && p.status.accepted) ? ('accepted tx #' + p.status.accepted.commit_txid) : st;
          const stCls = st === 'pending' ? 'warn' : (st === 'accepted' ? 'ok' : '');
          const btns = st === 'pending'
            ? '<div class="actions-cell">'
              + '<button class="small success" data-action="proposal-accept" data-id="' + esc(p.id) + '">Accept Atomically</button>'
              + '<button class="small danger" data-action="proposal-discard" data-id="' + esc(p.id) + '">Discard</button>'
              + '</div>'
            : '';
          const interesting = (p.outcomes || []).filter((o) => outcomeInfo(o).tag !== 'unchanged');
          const rows = interesting.slice(0, 12).map((o) => {
            const info = outcomeInfo(o);
            return '<tr><td class="mono">#' + info.data.seq + '</td><td class="mono">' + esc(info.data.principal) + '</td><td class="mono">' + esc(info.data.action) + '</td><td><span class="pill ' + info.cls + '">' + esc(info.tag) + '</span></td></tr>';
          }).join('');
          return '<div class="card" style="margin-bottom:10px;background:var(--panel-2)">'
            + '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px">'
            + '<div><strong>' + esc(p.id) + '</strong> <span class="pill ' + stCls + '">' + esc(stLabel) + '</span><div class="muted">' + esc(p.description) + '</div></div>'
            + '<div>' + btns + '</div></div>'
            + '<div class="summary-pills">'
            + '<span class="pill">total ' + s.total_calls + '</span>'
            + '<span class="pill purple">excluded ' + s.excluded + '</span>'
            + '<span class="pill info">reply_changed ' + s.reply_changed + '</span>'
            + '<span class="pill ok">now_accepted ' + s.now_accepted + '</span>'
            + '<span class="pill err">now_refused ' + s.now_refused + '</span>'
            + '<span class="pill err">inv_blocked ' + s.now_invariant_blocked + '</span>'
            + '</div>'
            + (rows ? '<table><thead><tr><th>Seq</th><th>Principal</th><th>Action</th><th>Outcome</th></tr></thead><tbody>' + rows + '</tbody></table>' : '')
            + '</div>';
        }).join('');
      }

      function renderCalls(calls) {
        $('calls-count').textContent = String(calls.length);
        if (!calls.length) {
          $('calls-list').innerHTML = '<div class="muted">No replayable calls recorded yet.</div>';
          return;
        }
        $('calls-list').innerHTML = '<table><thead><tr><th>Seq</th><th>Principal</th><th>Grant / World</th><th>Action</th><th>Original</th></tr></thead><tbody>'
          + calls.slice().reverse().map((c) => {
            const refused = c.outcome && typeof c.outcome === 'object' && 'orig_refused' in c.outcome;
            const errTip = refused ? esc((c.outcome.orig_refused && c.outcome.orig_refused.error) || '') : '';
            const pill = refused ? '<span class="pill err" title="' + errTip + '">OrigRefused</span>' : '<span class="pill ok">OrigOk</span>';
            return '<tr><td class="mono">#' + c.seq + '</td><td class="mono">' + esc(c.principal) + '</td>'
              + '<td class="mono muted">' + esc(c.grant_id || '-') + ' / ' + esc(c.world_id || '-') + '</td>'
              + '<td class="mono">' + esc(c.action) + '</td><td>' + pill + '</td></tr>';
          }).join('') + '</tbody></table>';
      }

      function renderAudit(entries) {
        if (!entries.length) {
          $('audit-list').innerHTML = '<div class="muted">No audit entries.</div>';
          return;
        }
        $('audit-list').innerHTML = '<table><thead><tr><th>Seq</th><th>TX</th><th>Principal</th><th>Action</th><th>Reason</th><th>Summary</th><th>Hash</th></tr></thead><tbody>'
          + entries.slice().reverse().map((e) => '<tr><td class="mono">#' + e.seq + '</td>'
            + '<td class="mono">' + e.txid + '</td>'
            + '<td class="mono">' + esc(e.principal) + '</td>'
            + '<td class="mono">' + esc(e.action) + '</td>'
            + '<td>' + esc(e.reason) + '</td>'
            + '<td>' + esc(e.summary) + '</td>'
            + '<td class="mono muted">' + esc((e.entry_hash || '').slice(0, 12)) + '...</td></tr>').join('')
          + '</tbody></table>';
      }

      document.addEventListener('click', (e) => {
        const el = e.target.closest('[data-action]');
        if (!el) return;
        const act = el.dataset.action;
        const id = el.dataset.id;
        if (act === 'select-project') selectProject(id);
        else if (act === 'complete-task') completeTaskDirect(Number(id));
        else if (act === 'revoke-grant') revokeGrant(id);
        else if (act === 'release-claim') releaseClaim(id);
        else if (act === 'world-diff') inspectDiff(id);
        else if (act === 'world-land') landWorld(id);
        else if (act === 'world-abort') abortWorld(id);
        else if (act === 'proposal-accept') acceptProposal(id);
        else if (act === 'proposal-discard') discardProposal(id);
      });

      async function refreshAll(explicit = false) {
        try {
          const h = await api('GET', '/health');
          state.initialized = h.status === 'ok';
          const pill = $('health-pill');
          pill.textContent = h.status === 'ok' ? ('ONLINE · tx ' + h.txid) : 'UNINITIALIZED';
          pill.className = 'pill ' + (h.status === 'ok' ? 'ok' : 'warn');
          $('st-txid').textContent = String(h.txid);
          $('st-schema').textContent = 'schema v' + h.schema_version;
          $('st-audit').textContent = String(h.audit_count);
          $('st-calls').textContent = String(h.call_count);
          if (!state.initialized) {
            state.lastRenderKey = null;
            return;
          }

          const ap = $('a-principal').value.trim();
          const aa = $('a-action').value.trim();
          const renderKey = [h.status, h.txid, h.audit_count, h.call_count, state.selectedProject || '', ap, aa].join('|');
          if (!explicit && renderKey === state.lastRenderKey) return;
          state.lastRenderKey = renderKey;

          let auditPath = '/audit?limit=80';
          if (ap) auditPath += '&principal=' + encodeURIComponent(ap);
          else if (aa) auditPath += '&action=' + encodeURIComponent(aa);

          const [projects, grants, claims, worlds, metrics, calls, proposals, audit, reads] = await Promise.all([
            api('GET', '/projects'),
            api('GET', '/grants'),
            api('GET', '/claims'),
            api('GET', '/worlds'),
            api('GET', '/worlds/metrics'),
            api('GET', '/admin/replay/calls'),
            api('GET', '/admin/replay/proposals'),
            api('GET', auditPath),
            api('GET', '/reads?limit=50'),
          ]);
          renderProjects(projects);
          await refreshTasks();
          renderGrants(grants);
          renderClaims(claims);
          renderWorlds(worlds, metrics);
          renderCalls(calls);
          renderProposals(proposals);
          renderAudit(audit);
          renderReads(reads);
        } catch (e) {
          if (explicit) toast('Refresh error: ' + e.message, 'err');
        }
      }

      refreshAll(true);
      setInterval(() => {
        if ($('auto-refresh').checked) refreshAll(false);
      }, 2000);
    </script>
  </body>
  </html>
  """
end
