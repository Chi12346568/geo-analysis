-- Shared agent runtime: runner invocation with a strict JSON contract,
-- verdict validation, and per-agent durable memory. Every agent thinks
-- through its own runner; this module only enforces the wire format.
return function(util, config)
	local base = {}

	local DIMENSIONS = {
		technical = true,
		geo_visibility = true,
		llm_visibility = true,
		trust = true,
		extractability = true,
		citability = true,
		performance = true,
	}
	local SEVERITIES = { high = true, medium = true, low = true }

	-- Durable, namespaced memory owned by a single agent. Keyed on the same
	-- context id / session the chat store uses, so an agent can compare a new
	-- scan with its own previous verdict for the same site.
	function base.memory(ctx, slug, args)
		local explicit = args and (args.context_id or args.project_id)
		local session = explicit or ctx.caller.session or "local"
		return ctx.memory.create(config.MEMORY_ROOT .. "/agents/" .. slug .. "/" .. tostring(session))
	end

	-- Invokes a runner and decodes its JSON reply. Delegates to the runtime's
	-- `ctx.structured` guarantee: it strips markdown fences, JSON-decodes,
	-- validates, and reprompts the model with the rejection reason before
	-- giving up. A stray token in one agent's output no longer aborts the
	-- whole pipeline — the runtime retries that single call. Still fails hard
	-- if every attempt is malformed (no degrading to canned output).
	function base.invoke(ctx, runner, system, payload)
		return ctx.structured(runner, {
			prompt = json.encode(payload),
			system = system,
			retries = 2,
			validate = function(t)
				if type(t) ~= "table" then return false, "reply was not a JSON object" end
				return true
			end,
		})
	end

	-- Validates and normalizes an analyzer verdict in place: unknown score
	-- dimensions are dropped, severities and impacts are clamped to the
	-- model the scorer understands.
	function base.sanitize_verdict(agent_name, verdict)
		local issues = {}
		for _, item in ipairs(verdict.issues or {}) do
			if type(item) == "table" and item.title then
				issues[#issues + 1] = {
					id = tostring(item.id or item.title),
					title = tostring(item.title),
					category = tostring(item.category or "General"),
					severity = SEVERITIES[item.severity] and item.severity or "medium",
					agent = agent_name,
					evidence = tostring(item.evidence or ""),
					recommendation = tostring(item.recommendation or ""),
					impact = util.clamp(util.round(tonumber(item.impact) or 5), 1, 10),
					method = tostring(item.method or "agent_judgment"),
				}
			end
		end
		local bonuses = {}
		for _, b in ipairs(verdict.bonuses or {}) do
			if type(b) == "table" and DIMENSIONS[b.key] then
				bonuses[#bonuses + 1] = {
					key = b.key,
					delta = util.clamp(util.round(tonumber(b.delta) or 0), -15, 15),
				}
			end
		end
		verdict.issues = issues
		verdict.bonuses = bonuses
		verdict.summary = util.trim(verdict.summary)
		return verdict
	end

	-- Output contract appended to every analyzer invocation.
	base.VERDICT_CONTRACT = [[
Respond with a single JSON object and nothing else (no markdown fences, no prose):
{
  "summary": "one sentence stating what you concluded from the evidence",
  "issues": [
    {
      "id": "snake_case_slug",
      "title": "short issue title",
      "category": "issue category",
      "severity": "high|medium|low",
      "evidence": "what in the provided evidence shows this",
      "recommendation": "the concrete fix",
      "impact": 1,
      "method": "geo method identifier",
      "_note": "impact is an integer 1-10"
    }
  ],
  "bonuses": [
    { "key": "technical|geo_visibility|llm_visibility|trust|extractability|citability|performance", "delta": 5 }
  ]
}
Issues are problems you actually observe in the evidence. Bonuses (delta -15..15)
reward signals that are present and healthy. Base every claim strictly on the
provided evidence; never invent crawl findings. `previous_verdict`, when present,
is your own verdict from the last scan of this context — note regressions or
improvements in your summary.]]

	return base
end
