-- geo.* actions: the analysis surface exposed over the WS interface.
return function(deps)
	local config = deps.config
	local util = deps.util
	local store = deps.store
	local sources = deps.sources
	local governor = deps.governor
	local recommendation = deps.recommendation

	local MEM = config.MEMORY_ROOT

	agentd.action({
		name = "geo.analyze",
		requires = {
			"ai:openai",
			"net:*",
			"memory.read:" .. MEM .. "/**",
			"memory.write:" .. MEM .. "/**",
		},
		handler = function(args, ctx)
			args = args or {}
			local source_type = util.trim(args.source_type)
			if source_type == "" then source_type = "url" end

			local source = {
				source_type = source_type,
				url = util.trim(args.url),
				html = util.trim(args.html),
				robots = util.trim(args.robots),
			}

			if source_type == "url" then
				source.html = sources.fetch_url(source.url, ctx)
			elseif source_type == "html" or source_type == "upload" then
				if source.html == "" then error("geo.analyze: `html` is required") end
			else
				error("geo.analyze: unsupported source_type `" .. source_type .. "`")
			end

			local result = governor.analyze(args, ctx, source)
			local mem = store.memory_for(ctx, args)
			store.stamp_analysis(result, mem)
			local baseline = store.previous_for_site(mem, result.input and result.input.site_key or "")
			governor.attach_session_comparison(result, baseline)
			store.save_analysis(mem, result)
			return result
		end,
	})

	agentd.action({
		name = "geo.project_scan",
		requires = {
			"ai:openai",
			"fs.read:*",
			"memory.read:" .. MEM .. "/**",
			"memory.write:" .. MEM .. "/**",
		},
		handler = function(args, ctx)
			args = args or {}
			local root = util.trim(args.path)
			if root == "" then error("geo.project_scan: `path` is required") end

			local max_files = tonumber(args.max_files or 120) or 120
			local project = sources.collect_project(root, max_files, ctx)
			if project.collected_count == 0 then
				error("geo.project_scan: no readable website/source files were found")
			end

			local source = {
				source_type = "project",
				url = "",
				html = project.html,
				robots = project.robots,
				project_files = project.file_count,
				project_path = root,
			}
			local result = governor.analyze(args, ctx, source)
			result.input.project_path = root
			local mem = store.memory_for(ctx, args)
			store.stamp_analysis(result, mem)
			local baseline = store.previous_for_site(mem, result.input and result.input.site_key or "")
			governor.attach_session_comparison(result, baseline)
			store.save_analysis(mem, result)
			return result
		end,
	})

	agentd.action({
		name = "geo.pipeline_status",
		requires = {},
		handler = function()
			return { agents = governor.states() }
		end,
	})

	agentd.action({
		name = "geo.last_analysis",
		requires = { "memory.read:" .. MEM .. "/**" },
		handler = function(args, ctx)
			return { analysis = store.memory_for(ctx, args):get("last_analysis") }
		end,
	})

	agentd.action({
		name = "geo.sessions",
		requires = { "memory.read:" .. MEM .. "/**" },
		handler = function(args, ctx)
			local mem = store.memory_for(ctx, args or {})
			return { sessions = store.list_sessions(mem) }
		end,
	})

	agentd.action({
		name = "geo.restore_session",
		requires = {
			"memory.read:" .. MEM .. "/**",
			"memory.write:" .. MEM .. "/**",
		},
		handler = function(args, ctx)
			args = args or {}
			local mem = store.memory_for(ctx, args)
			local analysis = store.restore_session(mem, args.session_id)
			if not analysis then error("geo.restore_session: saved session not found") end
			return {
				analysis = analysis,
				sessions = store.list_sessions(mem),
			}
		end,
	})

	agentd.action({
		name = "geo.report",
		requires = {
			"ai:openai",
			"memory.read:" .. MEM .. "/**",
			"memory.write:" .. MEM .. "/**",
		},
		handler = function(args, ctx)
			args = args or {}
			local mem = store.memory_for(ctx, args)
			local analysis = args.analysis or mem:get("last_analysis")
			if not analysis then error("geo.report: run an analysis first") end

			local report = governor.report(analysis, store.analysis_summary, ctx, args)
			mem:set("last_report", report.text)
			-- Persist the report alongside the analysis so a restored session
			-- shows it and the Reporting agent reads as `complete`.
			if type(analysis) == "table" then
				if type(report.agents) == "table" then analysis.agents = report.agents end
				analysis.report = { text = report.text, model = report.model }
				mem:set("last_analysis", analysis)
			end
			return { report = report.text, model = report.model, agents = report.agents }
		end,
	})

	-- Asks the AI for a concrete file edit that resolves a single issue, then
	-- returns a unified diff for review. Writes NOTHING — apply happens only on
	-- explicit approval via geo.apply_fix. Project-scan only: the supplied
	-- `path` must match the last analysis's project root.
	agentd.action({
		name = "geo.recommend_fix",
		requires = {
			"ai:openai",
			"fs.read:*",
			"memory.read:" .. MEM .. "/**",
		},
		handler = function(args, ctx)
			args = args or {}
			local issue = args.issue
			if type(issue) ~= "table" then error("geo.recommend_fix: `issue` is required") end

			local path = util.trim(args.path)
			local analysis = store.memory_for(ctx, args):get("last_analysis")
			local root = analysis and analysis.input and util.trim(analysis.input.project_path) or ""
			if root == "" then
				error("geo.recommend_fix: the last analysis was not a local project scan")
			end
			if path == "" then path = root end
			if util.normalize_path(path) ~= util.normalize_path(root) then
				error("geo.recommend_fix: `path` does not match the scanned project root")
			end

			local project = sources.collect_project(root, tonumber(args.max_files or 120) or 120, ctx)
			if project.collected_count == 0 then
				error("geo.recommend_fix: no readable project files were found")
			end

			local fix = recommendation.fix(issue, project.html, ctx, args)
			if fix.not_fixable then
				return { not_fixable = true, explanation = fix.explanation, files = {}, diff = "" }
			end

			local files = {}
			local diffs = {}
			for _, file in ipairs(fix.files) do
				if not util.path_inside(root, file.path) then
					error("geo.recommend_fix: refused path outside project root: " .. file.path)
				end
				local read_ok, old = pcall(ctx.fs.read, file.path)
				if not read_ok or old == nil then old = "" end
				local diff = util.unified_diff(file.path, old, file.new_content)
				files[#files + 1] = {
					path = file.path,
					new_content = file.new_content,
					diff = diff,
				}
				if diff ~= "" then diffs[#diffs + 1] = diff end
			end

			return {
				not_fixable = false,
				explanation = fix.explanation,
				files = files,
				diff = table.concat(diffs, "\n\n"),
			}
		end,
	})

	-- Writes approved fix content to disk. In-place, no backup. Every target is
	-- re-validated against the scanned project root before writing.
	agentd.action({
		name = "geo.apply_fix",
		requires = {
			"fs.read:*",
			"fs.write:*",
			"memory.read:" .. MEM .. "/**",
		},
		handler = function(args, ctx)
			args = args or {}
			local files = args.files
			if type(files) ~= "table" or #files == 0 then
				error("geo.apply_fix: `files` is required and must be non-empty")
			end

			local path = util.trim(args.path)
			local analysis = store.memory_for(ctx, args):get("last_analysis")
			local root = analysis and analysis.input and util.trim(analysis.input.project_path) or ""
			if root == "" then
				error("geo.apply_fix: the last analysis was not a local project scan")
			end
			if path == "" then path = root end
			if util.normalize_path(path) ~= util.normalize_path(root) then
				error("geo.apply_fix: `path` does not match the scanned project root")
			end

			local written = {}
			for _, file in ipairs(files) do
				if type(file) ~= "table" or not file.path or file.new_content == nil then
					error("geo.apply_fix: each file needs `path` and `new_content`")
				end
				if not util.path_inside(root, file.path) then
					error("geo.apply_fix: refused path outside project root: " .. tostring(file.path))
				end
				local ok, err = pcall(ctx.fs.write, file.path, tostring(file.new_content))
				if not ok then
					error("geo.apply_fix: write failed for " .. file.path .. ": " .. tostring(err))
				end
				written[#written + 1] = file.path
			end

			return { written = written }
		end,
	})
end
