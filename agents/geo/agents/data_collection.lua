-- Agent 1: Data Collection Agent
-- Owns crawl-side evidence: extracted content presence and AI crawler access.
-- The deterministic helpers here gather facts; judgment happens in the runner.
return function(util, config)
	local agent = {
		id = 1,
		name = "Agent 1: Data Collection Agent",
		slug = "data_collection",
		runner = "geo_juma_data_collection",
		skill = "geo-data-collection",
		summary = "",
		status = "pending",
	}

	agentd.runner({
		name = agent.runner,
		model = config.MODEL,
		skills = { agent.skill },
	})

	-- robots.txt policy facts for the major AI crawlers. Evidence only:
	-- the runner interprets what blocked/mentioned counts mean.
	function agent.robots_allows_ai(robots)
		if not robots or robots == "" then
			return false, "robots.txt was not available during this scan"
		end
		local body = util.lower(robots)
		local bots = { "gptbot", "chatgpt-user", "claudebot", "google-extended", "perplexitybot", "ccbot" }
		local mentioned = 0
		local blocked = 0
		for _, bot in ipairs(bots) do
			if util.contains(body, bot) then
				mentioned = mentioned + 1
				local cursor = 1
				while true do
					local s, e = string.find(body, "user%-agent:%s*" .. bot, cursor)
					if not s then break end
					local chunk = string.sub(body, e + 1, e + 240)
					if string.find(chunk, "disallow:%s*/") then
						blocked = blocked + 1
					end
					cursor = e + 1
				end
			end
		end
		return mentioned > 0 and blocked == 0,
			tostring(mentioned) .. " AI crawler directives found; " .. tostring(blocked) .. " blocking directives"
	end

	-- Crawl-side facts handed to the runner for judgment.
	function agent.evidence(doc)
		return {
			title = doc.title,
			description = doc.description,
			language = doc.lang,
			word_count = doc.words,
			html_bytes = #doc.html,
			internal_links = doc.internal_links,
			external_links = doc.external_links,
			robots_ok = doc.robots_ok,
			robots_evidence = doc.robots_evidence,
			text_excerpt = string.sub(doc.text, 1, 1500),
		}
	end

	return agent
end
