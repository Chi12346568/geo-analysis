-- The governor drives the eight-agent GEO pipeline. It builds the evidence
-- document once, then dispatches every agent's AI runner in order, tracking
-- real per-agent status, persisting each agent's verdict in its own memory
-- namespace, and assembling the analysis result consumed by the webapp.
-- Fail-hard: a provider or contract failure aborts the analysis (the failing
-- agent is marked `failed`) instead of degrading to canned output.
return function(deps)
	local util = deps.util
	local html = deps.html
	local base = deps.base
	local sources = deps.sources
	local analyzers = deps.analyzers -- agents 1-5, in pipeline order
	local recommendation = deps.recommendation -- agent 6
	local scoring = deps.scoring -- agent 7
	local reporting = deps.reporting -- agent 8

	local governor = {}

	-- Decides whether an issue is fixable by editing the project's own files.
	-- `method` is free model text, so we classify on the lowercased
	-- method+category+title. The non-fixable denylist is checked first and
	-- wins on conflict (e.g. a "performance" issue that mentions headings stays
	-- non-fixable). The flag is meaningful only for local project scans, where
	-- there are files on disk to edit.
	local NOT_FIXABLE = {
		"https", "ssl", "robots", "payload", "size", "performance",
		"viewport", "mobile", "backlink", "external authority",
		"prompt test", "live test", "citation rate",
	}
	local FIXABLE = {
		"alt", "llms.txt", "llms_txt", "schema", "json-ld", "jsonld",
		"faq", "meta description", "description", "heading", "h1",
		"canonical", "structured answer", "direct answer", "internal link",
		"lang",
	}
	local function fixable(issue)
		local text = util.lower(
			tostring(issue.method or "") .. " "
				.. tostring(issue.category or "") .. " "
				.. tostring(issue.title or "")
		)
		for _, word in ipairs(NOT_FIXABLE) do
			if util.contains(text, word) then return false end
		end
		for _, word in ipairs(FIXABLE) do
			if util.contains(text, word) then return true end
		end
		return false
	end
	governor.fixable = fixable

	local roster = {
		analyzers[1], analyzers[2], analyzers[3], analyzers[4], analyzers[5],
		recommendation, scoring, reporting,
	}

	local function reset_states()
		for _, agent in ipairs(roster) do
			agent.status = "pending"
			agent.summary = ""
		end
	end

	local function agent_states()
		local states = {}
		for _, agent in ipairs(roster) do
			states[#states + 1] = {
				name = agent.name,
				status = agent.status,
				output = agent.summary,
			}
		end
		return states
	end

	local function resolve_robots(doc, ctx)
		local source = doc.source
		local robots = util.trim(source.robots)
		if robots == "" and source.url and source.url ~= "" then
			robots = sources.fetch_robots(source.url, ctx) or ""
			source.robots = robots
		end
		-- Agent 1 owns the robots policy facts.
		doc.robots_ok, doc.robots_evidence = analyzers[1].robots_allows_ai(robots)
	end

	local function normalized_url_key(url)
		local value = util.trim(url)
		if value == "" then return "" end
		local scheme, rest = value:match("^(https?)://(.+)$")
		if not scheme then return "" end
		rest = rest:gsub("[#?].*$", ""):gsub("/+$", "")
		if rest == "" then return "" end
		return "url:" .. util.lower(rest)
	end

	local function site_key_for(doc)
		local source = doc.source or {}
		local canonical = normalized_url_key(doc.canonical)
		if canonical ~= "" then return canonical end

		local url = normalized_url_key(source.url)
		if url ~= "" then return url end

		if util.trim(source.project_path) ~= "" then
			return "project:" .. util.lower(source.project_path)
		end

		local title = util.lower(util.trim(doc.title))
		if title ~= "" then
			return tostring(source.source_type or "input") .. ":" .. title
		end

		return tostring(source.source_type or "input") .. ":untitled"
	end

	-- Runs one agent step, tracking real status. A failure marks the agent
	-- `failed` and aborts the analysis.
	local function dispatch(agent, fn)
		agent.status = "running"
		local ok, result = pcall(fn)
		if not ok then
			agent.status = "failed"
			agent.summary = tostring(result)
			error(agent.name .. ": " .. tostring(result), 0)
		end
		agent.status = "complete"
		return result
	end

	-- Sends one analyzer's evidence through its runner and records the
	-- sanitized verdict in the agent's own memory namespace.
	local function run_analyzer(agent, doc, ctx, args)
		return dispatch(agent, function()
			local mem = base.memory(ctx, agent.slug, args)
			local verdict = base.invoke(ctx, agent.runner, base.VERDICT_CONTRACT, {
				role = agent.name,
				evidence = agent.evidence(doc),
				previous_verdict = mem:get("last_verdict"),
			})
			base.sanitize_verdict(agent.name, verdict)
			mem:set("last_verdict", verdict)
			agent.summary = verdict.summary
			return verdict
		end)
	end

	function governor.analyze(args, ctx, source)
		reset_states()
		local doc = html.build_document(source)
		resolve_robots(doc, ctx)

		-- Agents 1-5: independent analysis verdicts. They share no state, so
		-- they fan out across async coroutines — their model calls overlap
		-- instead of running back to back (this stage was ~5x its own
		-- wall-clock). `parallel_map` keeps results in input order, so the
		-- aggregation below stays deterministic; a failing agent still raises
		-- out of the join and aborts the scan (fail-hard preserved).
		local issues = {}
		-- Mechanical baseline derived from the page's own facts (no seed magic
		-- numbers); analyzer bonuses then adjust it dimension by dimension.
		local mechanical = scoring.baseline(doc)
		local verdicts = parallel_map(analyzers, function(agent)
			return run_analyzer(agent, doc, ctx, args)
		end)
		for _, verdict in ipairs(verdicts) do
			for _, issue in ipairs(verdict.issues) do
				-- Attach AFTER sanitize_verdict (which rebuilds issues into a
				-- fixed shape and would otherwise strip this field).
				issue.fixable = fixable(issue)
				issues[#issues + 1] = issue
			end
			for _, bonus in ipairs(verdict.bonuses) do
				mechanical[bonus.key] = util.clamp((mechanical[bonus.key] or 0) + bonus.delta, 0, 100)
			end
		end

		local metrics = {
			word_count = doc.words,
			html_bytes = #doc.html,
			headings = #doc.headings,
			h1_count = doc.h1_count,
			schema_markers = doc.schema_count,
			faq_schema = doc.faq_schema,
			internal_links = doc.internal_links,
			external_links = doc.external_links,
			images = doc.image_total,
			missing_alt = doc.missing_alt,
			structured_answer_score = doc.structured_answer_score,
			robots_evidence = doc.robots_evidence,
			project_files = source.project_files or 0,
		}

		-- Agent 6: prioritized fix list.
		local recommendations = dispatch(recommendation, function()
			return recommendation.build(issues, ctx, args)
		end)

		-- Agent 7: final dimension scores from the mechanical baseline.
		local scores = dispatch(scoring, function()
			return scoring.assess(mechanical, issues, metrics, ctx, args)
		end)
		local overall = scoring.overall(scores)
		local projected = scoring.projected(overall, issues)
		local rounded = scoring.rounded(scores)
		rounded.overall = overall

		local high_priority = 0
		for _, item in ipairs(issues) do
			if item.severity == "high" then high_priority = high_priority + 1 end
		end
		reporting.status = "ready"
		reporting.summary = "Generate the optimization report to run this agent."

		return {
			input = {
				source_type = source.source_type,
				url = source.url or "",
				canonical = doc.canonical or "",
				origin = sources.origin_from(source.url or ""),
				project_path = source.project_path or "",
				site_key = site_key_for(doc),
				title = doc.title,
				language = doc.lang,
			},
			scores = rounded,
			benchmark = {
				before = overall,
				after = projected,
				delta = projected - overall,
				issue_count = #issues,
				high_priority = high_priority,
			},
			metrics = metrics,
			issues = issues,
			recommendations = recommendations,
			agents = agent_states(),
			excerpt = string.sub(doc.text, 1, 1200),
			-- Correlation id for this scan. Every per-agent `runner:*` trace
			-- event from this run carries the same id, so the whole 8-agent
			-- tree is one `grep` away:
			--   agentctl trace | grep <execution>
			execution = ctx.caller.execution,
		}
	end

	-- Live snapshot of every agent's current status. Read by `geo.pipeline_status`
	-- on a separate connection while `geo.analyze` runs, so the webapp can show
	-- each agent flipping to `complete` incrementally instead of all at once.
	function governor.states()
		return agent_states()
	end

	function governor.attach_session_comparison(analysis, baseline)
		analysis.benchmark = analysis.benchmark or {}
		analysis.benchmark.comparison = scoring.session_comparison(analysis, baseline)
		return analysis
	end

	-- Agent 8: executive report, driven through the same dispatcher so the
	-- agent's status reflects the actual run.
	function governor.report(analysis, summary_of, ctx, args)
		reporting.status = "running"
		reporting.summary = "Writing the executive report."
		local result = dispatch(reporting, function()
			local text, model = reporting.write(analysis, summary_of, ctx, args)
			return { text = text, model = model }
		end)
		-- Surface the post-run status so the webapp can flip Agent 8 from
		-- `ready` to `complete` without a full re-scan.
		result.agents = agent_states()
		return result
	end

	return governor
end
