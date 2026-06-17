-- Agent 6: Recommendation Agent
-- Turns detected issues into a prioritized, impact-ordered fix list by
-- reasoning over the full issue set through its runner.
return function(util, config, base)
	local agent = {
		id = 6,
		name = "Agent 6: Recommendation Agent",
		slug = "recommendation",
		runner = "geo_juma_recommendation",
		skill = "geo-recommendation",
		summary = "",
		status = "pending",
	}

	agentd.runner({
		name = agent.runner,
		model = config.MODEL,
		skills = { agent.skill },
	})

	local CONTRACT = [[
Respond with a single JSON object and nothing else (no markdown fences, no prose):
{
  "summary": "one sentence on how you prioritized",
  "recommendations": [
    {
      "title": "short fix title",
      "priority": "high|medium|low",
      "action": "the concrete fix, one or two sentences",
      "method": "geo method identifier",
      "expected_delta": 4
    }
  ]
}
At most 8 recommendations, ordered by expected GEO impact (highest first).
expected_delta is an integer 0-10: the score points the fix should recover.
Merge issues that share one root cause into a single recommendation. Base
everything on the provided issues; never invent findings.]]

	local PRIORITIES = { high = true, medium = true, low = true }

	-- Asks the runner to prioritize the issue list. Fails hard on a
	-- malformed reply.
	function agent.build(issues, ctx, args)
		local mem = base.memory(ctx, agent.slug, args)
		table.sort(issues, function(a, b)
			return (a.impact or 0) > (b.impact or 0)
		end)

		local verdict = base.invoke(ctx, agent.runner, CONTRACT, {
			role = agent.name,
			issues = issues,
			previous_verdict = mem:get("last_verdict"),
		})

		local recommendations = {}
		for i, item in ipairs(verdict.recommendations or {}) do
			if i <= 8 and type(item) == "table" and item.title then
				recommendations[#recommendations + 1] = {
					title = tostring(item.title),
					agent = agent.name,
					priority = PRIORITIES[item.priority] and item.priority or "medium",
					action = tostring(item.action or ""),
					method = tostring(item.method or "agent_judgment"),
					expected_delta = util.clamp(util.round(tonumber(item.expected_delta) or 3), 0, 10),
				}
			end
		end
		if #issues > 0 and #recommendations == 0 then
			error(agent.runner .. ": returned no recommendations for " .. tostring(#issues) .. " issues")
		end

		agent.summary = util.trim(verdict.summary)
		mem:set("last_verdict", { summary = agent.summary, recommendations = recommendations })
		return recommendations
	end

	-- Contract for a single-issue, file-editing fix. The runner returns the FULL
	-- replacement content of each file it changes (more reliable than emitting a
	-- patch). It must set `not_fixable` when the issue cannot be resolved by
	-- editing the project's own files.
	local FIX_CONTRACT = [[
You fix ONE detected GEO issue by editing the local project's own files.
You are given the issue and the project's files (each prefixed with a
`<!-- file: /abs/path -->` marker). Respond with a single JSON object and
nothing else (no markdown fences, no prose):
{
  "explanation": "one or two sentences on exactly what you changed and why",
  "not_fixable": false,
  "files": [
    { "path": "/absolute/path/exactly/as/shown/in/a/file/marker",
      "new_content": "the ENTIRE new contents of that file" }
  ]
}
Rules:
- Only edit files shown in the provided project content. Use each file's path
  EXACTLY as it appears in its `<!-- file: ... -->` marker.
- `new_content` is the complete file after your change, not a diff or snippet.
- Make the smallest change that resolves the issue. Touch as few files as
  possible. Never invent files or paths.
- If the issue cannot be fixed by editing these files (e.g. it needs server
  config, HTTPS, external backlinks, or live testing), set
  "not_fixable": true and return an empty "files" array.]]

	-- Asks the runner to produce a concrete file edit for one issue. Returns the
	-- raw verdict { explanation, not_fixable, files = {{path,new_content}} };
	-- the caller validates paths and computes the diff. Project content is the
	-- concatenated blob from sources.collect_project (carries path markers).
	function agent.fix(issue, project_content, ctx, args)
		local verdict = base.invoke(ctx, agent.runner, FIX_CONTRACT, {
			role = agent.name,
			issue = issue,
			project = tostring(project_content or ""),
		})

		local files = {}
		if not verdict.not_fixable then
			for _, item in ipairs(verdict.files or {}) do
				if type(item) == "table" and item.path and item.new_content ~= nil then
					files[#files + 1] = {
						path = tostring(item.path),
						new_content = tostring(item.new_content),
					}
				end
			end
		end

		return {
			explanation = util.trim(verdict.explanation),
			not_fixable = verdict.not_fixable and true or (#files == 0),
			files = files,
		}
	end

	return agent
end
