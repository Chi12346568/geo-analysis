-- Agent 3: GEO/LLM Visibility Agent
-- Generative-engine readiness: schema markup, FAQ structure, content depth,
-- and quotable answer formats. Facts here; judgment in the runner.
return function(util, config)
	local agent = {
		id = 3,
		name = "Agent 3: GEO/LLM Visibility Agent",
		slug = "geo_visibility",
		runner = "geo_juma_visibility",
		skill = "geo-visibility",
		summary = "",
		status = "pending",
	}

	agentd.runner({
		name = agent.runner,
		model = config.MODEL,
		skills = { agent.skill },
	})

	-- Generative-engine readiness facts handed to the runner for judgment.
	function agent.evidence(doc)
		return {
			schema_markers = doc.schema_count,
			faq_schema = doc.faq_schema,
			word_count = doc.words,
			structured_answer_score = doc.structured_answer_score,
			heading_count = #doc.headings,
			internal_links = doc.internal_links,
			text_excerpt = string.sub(doc.text, 1, 2000),
		}
	end

	return agent
end
