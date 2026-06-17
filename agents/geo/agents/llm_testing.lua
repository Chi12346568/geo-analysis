-- Agent 5: LLM Testing Agent
-- LLM usage signals: llms.txt presence, AI crawler posture, and how
-- citable the content is for generative answers. Facts here; judgment in
-- the runner.
return function(util, config)
	local agent = {
		id = 5,
		name = "Agent 5: LLM Testing Agent",
		slug = "llm_testing",
		runner = "geo_juma_llm_testing",
		skill = "geo-llm-testing",
		summary = "",
		status = "pending",
	}

	agentd.runner({
		name = agent.runner,
		model = config.MODEL,
		skills = { agent.skill },
	})

	-- LLM usage facts handed to the runner for judgment.
	function agent.evidence(doc)
		return {
			has_llms_txt_signal = doc.has_llms,
			robots_ok = doc.robots_ok,
			robots_evidence = doc.robots_evidence,
			faq_schema = doc.faq_schema,
			structured_answer_score = doc.structured_answer_score,
			word_count = doc.words,
			text_excerpt = string.sub(doc.text, 1, 1500),
		}
	end

	return agent
end
