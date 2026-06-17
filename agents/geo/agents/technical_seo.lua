-- Agent 2: Technical SEO Agent
-- Classic on-page hygiene: meta, headings, canonical, mobile, HTTPS,
-- image alt coverage, and payload size. Facts here; judgment in the runner.
return function(util, config)
	local agent = {
		id = 2,
		name = "Agent 2: Technical SEO Agent",
		slug = "technical_seo",
		runner = "geo_juma_technical_seo",
		skill = "geo-technical-seo",
		summary = "",
		status = "pending",
	}

	agentd.runner({
		name = agent.runner,
		model = config.MODEL,
		skills = { agent.skill },
	})

	-- On-page hygiene facts handed to the runner for judgment.
	function agent.evidence(doc)
		local headings = {}
		for i, h in ipairs(doc.headings) do
			if i <= 30 then
				headings[#headings + 1] = { level = h.level, text = h.text }
			end
		end
		return {
			source_type = doc.source.source_type,
			title = doc.title,
			meta_description = doc.description,
			canonical = doc.canonical,
			h1_count = doc.h1_count,
			heading_count = #doc.headings,
			headings = headings,
			image_total = doc.image_total,
			missing_alt = doc.missing_alt,
			has_https = doc.has_https,
			has_viewport = doc.has_viewport,
			html_bytes = #doc.html,
		}
	end

	return agent
end
