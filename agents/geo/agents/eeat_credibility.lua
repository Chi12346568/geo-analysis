-- Agent 4: E-E-A-T Credibility Agent
-- Authority and trust signals: author/ownership exposure and outbound
-- references to authoritative sources. Facts here; judgment in the runner.
return function(util, config)
	local agent = {
		id = 4,
		name = "Agent 4: E-E-A-T Credibility Agent",
		slug = "eeat_credibility",
		runner = "geo_juma_eeat",
		skill = "geo-eeat",
		summary = "",
		status = "pending",
	}

	agentd.runner({
		name = agent.runner,
		model = config.MODEL,
		skills = { agent.skill },
	})

	-- Authority and trust facts handed to the runner for judgment.
	function agent.evidence(doc)
		return {
			has_author_signal = doc.has_author,
			external_links = doc.external_links,
			internal_links = doc.internal_links,
			has_https = doc.has_https,
			schema_markers = doc.schema_count,
			title = doc.title,
			text_excerpt = string.sub(doc.text, 1, 2000),
		}
	end

	return agent
end
