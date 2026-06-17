-- Agent 8: Reporting Agent
-- Writes the executive optimization report through its runner. Fails hard
-- when no provider is configured: no silent deterministic fallback.
return function(util, config, base)
	local agent = {
		id = 8,
		name = "Agent 8: Reporting Agent",
		slug = "reporting",
		runner = "geo_juma_report",
		skill = "geo-reporting",
		summary = "",
		status = "pending",
	}

	agentd.runner({
		name = agent.runner,
		model = config.MODEL,
		skills = { agent.skill },
	})

	-- AI-written report. `summary_of` renders the headline numbers
	-- (store.analysis_summary) for the prompt preamble.
	function agent.write(analysis, summary_of, ctx, args)
		local mem = base.memory(ctx, agent.slug, args)
		local response = ctx.run(agent.runner, {
			prompt = "Create a GEO optimization report from this analysis, following the section structure and metric definitions in your skill.\n\n"
				.. "For every benchmark metric in analysis.benchmark.comparison.metrics, report its before/after/delta and explain what the change means using the definition of that metric. Remember: lower modelled rank is better, and positive ΔRank/NRG means the page moved up. Do not print raw LaTeX or restate a formula without interpreting it. Show before/after only when a baseline session exists.\n\n"
				.. "Headline numbers:\n"
				.. summary_of(analysis)
				.. "\n\nFull analysis JSON:\n"
				.. json.encode(analysis),
		})
		if not response or util.trim(response.text) == "" then
			error(agent.runner .. ": runner returned an empty report")
		end

		agent.summary = "Wrote the executive report (" .. tostring(response.model) .. ")."
		mem:set("last_report", { text = response.text, model = response.model })
		return response.text, response.model
	end

	return agent
end
