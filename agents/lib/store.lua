-- Per-context durable memory: namespace resolution, chat history,
-- and analysis summaries shared by the chat and report actions.
return function(config)
	local store = {}

	function store.memory_for(ctx, args)
		local explicit = args and (args.context_id or args.project_id)
		local session = explicit or ctx.caller.session or "local"
		return ctx.memory.create(config.MEMORY_ROOT .. "/" .. tostring(session))
	end

	function store.append_turn(history, role, content)
		history[#history + 1] = {
			role = role,
			content = tostring(content or ""),
		}

		while #history > config.HISTORY_LIMIT do
			table.remove(history, 1)
		end
	end

	function store.analysis_summary(analysis)
		if not analysis then return "No analysis is available." end
		local parts = {
			"Overall score: " .. tostring(analysis.scores and analysis.scores.overall or "?"),
			"Projected score: " .. tostring(analysis.benchmark and analysis.benchmark.after or "?"),
			"Issues: " .. tostring(analysis.benchmark and analysis.benchmark.issue_count or "?"),
			"Words: " .. tostring(analysis.metrics and analysis.metrics.word_count or "?"),
		}
		local comparison = analysis.benchmark and analysis.benchmark.comparison
		if comparison and comparison.baseline_available then
			parts[#parts + 1] = "Baseline session: " .. tostring(comparison.baseline_session_id or "?")
			parts[#parts + 1] = "Current session: " .. tostring(comparison.current_session_id or "?")
			for _, metric in ipairs(comparison.metrics or {}) do
				parts[#parts + 1] = tostring(metric.label or metric.id) .. ": before "
					.. tostring(metric.before or "?") .. ", after " .. tostring(metric.after or "?")
					.. ", delta " .. tostring(metric.delta or "?")
			end
		end
		if analysis.input and analysis.input.title and analysis.input.title ~= "" then
			parts[#parts + 1] = "Title: " .. analysis.input.title
		end
		return table.concat(parts, "\n")
	end

	local function has_session(history, session_id)
		for _, item in ipairs(history or {}) do
			if tostring(item and item.session_id or "") == tostring(session_id or "") then
				return true
			end
		end
		return false
	end

	function store.stamp_analysis(analysis, mem)
		local execution = tostring(analysis.execution or "local")
		local history = mem and store.history(mem) or {}
		analysis.session_id = analysis.session_id
			or execution
		if analysis.session_id == "" or analysis.session_id == "local" or has_session(history, analysis.session_id) then
			analysis.session_id = "scan-" .. tostring(#history + 1)
		end
		analysis.created_at = analysis.created_at or execution
		if analysis.created_at == "" or analysis.created_at == "local" then
			analysis.created_at = analysis.session_id
		end
		return analysis
	end

	function store.history(mem)
		local history = mem:get("analysis_sessions")
		if type(history) ~= "table" then return {} end
		return history
	end

	local function first_text(...)
		for i = 1, select("#", ...) do
			local value = select(i, ...)
			local text = tostring(value or "")
			if text ~= "" then return text end
		end
		return ""
	end

	function store.session_summary(analysis)
		local input = analysis.input or {}
		local benchmark = analysis.benchmark or {}
		local comparison = benchmark.comparison or {}
		return {
			session_id = analysis.session_id,
			created_at = analysis.created_at,
			site_key = input.site_key or "",
			title = first_text(input.title, "Untitled input"),
			source = first_text(input.url, input.project_path, input.source_type),
			score = analysis.scores and analysis.scores.overall or nil,
			projected = benchmark.after,
			issue_count = benchmark.issue_count,
			baseline_session_id = comparison.baseline_session_id,
		}
	end

	function store.list_sessions(mem)
		local summaries = {}
		local history = store.history(mem)
		if #history == 0 then
			local last = mem:get("last_analysis")
			if type(last) == "table" then history = { last } end
		end
		for _, analysis in ipairs(history) do
			summaries[#summaries + 1] = store.session_summary(analysis)
		end
		return summaries
	end

	function store.previous_for_site(mem, site_key)
		local history = store.history(mem)
		for i = #history, 1, -1 do
			local analysis = history[i]
			local input = analysis and analysis.input or {}
			if input.site_key == site_key then return analysis end
		end
		local last = mem:get("last_analysis")
		local input = last and last.input or {}
		if type(last) == "table" and input.site_key == site_key then return last end
		return nil
	end

	function store.save_analysis(mem, analysis)
		local history = store.history(mem)
		history[#history + 1] = analysis
		mem:set("analysis_sessions", history)
		mem:set("last_analysis", analysis)
		return history
	end

	function store.restore_session(mem, session_id)
		for _, analysis in ipairs(store.history(mem)) do
			if tostring(analysis.session_id or "") == tostring(session_id or "") then
				mem:set("last_analysis", analysis)
				return analysis
			end
		end
		local last = mem:get("last_analysis")
		if type(last) == "table" and tostring(last.session_id or "") == tostring(session_id or "") then
			return last
		end
		return nil
	end

	return store
end
