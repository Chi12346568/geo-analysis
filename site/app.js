const els = {
  daemonUrl: document.querySelector("#daemonUrl"),
  statusText: document.querySelector("#statusText"),
  statusDot: document.querySelector("#statusDot"),
  contextLabel: document.querySelector("#contextLabel"),
  pageTitle: document.querySelector("#pageTitle"),
  settingsButton: document.querySelector("#settingsButton"),
  checkStatusButton: document.querySelector("#checkStatusButton"),
  clearButton: document.querySelector("#clearButton"),
  runButton: document.querySelector("#runButton"),
  loadLastButton: document.querySelector("#loadLastButton"),
  openIssuesButton: document.querySelector("#openIssuesButton"),
  openAgentsButton: document.querySelector("#openAgentsButton"),
  openReportButton: document.querySelector("#openReportButton"),
  openChatButton: document.querySelector("#openChatButton"),
  reportButton: document.querySelector("#reportButton"),
  downloadSplit: document.querySelector("#downloadSplit"),
  downloadReportButton: document.querySelector("#downloadReportButton"),
  downloadMenuButton: document.querySelector("#downloadMenuButton"),
  downloadMenu: document.querySelector("#downloadMenu"),
  downloadLabel: document.querySelector("#downloadLabel"),
  modeTabs: document.querySelectorAll(".mode-tab"),
  modeFields: document.querySelectorAll(".mode-field"),
  filterButtons: document.querySelectorAll(".filter-button"),
  urlInput: document.querySelector("#urlInput"),
  htmlInput: document.querySelector("#htmlInput"),
  fileInput: document.querySelector("#fileInput"),
  projectPathInput: document.querySelector("#projectPathInput"),
  robotsInput: document.querySelector("#robotsInput"),
  openaiKey: document.querySelector("#openaiKey"),
  saveKeyButton: document.querySelector("#saveKeyButton"),
  overallScore: document.querySelector("#overallScore"),
  projectedScore: document.querySelector("#projectedScore"),
  scoreDelta: document.querySelector("#scoreDelta"),
  issueCount: document.querySelector("#issueCount"),
  wordCount: document.querySelector("#wordCount"),
  pageMeta: document.querySelector("#pageMeta"),
  scoreBreakdown: document.querySelector("#scoreBreakdown"),
  benchmarkComparison: document.querySelector("#benchmarkComparison"),
  sideSessionsList: document.querySelector("#sideSessionsList"),
  agentActivity: document.querySelector("#agentActivity"),
  agentGrid: document.querySelector("#agentGrid"),
  issuesList: document.querySelector("#issuesList"),
  recommendationsList: document.querySelector("#recommendationsList"),
  reportOutput: document.querySelector("#reportOutput"),
  messages: document.querySelector("#messages"),
  chatForm: document.querySelector("#chatForm"),
  prompt: document.querySelector("#prompt"),
  sendButton: document.querySelector("#sendButton"),
  toastRegion: document.querySelector("#toastRegion"),
  settingsDialog: document.querySelector("#settingsDialog"),
  issuesDialog: document.querySelector("#issuesDialog"),
  diffDialog: document.querySelector("#diffDialog"),
  diffView: document.querySelector("#diffView"),
  diffExplanation: document.querySelector("#diffExplanation"),
  approveFixButton: document.querySelector("#approveFixButton"),
  discardFixButton: document.querySelector("#discardFixButton"),
  agentsDialog: document.querySelector("#agentsDialog"),
  reportDialog: document.querySelector("#reportDialog"),
  chatDialog: document.querySelector("#chatDialog"),
  emptyStateTemplate: document.querySelector("#emptyStateTemplate"),
};

const state = {
  mode: "url",
  issueFilter: "all",
  analysis: null,
  sessions: [],
  nextId: 1,
  contextId: getContextId(),
  progressTimer: null,
  progressIndex: 0,
  pendingFix: null,
  reportText: "",
  reportModel: "",
  downloadFormat: "md",
};

const scoreLabels = {
  technical: "Technical SEO",
  geo_visibility: "GEO visibility",
  llm_visibility: "LLM visibility",
  trust: "Trust",
  extractability: "Extractability",
  citability: "Citability",
  performance: "Performance",
};

function getContextId() {
  const key = "geo_juma_context_id";
  const existing = window.localStorage.getItem(key);
  if (existing) return existing;

  const fresh =
    window.crypto && window.crypto.randomUUID
      ? window.crypto.randomUUID()
      : `local-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  window.localStorage.setItem(key, fresh);
  return fresh;
}

function wsUrl() {
  const raw = els.daemonUrl.value.trim() || "http://127.0.0.1:7777";
  const url = new URL(raw);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = "/ws";
  url.search = "";
  url.hash = "";
  return url.toString();
}

function setStatus(text, kind = "offline") {
  els.statusText.textContent = text;
  els.statusDot.className = `dot ${kind}`;
}

function setBusy(button, busy, label) {
  if (!button) return;
  const labelEl = button.querySelector(".button-label");
  if (busy) {
    button.dataset.label = labelEl ? labelEl.textContent : button.textContent;
    if (labelEl) {
      labelEl.textContent = label || "Working";
    } else {
      button.textContent = label || "Working";
    }
    button.disabled = true;
  } else {
    if (labelEl) {
      labelEl.textContent = button.dataset.label || labelEl.textContent;
    } else {
      button.textContent = button.dataset.label || button.textContent;
    }
    button.disabled = false;
    delete button.dataset.label;
  }
}

function safeText(value, fallback = "") {
  const text = value === null || value === undefined ? "" : String(value);
  return text || fallback;
}

function formatScore(value) {
  return Number.isFinite(Number(value)) ? String(Math.round(Number(value))) : "--";
}

function formatMetricValue(metric, value) {
  if (!Number.isFinite(Number(value))) return "--";
  const number = Number(value);
  if (metric.unit === "rate") return `${Math.round(number * 100)}%`;
  if (metric.unit === "indicator") return number >= 1 ? "Yes" : "No";
  return Number.isInteger(number) ? String(number) : number.toFixed(3);
}

function formatMetricDelta(metric) {
  if (!Number.isFinite(Number(metric && metric.delta))) return "--";
  const delta = Number(metric.delta);
  if (metric.unit === "rate") {
    const points = Math.round(delta * 100);
    return `${points > 0 ? "+" : ""}${points} pp`;
  }
  if (metric.unit === "indicator") return delta > 0 ? "+1" : String(delta);
  return `${delta > 0 ? "+" : ""}${Number.isInteger(delta) ? delta : delta.toFixed(3)}`;
}

function wsCall(method, params = null, options = {}) {
  const id = state.nextId++;
  const socket = new WebSocket(wsUrl());
  const payloadParams =
    method === "actions.call" || method === "runners.run"
      ? { ...(params || {}), session: options.session || state.contextId }
      : params;

  return new Promise((resolve, reject) => {
    let settled = false;
    const timeout = window.setTimeout(() => {
      settled = true;
      socket.close();
      reject(new Error("Timed out waiting for agent.d"));
    }, options.timeout || 140000);

    socket.addEventListener("open", () => {
      socket.send(JSON.stringify({ id, method, params: payloadParams }));
    });

    socket.addEventListener("message", (event) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeout);
      socket.close();

      let payload;
      try {
        payload = JSON.parse(event.data);
      } catch {
        reject(new Error("agent.d returned invalid JSON"));
        return;
      }

      if (!payload.ok) {
        reject(new Error(payload.error || payload.code || "agent.d request failed"));
        return;
      }
      resolve(payload.result);
    });

    socket.addEventListener("error", () => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeout);
      reject(new Error("Could not connect to agent.d"));
    });

    socket.addEventListener("close", () => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeout);
      reject(new Error("agent.d connection closed before a response"));
    });
  });
}

async function callAction(name, args = {}, options = {}) {
  const envelope = await wsCall(
    "actions.call",
    {
      name,
      args: { ...args, context_id: state.contextId },
    },
    options,
  );
  return envelope.result;
}

function showToast(message, kind = "system") {
  const toast = document.createElement("div");
  toast.className = `toast ${kind === "system" ? "error" : ""}`;
  toast.textContent = safeText(message);
  els.toastRegion.append(toast);
  window.setTimeout(() => toast.remove(), 5200);
}

function showFormulaToast(metric) {
  if (!metric || !metric.formula) return;
  const toast = document.createElement("div");
  toast.className = "toast formula-toast";
  toast.innerHTML = `<strong></strong><code></code><span></span>`;
  toast.querySelector("strong").textContent = metric.label || metric.id || "Formula";
  toast.querySelector("code").textContent = metric.formula;
  toast.querySelector("span").textContent = metric.reference || "";
  if (!metric.reference) toast.querySelector("span").remove();
  els.toastRegion.append(toast);
  window.setTimeout(() => toast.remove(), 9000);
}

function addMessage(role, text) {
  const li = document.createElement("li");
  li.className = `message ${role}`;
  li.textContent = safeText(text);
  els.messages.append(li);
  li.scrollIntoView({ block: "end" });
}

function renderHistory(history) {
  els.messages.replaceChildren();
  if (!Array.isArray(history) || history.length === 0) {
    addMessage(
      "system",
      "Coordinator ready. Run an analysis, then ask for implementation steps or benchmark interpretation.",
    );
    return;
  }

  for (const turn of history) {
    const role = turn.role === "assistant" || turn.role === "user" ? turn.role : "system";
    addMessage(role, turn.content || "");
  }
}

function emptyNode(message) {
  const node = els.emptyStateTemplate.content.firstElementChild.cloneNode(true);
  if (message) node.querySelector("p").textContent = message;
  return node;
}

function inlineEmpty(message) {
  const node = document.createElement("div");
  node.className = "inline-empty";
  node.textContent = message;
  return node;
}

function renderEmpty() {
  els.pageTitle.textContent = "No analysis loaded";
  els.overallScore.textContent = "--";
  els.projectedScore.textContent = "--";
  els.scoreDelta.textContent = "No benchmark yet";
  els.issueCount.textContent = "0";
  els.wordCount.textContent = "--";
  els.pageMeta.textContent = "Choose an input source and run the scan.";
  els.scoreBreakdown.replaceChildren();
  renderBenchmarkComparison(null);
  renderAgentActivity([]);
  els.agentGrid.replaceChildren(emptyNode("The eight-agent workflow will appear after the first scan."));
  els.issuesList.replaceChildren(emptyNode("Detected issues will appear here."));
  renderRecommendations([]);
}

function renderBenchmarkComparison(analysis) {
  els.benchmarkComparison.replaceChildren();
  const comparison = analysis && analysis.benchmark && analysis.benchmark.comparison;
  if (!comparison) {
    els.benchmarkComparison.append(inlineEmpty("Benchmark comparison appears after the first saved scan."));
    return;
  }

  const meta = document.createElement("div");
  meta.className = "benchmark-meta";
  meta.textContent = comparison.baseline_available
    ? `Baseline ${comparison.baseline_session_id || "--"} -> current ${comparison.current_session_id || "--"}`
    : comparison.note || "No previous saved scan exists for this same website.";

  const table = document.createElement("table");
  table.className = "benchmark-table";
  table.innerHTML = `
    <thead>
      <tr>
        <th>Metric</th>
        <th>Before</th>
        <th>After</th>
        <th>Delta</th>
      </tr>
    </thead>
    <tbody></tbody>
  `;
  const tbody = table.querySelector("tbody");
  for (const metric of comparison.metrics || []) {
    const row = document.createElement("tr");
    row.innerHTML = `
      <th scope="row"><span></span><button type="button" class="formula-hint" hidden></button></th>
      <td></td>
      <td></td>
      <td></td>
    `;
    row.querySelector("span").textContent = metric.label || metric.id;
    const hint = row.querySelector(".formula-hint");
    if (metric.formula) {
      hint.hidden = false;
      hint.textContent = "ƒ formula";
      hint.addEventListener("click", () => showFormulaToast(metric));
    }
    const cells = row.querySelectorAll("td");
    cells[0].textContent = formatMetricValue(metric, metric.before);
    cells[1].textContent = formatMetricValue(metric, metric.after);
    cells[2].textContent = formatMetricDelta(metric);
    tbody.append(row);
  }

  els.benchmarkComparison.append(meta, table);
}

function renderAgentActivity(agents = []) {
  if (!els.agentActivity) return;
  els.agentActivity.replaceChildren();
  const fallback = [
    "Data",
    "Technical",
    "GEO/LLM",
    "Trust",
    "LLM test",
    "Recommend",
    "Score",
    "Report",
  ];

  const rows =
    agents.length > 0
      ? agents.map((agent, index) => ({
          label: (agent.name || fallback[index] || `Agent ${index + 1}`)
            .replace(/^Agent\s+\d+:\s*/i, "")
            .replace(/\s+Agent$/i, ""),
          status: agent.status || "ready",
        }))
      : fallback.map((label) => ({ label, status: "idle" }));

  for (const row of rows.slice(0, 8)) {
    const item = document.createElement("div");
    item.className = `activity-step ${row.status}`;
    item.innerHTML = `
      <span class="activity-dot"><svg class="icon"><use href="#icon-check"></use></svg></span>
      <span></span>
    `;
    item.querySelector("span:last-child").textContent = row.label;
    els.agentActivity.append(item);
  }
}

// Real incremental progress: poll the live roster state on its own connection
// while geo.analyze runs, so each agent flips to `complete` as it finishes
// instead of every dot updating at once when the whole scan returns.
async function pollPipeline() {
  try {
    const result = await callAction("geo.pipeline_status", {}, { timeout: 8000 });
    if (result && Array.isArray(result.agents)) {
      renderAgentActivity(result.agents.map(normalizeAgentState));
    }
  } catch {
    // A dropped poll is harmless; the next tick (or the final render) recovers.
  }
}

function startActivityPlayback() {
  stopActivityPlayback();
  renderAgentActivity(
    ["Data", "Technical", "GEO/LLM", "Trust", "LLM test", "Recommend", "Scoring", "Report"].map(
      (name) => ({ name, status: "ready" }),
    ),
  );
  pollPipeline();
  state.progressTimer = window.setInterval(pollPipeline, 900);
}

function stopActivityPlayback() {
  if (state.progressTimer) {
    window.clearInterval(state.progressTimer);
    state.progressTimer = null;
  }
}

function bar(label, value) {
  const row = document.createElement("div");
  row.className = "bar-row";

  const labelEl = document.createElement("div");
  labelEl.className = "bar-label";
  labelEl.innerHTML = `<span></span><strong></strong>`;
  labelEl.querySelector("span").textContent = label;
  labelEl.querySelector("strong").textContent = formatScore(value);

  const track = document.createElement("div");
  track.className = "bar-track";
  const fill = document.createElement("div");
  fill.className = "bar-fill";
  fill.style.width = `${Math.max(0, Math.min(100, Number(value) || 0))}%`;
  track.append(fill);

  row.append(labelEl, track);
  return row;
}

function renderScores(analysis) {
  const scores = analysis.scores || {};
  const benchmark = analysis.benchmark || {};
  els.overallScore.textContent = formatScore(scores.overall);
  els.projectedScore.textContent = formatScore(benchmark.after);
  els.scoreDelta.textContent =
    Number.isFinite(Number(benchmark.delta)) && Number(benchmark.delta) > 0
      ? `+${Math.round(benchmark.delta)} projected after fixes`
      : "Projected from current findings";
  els.issueCount.textContent = String(benchmark.issue_count || 0);
  els.wordCount.textContent = formatScore(analysis.metrics && analysis.metrics.word_count);

  const title = analysis.input && analysis.input.title ? analysis.input.title : "Untitled input";
  const source = analysis.input && (analysis.input.url || analysis.input.project_path || analysis.input.source_type);
  els.pageTitle.textContent = title;
  els.pageMeta.textContent = source ? String(source) : safeText(analysis.input && analysis.input.source_type, "Local input");

  els.scoreBreakdown.replaceChildren();
  for (const [key, label] of Object.entries(scoreLabels)) {
    els.scoreBreakdown.append(bar(label, scores[key]));
  }
  renderBenchmarkComparison(analysis);
}

function normalizeAgentState(agent) {
  if (!agent) return agent;
  const name = safeText(agent.name);
  const isReporting = /reporting/i.test(name);
  if (isReporting && safeText(agent.status).toLowerCase() === "pending") {
    return {
      ...agent,
      status: "ready",
      output: agent.output || "Generate the optimization report to run this agent.",
    };
  }
  return agent;
}

function sessionHost(session) {
  const source = safeText(session.source || session.site_key);
  try {
    return new URL(source).host.replace(/^www\./, "");
  } catch {
    return source;
  }
}

function sessionOrigin(session) {
  try {
    return new URL(safeText(session.source)).origin;
  } catch {
    return "";
  }
}

// The whole card is a button: clicking it loads the full session as if it were
// just scanned. Two text lines (title + host) plus a favicon and score badge.
function sessionCard(session) {
  const item = document.createElement("button");
  item.type = "button";
  item.className = "session-item";
  item.dataset.sessionId = session.session_id || "";
  item.innerHTML = `
    <span class="session-favicon"></span>
    <span class="session-text">
      <span class="session-title"></span>
      <span class="session-sub"></span>
    </span>
    <span class="session-score" hidden></span>
  `;

  const host = sessionHost(session);
  const fav = item.querySelector(".session-favicon");
  const origin = sessionOrigin(session);
  const letter = (host || safeText(session.title, "?")).charAt(0).toUpperCase();
  if (origin) {
    const img = document.createElement("img");
    img.alt = "";
    img.loading = "lazy";
    img.src = `${origin}/favicon.ico`;
    img.addEventListener("error", () => {
      img.remove();
      fav.textContent = letter;
    });
    fav.append(img);
  } else {
    fav.textContent = letter;
  }

  item.querySelector(".session-title").textContent = safeText(session.title, "Untitled input");
  item.querySelector(".session-sub").textContent = host || "Local input";

  const score = item.querySelector(".session-score");
  if (Number.isFinite(Number(session.score))) {
    score.hidden = false;
    score.textContent = formatScore(session.score);
    score.title = "Overall GEO readiness /100";
  }
  return item;
}

function renderSessions(sessions = []) {
  state.sessions = sessions;
  if (!els.sideSessionsList) return;
  els.sideSessionsList.replaceChildren();
  if (!sessions.length) {
    els.sideSessionsList.append(inlineEmpty("Saved scans will appear here after the first analysis."));
    return;
  }
  // Newest first, every session, no cap.
  for (const session of [...sessions].reverse()) {
    els.sideSessionsList.append(sessionCard(session));
  }
}

function renderSessionsError(message) {
  if (els.sideSessionsList) els.sideSessionsList.replaceChildren(inlineEmpty(message));
}

function renderAgents(agents = []) {
  renderAgentActivity(agents);
  els.agentGrid.replaceChildren();
  if (!agents.length) {
    els.agentGrid.append(emptyNode("No agent state is available."));
    return;
  }

  for (const agent of agents) {
    const card = document.createElement("article");
    card.className = "agent-card";
    const status = safeText(agent.status, "ready");
    const pillClass = `status-pill ${status}`;
    card.innerHTML = `
      <h3></h3>
      <span class="${pillClass}"></span>
      <p></p>
    `;
    card.querySelector("h3").textContent = safeText(agent.name);
    card.querySelector("span").textContent = status;
    card.querySelector("p").textContent = safeText(agent.output);
    els.agentGrid.append(card);
  }
}

function renderIssues(issues = []) {
  els.issuesList.replaceChildren();
  const visible = issues.filter(
    (issue) => state.issueFilter === "all" || issue.severity === state.issueFilter,
  );

  if (!visible.length) {
    els.issuesList.append(emptyNode("No issues match the current filter."));
    return;
  }

  for (const issue of visible) {
    const item = document.createElement("article");
    item.className = "issue-item";
    item.innerHTML = `
      <div><span class="severity"></span></div>
      <div class="issue-main">
        <h3></h3>
        <p class="evidence"></p>
        <p class="recommendation"></p>
      </div>
      <div class="issue-meta"></div>
    `;
    const severity = item.querySelector(".severity");
    severity.classList.add(issue.severity || "low");
    severity.textContent = issue.severity || "low";
    item.querySelector("h3").textContent = safeText(issue.title);
    item.querySelector(".evidence").textContent = safeText(issue.evidence);
    item.querySelector(".recommendation").textContent = safeText(issue.recommendation);
    item.querySelector(".issue-meta").textContent = `${safeText(issue.category)}\n${safeText(issue.agent)}\n${safeText(issue.method)}`;

    // AI fix is only meaningful for local project scans, and only for issues
    // the backend flagged as resolvable by editing files.
    const projectPath = state.analysis && state.analysis.input && state.analysis.input.project_path;
    if (projectPath && issue.fixable) {
      const main = item.querySelector(".issue-main");
      const button = document.createElement("button");
      button.type = "button";
      button.className = "command-button fix-button";
      button.textContent = "Get AI recommendation";
      const note = document.createElement("p");
      note.className = "fix-note";
      note.hidden = true;
      button.addEventListener("click", () => requestFix(issue, button, note));
      main.append(button, note);
    }

    els.issuesList.append(item);
  }
}

async function requestFix(issue, button, note) {
  button.disabled = true;
  const original = button.textContent;
  button.textContent = "Thinking…";
  note.hidden = true;
  try {
    const path = state.analysis.input.project_path;
    const result = await callAction("geo.recommend_fix", { issue, path }, { timeout: 180000 });
    if (result.not_fixable || !result.files || !result.files.length) {
      note.textContent = result.explanation || "The AI could not produce a file fix for this issue.";
      note.hidden = false;
      return;
    }
    openDiffDialog(result);
  } catch (error) {
    showToast(error.message);
  } finally {
    button.disabled = false;
    button.textContent = original;
  }
}

function openDiffDialog(fix) {
  state.pendingFix = fix;
  els.diffExplanation.textContent = safeText(fix.explanation, "Review the change before applying.");
  els.diffView.replaceChildren();
  for (const line of (fix.diff || "").split("\n")) {
    const row = document.createElement("span");
    row.className = "diff-line";
    if (line.startsWith("+") && !line.startsWith("+++")) row.classList.add("diff-add");
    else if (line.startsWith("-") && !line.startsWith("---")) row.classList.add("diff-del");
    else if (line.startsWith("@@")) row.classList.add("diff-hunk");
    row.textContent = line || " ";
    els.diffView.append(row, document.createTextNode("\n"));
  }
  openDialog(els.diffDialog);
}

async function approveFix() {
  const fix = state.pendingFix;
  if (!fix || !fix.files || !fix.files.length) return;
  els.approveFixButton.disabled = true;
  try {
    const path = state.analysis.input.project_path;
    const files = fix.files.map((file) => ({ path: file.path, new_content: file.new_content }));
    const result = await callAction("geo.apply_fix", { files, path }, { timeout: 60000 });
    showToast(`Applied ${result.written.length} file(s) — re-scan to refresh scores`, "info");
    state.pendingFix = null;
    closeDiffDialog();
  } catch (error) {
    showToast(error.message);
  } finally {
    els.approveFixButton.disabled = false;
  }
}

function closeDiffDialog() {
  state.pendingFix = null;
  const dialog = els.diffDialog;
  if (dialog && dialog.open) dialog.close();
}

function renderRecommendations(recommendations = []) {
  els.recommendationsList.replaceChildren();
  if (!recommendations.length) {
    const li = document.createElement("li");
    li.textContent = "No recommendations yet.";
    els.recommendationsList.append(li);
    return;
  }

  for (const rec of recommendations.slice(0, 5)) {
    const li = document.createElement("li");
    const expected = rec.expected_delta ? `Expected +${rec.expected_delta}` : "";
    li.innerHTML = `<strong></strong><span></span>`;
    li.querySelector("strong").textContent = safeText(rec.title);
    li.querySelector("span").textContent = `${safeText(rec.action)} ${expected}`.trim();
    els.recommendationsList.append(li);
  }
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

// Minimal, dependency-free markdown for the report subset the agent emits:
// headings, bold, inline code, and "-"/"*" bullet lists with paragraphs.
function renderMarkdown(text) {
  const inline = (raw) =>
    escapeHtml(raw)
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/`([^`]+?)`/g, "<code>$1</code>");

  const lines = String(text || "").replace(/\r\n/g, "\n").split("\n");
  const out = [];
  let list = null;
  let paragraph = [];

  const flushParagraph = () => {
    if (paragraph.length) {
      out.push(`<p>${inline(paragraph.join(" "))}</p>`);
      paragraph = [];
    }
  };
  const flushList = () => {
    if (list) {
      out.push(`<ul>${list.join("")}</ul>`);
      list = null;
    }
  };

  for (const line of lines) {
    const trimmed = line.trim();
    const heading = trimmed.match(/^(#{1,6})\s+(.*)$/);
    const bullet = trimmed.match(/^[-*]\s+(.*)$/);

    if (trimmed === "") {
      flushParagraph();
      flushList();
    } else if (heading) {
      flushParagraph();
      flushList();
      const level = Math.min(heading[1].length + 2, 6);
      out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
    } else if (bullet) {
      flushParagraph();
      list = list || [];
      list.push(`<li>${inline(bullet[1])}</li>`);
    } else {
      flushList();
      paragraph.push(trimmed);
    }
  }
  flushParagraph();
  flushList();
  return out.join("\n");
}

function setReportContent(text) {
  const value = safeText(text);
  state.reportText = value;
  els.reportOutput.innerHTML = renderMarkdown(value);
  if (els.downloadSplit) els.downloadSplit.hidden = false;
  if (els.downloadReportButton) els.downloadReportButton.disabled = false;
  if (els.downloadMenuButton) els.downloadMenuButton.disabled = false;
}

function setReportPlaceholder(text) {
  state.reportText = "";
  els.reportOutput.textContent = safeText(text);
  if (els.downloadReportButton) els.downloadReportButton.disabled = true;
  if (els.downloadMenuButton) els.downloadMenuButton.disabled = true;
  closeDownloadMenu();
}

function renderAnalysis(analysis) {
  if (Array.isArray(analysis.agents)) {
    analysis.agents = analysis.agents.map(normalizeAgentState);
  }
  state.analysis = analysis;
  renderScores(analysis);
  renderAgents(analysis.agents || []);
  renderIssues(analysis.issues || []);
  renderRecommendations(analysis.recommendations || []);
  if (analysis.report && analysis.report.text) {
    setReportContent(analysis.report.text);
    state.reportModel = analysis.report.model || "";
  } else {
    setReportPlaceholder("Report not generated for this scan yet.");
  }
}

function switchMode(mode) {
  state.mode = mode;
  for (const tab of els.modeTabs) {
    tab.classList.toggle("active", tab.dataset.mode === mode);
  }
  for (const field of els.modeFields) {
    field.classList.toggle("hidden", field.dataset.field !== mode);
  }
}

function setFilter(filter) {
  state.issueFilter = filter;
  for (const button of els.filterButtons) {
    button.classList.toggle("active", button.dataset.filter === filter);
  }
  if (state.analysis) renderIssues(state.analysis.issues || []);
}

function readFile(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve({ name: file.webkitRelativePath || file.name, body: String(reader.result || "") });
    reader.onerror = () => reject(new Error(`Could not read ${file.name}`));
    reader.readAsText(file);
  });
}

async function uploadedHtml() {
  const files = Array.from(els.fileInput.files || []);
  if (!files.length) throw new Error("Choose at least one website file");

  const allowed = /\.(html?|mdx?|txt|jsx?|tsx?|vue|svelte|astro|php|json|ya?ml|toml)$/i;
  const selected = files.filter((file) => allowed.test(file.name)).slice(0, 80);
  if (!selected.length) throw new Error("No readable website files were selected");

  const parts = await Promise.all(selected.map(readFile));
  return parts.map((part) => `\n\n<!-- file: ${part.name} -->\n${part.body}`).join("\n");
}

async function buildAnalysisPayload() {
  // The robots.txt override is optional and may be omitted from customized UI builds.
  const robots = els.robotsInput?.value.trim() || "";
  if (state.mode === "url") {
    const url = els.urlInput.value.trim();
    if (!url) throw new Error("Website URL is required");
    return { action: "geo.analyze", args: { source_type: "url", url, robots } };
  }
  if (state.mode === "html") {
    const html = els.htmlInput.value.trim();
    if (!html) throw new Error("HTML content is required");
    return { action: "geo.analyze", args: { source_type: "html", html, robots } };
  }
  if (state.mode === "upload") {
    return {
      action: "geo.analyze",
      args: { source_type: "upload", html: await uploadedHtml(), robots },
    };
  }
  if (state.mode === "project") {
    const path = els.projectPathInput.value.trim();
    if (!path) throw new Error("Project path is required");
    return { action: "geo.project_scan", args: { path, robots } };
  }
  throw new Error("Unsupported input mode");
}

async function checkStatus() {
  setBusy(els.checkStatusButton, true, "Checking");
  try {
    setStatus("Checking agent.d", "busy");
    const health = await wsCall("health");
    const secret = await callAction("secrets.openai_status");
    const configured = secret && secret.configured;
    setStatus(`${health}; OpenAI key ${configured ? "configured" : "missing"}`, "online");
  } finally {
    setBusy(els.checkStatusButton, false);
  }
}

async function loadHistory() {
  const result = await callAction("chat.history");
  renderHistory(result.history);
}

async function loadLastAnalysis() {
  setBusy(els.loadLastButton, true, "Loading");
  try {
    setStatus("Loading last analysis", "busy");
    const result = await callAction("geo.last_analysis");
    if (result && result.analysis) {
      renderAnalysis(result.analysis);
      setStatus("Loaded last analysis", "online");
      showToast("Loaded last analysis", "info");
    } else {
      renderEmpty();
      setStatus("No stored analysis", "online");
      showToast("No stored analysis for this context", "info");
    }
  } catch (error) {
    setStatus("Load failed", "offline");
    showToast(error.message);
  } finally {
    setBusy(els.loadLastButton, false);
  }
}

async function loadSessions() {
  try {
    const result = await callAction("geo.sessions");
    renderSessions((result && result.sessions) || []);
  } catch (error) {
    renderSessionsError(error.message);
    showToast(error.message);
  }
}

async function restoreSession(sessionId) {
  if (!sessionId) return;
  setStatus("Loading saved session", "busy");
  try {
    const result = await callAction("geo.restore_session", { session_id: sessionId });
    renderSessions((result && result.sessions) || []);
    if (result && result.analysis) {
      renderAnalysis(result.analysis);
      setStatus("Session loaded", "online");
      showToast("Session loaded", "info");
    } else {
      setStatus("Session not found", "offline");
      showToast("That saved session could not be loaded");
    }
  } catch (error) {
    setStatus("Load failed", "offline");
    showToast(error.message);
  }
}

async function runAnalysis() {
  setBusy(els.runButton, true, "Analyzing");
  try {
    setStatus("Running multi-agent analysis", "busy");
    startActivityPlayback();
    setReportPlaceholder("Analysis in progress.");
    const payload = await buildAnalysisPayload();
    const analysis = await callAction(payload.action, payload.args, { timeout: 180000 });
    renderAnalysis(analysis);
    await loadSessions();
    setStatus("Analysis complete", "online");
    showToast("Analysis complete", "info");
  } catch (error) {
    setStatus("Analysis failed", "offline");
    showToast(error.message);
    setReportPlaceholder(error.message);
  } finally {
    stopActivityPlayback();
    setBusy(els.runButton, false);
  }
}

async function generateReport() {
  if (!state.analysis) {
    showToast("Run an analysis before generating a report", "info");
    return;
  }

  openDialog(els.reportDialog);
  setBusy(els.reportButton, true, "Writing");
  try {
    setStatus("Generating report", "busy");
    setReportPlaceholder("Generating report.");
    const result = await callAction("geo.report", { analysis: state.analysis }, { timeout: 180000 });
    setReportContent(result.report || "No report returned.");
    state.reportModel = result.model || "";
    if (state.analysis) {
      if (Array.isArray(result.agents)) {
        state.analysis.agents = result.agents.map(normalizeAgentState);
      }
      // The report just ran successfully, so Agent 8 is complete regardless of
      // what the backend snapshot reports (covers a not-yet-restarted daemon).
      state.analysis.agents = (state.analysis.agents || []).map((agent) =>
        agent && /reporting/i.test(safeText(agent.name))
          ? { ...agent, status: "complete", output: `Wrote the executive report (${result.model || "agent.d"}).` }
          : agent,
      );
      state.analysis.report = { text: result.report, model: result.model };
      renderAgents(state.analysis.agents || []);
    }
    setStatus(`Report ready (${result.model || "agent.d"})`, "online");
    showToast("Report ready", "info");
  } catch (error) {
    setReportPlaceholder(error.message);
    setStatus("Report failed", "offline");
    showToast(error.message);
  } finally {
    setBusy(els.reportButton, false);
  }
}

function reportFilenameBase() {
  const title = (state.analysis && state.analysis.input && state.analysis.input.title) || "geo-report";
  const slug = String(title)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);
  return slug || "geo-report";
}

function triggerDownload(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function downloadMarkdown() {
  const blob = new Blob([state.reportText], { type: "text/markdown;charset=utf-8" });
  triggerDownload(blob, `${reportFilenameBase()}.md`);
}

// PDF without a bundled library: render the report into a print window and let
// the browser's "Save as PDF" produce the file.
function downloadPdf() {
  const win = window.open("", "_blank");
  if (!win) {
    showToast("Allow pop-ups to export the report as PDF", "info");
    return;
  }
  const title = safeText(state.analysis && state.analysis.input && state.analysis.input.title, "GEO report");
  win.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>${escapeHtml(title)}</title>
    <style>
      body { font: 14px/1.55 -apple-system, Segoe UI, Roboto, sans-serif; color: #16191d; max-width: 720px; margin: 40px auto; padding: 0 24px; }
      h2, h3, h4 { line-height: 1.3; }
      code { font-family: ui-monospace, SF Mono, monospace; background: #f2f1ec; padding: 1px 4px; border-radius: 3px; }
      ul { padding-left: 20px; }
      li { margin: 3px 0; }
    </style></head><body>${renderMarkdown(state.reportText)}</body></html>`);
  win.document.close();
  win.focus();
  win.addEventListener("load", () => {
    win.print();
  });
  // Fallback if `load` already fired for the written document.
  window.setTimeout(() => {
    try {
      win.print();
    } catch {
      /* print triggered on load */
    }
  }, 400);
}

function downloadReport() {
  if (!state.reportText) return;
  if (state.downloadFormat === "pdf") {
    downloadPdf();
  } else {
    downloadMarkdown();
  }
}

function closeDownloadMenu() {
  if (!els.downloadMenu) return;
  els.downloadMenu.hidden = true;
  if (els.downloadMenuButton) els.downloadMenuButton.setAttribute("aria-expanded", "false");
}

function toggleDownloadMenu() {
  if (!els.downloadMenu) return;
  const open = els.downloadMenu.hidden;
  els.downloadMenu.hidden = !open;
  els.downloadMenuButton.setAttribute("aria-expanded", String(open));
}

function selectDownloadFormat(format) {
  state.downloadFormat = format === "pdf" ? "pdf" : "md";
  if (els.downloadLabel) {
    els.downloadLabel.textContent = state.downloadFormat === "pdf" ? "Download PDF" : "Download .md";
  }
  closeDownloadMenu();
  downloadReport();
}

async function saveOpenAiKey() {
  const value = els.openaiKey.value.trim();
  if (!value) return;

  setBusy(els.saveKeyButton, true, "Saving");
  try {
    await callAction("secrets.set_openai_key", { value });
    els.openaiKey.value = "";
    setStatus("OpenAI key saved", "online");
    showToast("OpenAI key saved", "info");
  } catch (error) {
    setStatus("Key save failed", "offline");
    showToast(error.message);
  } finally {
    setBusy(els.saveKeyButton, false);
  }
}

async function clearMemory() {
  setBusy(els.clearButton, true, "Clearing");
  try {
    await callAction("chat.clear");
    stopActivityPlayback();
    state.analysis = null;
    state.sessions = [];
    state.pendingFix = null;
    state.reportModel = "";
    renderHistory([]);
    renderSessions([]);
    renderEmpty();
    setReportPlaceholder("No report generated yet.");
    closeDiffDialog();
    setStatus("All memory cleared", "online");
    showToast("All memory and saved sessions cleared", "info");
  } catch (error) {
    setStatus("Clear failed", "offline");
    showToast(error.message);
  } finally {
    setBusy(els.clearButton, false);
  }
}

els.modeTabs.forEach((tab) => {
  tab.addEventListener("click", () => switchMode(tab.dataset.mode));
});

els.filterButtons.forEach((button) => {
  button.addEventListener("click", () => setFilter(button.dataset.filter));
});

function openDialog(dialog) {
  if (!dialog) return;
  if (typeof dialog.showModal === "function") {
    dialog.showModal();
  } else {
    dialog.setAttribute("open", "");
  }
}

document.querySelectorAll(".dialog-close").forEach((button) => {
  button.addEventListener("click", () => {
    const dialog = button.closest("dialog");
    if (dialog) dialog.close();
  });
});

els.checkStatusButton.addEventListener("click", () => {
  checkStatus().catch((error) => {
    setStatus("Disconnected", "offline");
    showToast(error.message);
  });
});

els.loadLastButton.addEventListener("click", loadLastAnalysis);
els.runButton.addEventListener("click", runAnalysis);
els.reportButton.addEventListener("click", generateReport);
if (els.downloadReportButton) {
  els.downloadReportButton.addEventListener("click", downloadReport);
}
if (els.downloadMenuButton) {
  els.downloadMenuButton.addEventListener("click", (event) => {
    event.stopPropagation();
    toggleDownloadMenu();
  });
}
if (els.downloadMenu) {
  els.downloadMenu.addEventListener("click", (event) => {
    const item = event.target.closest("button[data-format]");
    if (item) selectDownloadFormat(item.dataset.format);
  });
}
document.addEventListener("click", (event) => {
  if (els.downloadSplit && !els.downloadSplit.contains(event.target)) closeDownloadMenu();
});
els.saveKeyButton.addEventListener("click", saveOpenAiKey);
els.clearButton.addEventListener("click", clearMemory);
els.settingsButton.addEventListener("click", () => openDialog(els.settingsDialog));
els.openIssuesButton.addEventListener("click", () => openDialog(els.issuesDialog));
if (els.approveFixButton) els.approveFixButton.addEventListener("click", approveFix);
if (els.discardFixButton) els.discardFixButton.addEventListener("click", closeDiffDialog);
els.openAgentsButton.addEventListener("click", () => openDialog(els.agentsDialog));
els.openReportButton.addEventListener("click", () => openDialog(els.reportDialog));
els.openChatButton.addEventListener("click", () => openDialog(els.chatDialog));

els.sideSessionsList.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-session-id]");
  if (button) restoreSession(button.dataset.sessionId);
});

els.chatForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const message = els.prompt.value.trim();
  if (!message) return;

  els.prompt.value = "";
  addMessage("user", message);
  setBusy(els.sendButton, true, "Sending");
  try {
    setStatus("Coordinator thinking", "busy");
    const result = await callAction("chat.send", { message }, { timeout: 180000 });
    addMessage("assistant", result.reply || "");
    setStatus(`Connected; ${result.provider || "provider"} ${result.model || ""}`.trim(), "online");
  } catch (error) {
    showToast(error.message);
  } finally {
    setBusy(els.sendButton, false);
  }
});

els.contextLabel.textContent = `Context ${state.contextId.slice(0, 8)}`;
renderEmpty();

// Boot each surface in sequence: every wsCall opens its own short-lived
// socket, and firing four at once races on the daemon handshake (the sessions
// call lost that race, so the list looked empty until reopened). Awaiting them
// one at a time is both reliable and independently fault-tolerant.
(async () => {
  try {
    await loadSessions();
  } catch (error) {
    showToast(error.message);
  }
  try {
    await loadLastAnalysis();
  } catch (error) {
    showToast(error.message);
  }
  try {
    await loadHistory();
  } catch {
    renderHistory([]);
  }
  try {
    await checkStatus();
  } catch {
    setStatus("Disconnected", "offline");
  }
})();
