-- Agent 7: Scoring Agent
-- Owns the score model. The mechanical pass (base values + analyzer bonuses)
-- anchors the numbers; the runner reviews issues and evidence and settles the
-- final dimension scores. Weighting and projection stay deterministic math.
return function(util, config, base)
	local agent = {
		id = 7,
		name = "Agent 7: Scoring Agent",
		slug = "scoring",
		runner = "geo_juma_scoring",
		skill = "geo-scoring",
		summary = "",
		status = "pending",
	}

	agentd.runner({
		name = agent.runner,
		model = config.MODEL,
		skills = { agent.skill },
	})

	local WEIGHTS = {
		technical = 0.17,
		geo_visibility = 0.18,
		llm_visibility = 0.17,
		trust = 0.16,
		extractability = 0.12,
		citability = 0.14,
		performance = 0.06,
	}
	local RANK_LIST_LENGTH = 100
	local PROMOTION_ALPHA = 0.20

	local FORMULAS = {
		readiness_scoring = {
			label = "Readiness Scoring",
			formula = "R = (Σ_{i∈P} w_i m_i) / (Σ_{i∈P} w_i)",
			reference = "MAIORANO, Alexandre Cristovão. LLM Readiness Harness: Evaluation, Observability, and CI Gates for LLM/RAG Applications. arXiv:2603.27355, 2026.",
		},
		nrg = {
			label = "Normalized Rank Gain (NRG)",
			formula = "NRG = (r_before - r_after) / (L - 1)",
			reference = "NIMASE, Ojas, CHEN, Zhe, QI, Gengpei, et al. GEO-Bench: Benchmarking Ranking Manipulation in Generative Engine Optimization. arXiv:2605.29107, 2026.",
		},
		promote_alpha = {
			label = "Promotion Success@α (Promote@α)",
			formula = "Promote@α = I[r_before > ⌈αL⌉ ∧ r_after ≤ ⌈αL⌉]",
			reference = "NIMASE, Ojas, CHEN, Zhe, QI, Gengpei, et al. GEO-Bench: Benchmarking Ranking Manipulation in Generative Engine Optimization. arXiv:2605.29107, 2026.",
		},
		citation_rate = {
			label = "Citation Rate",
			formula = "Citation Rate = cited_responses / total_tested_responses",
			reference = "SAGEO Arena: A Realistic Environment for Evaluating Search-Augmented Generative Engine Optimization. Sunghwan Kim.",
		},
		delta_rank = {
			label = "ΔRank",
			formula = "ΔRank = (1 / |Q|) Σ_{q∈Q}(rank_base(d_q^tgt) - rank_SAGEO(d_q^tgt))",
			reference = "SAGEO Arena: A Realistic Environment for Evaluating Search-Augmented Generative Engine Optimization. Sunghwan Kim.",
		},
	}

	local CONTRACT = [[
Respond with a single JSON object and nothing else (no markdown fences, no prose):
{
  "summary": "one sentence on the score picture",
  "scores": {
    "technical": 0, "geo_visibility": 0, "llm_visibility": 0, "trust": 0,
    "extractability": 0, "citability": 0, "performance": 0
  }
}
Each score is an integer 0-100. `mechanical_scores` is the rule-based baseline;
adjust each dimension where the issues and metrics justify it, and keep it
where they do not. Stay within ±20 of the baseline unless the evidence is
overwhelming. Never invent findings.]]

	-- Deterministic mechanical baseline derived from the page's own facts — no
	-- invented seed numbers. Each dimension is a weighted sum of normalized
	-- evidence signals (each 0..1, weights per dimension sum to 100). The
	-- analyzer bonuses and the scoring runner then adjust this grounded anchor.
	local function ramp(value, full)
		if full <= 0 then return 1 end
		return util.clamp((tonumber(value) or 0) / full, 0, 1)
	end
	-- 1 when value is at or below `good`, 0 at or above `bad` (smaller is better).
	local function inverse_ramp(value, good, bad)
		value = tonumber(value) or 0
		if value <= good then return 1 end
		if value >= bad then return 0 end
		return (bad - value) / (bad - good)
	end
	local function flag(value)
		return value and 1 or 0
	end

	function agent.baseline(doc)
		doc = doc or {}
		local source = doc.source or {}
		local is_url = source.source_type == "url"

		local words = doc.words or 0
		local html_bytes = #(doc.html or "")
		local images = doc.image_total or 0
		local missing_alt = doc.missing_alt or 0
		local alt_ok = images > 0 and (images - missing_alt) / images or 1
		local headings = #(doc.headings or {})
		local h1 = doc.h1_count or 0
		local schema = math.min(doc.schema_count or 0, 3) / 3
		local faq = flag(doc.faq_schema)
		local struct = (doc.structured_answer_score or 0) / 4
		local external = doc.external_links or 0

		-- URL-only signals are unknown for pasted/uploaded/project inputs; give
		-- neutral partial credit there instead of a false penalty.
		local https = is_url and flag(doc.has_https) or 0.6
		local robots = doc.robots_ok and 1 or (is_url and 0 or 0.5)
		local viewport = flag(doc.has_viewport)
		local canonical = flag(doc.canonical and doc.canonical ~= "")
		local lang = flag(doc.lang and doc.lang ~= "")
		local author = flag(doc.has_author)
		local llms = flag(doc.has_llms)
		local description = flag(doc.description and doc.description ~= "")
		local h1_ok = h1 == 1 and 1 or (h1 == 0 and 0.3 or 0.5)
		local payload = inverse_ramp(html_bytes, 500000, 3000000)
		local image_load = inverse_ramp(images, 60, 300)

		local function dim(parts)
			local total = 0
			for _, part in ipairs(parts) do
				total = total + part[1] * part[2]
			end
			return util.clamp(util.round(total), 0, 100)
		end

		return {
			technical = dim({
				{ https, 18 }, { viewport, 16 }, { canonical, 14 }, { h1_ok, 16 },
				{ lang, 10 }, { ramp(headings, 6), 14 }, { payload, 12 },
			}),
			geo_visibility = dim({
				{ schema, 26 }, { faq, 22 }, { struct, 22 },
				{ ramp(words, 800), 18 }, { ramp(headings, 8), 12 },
			}),
			llm_visibility = dim({
				{ llms, 28 }, { robots, 22 }, { flag(schema > 0), 18 },
				{ faq, 16 }, { struct, 16 },
			}),
			trust = dim({
				{ author, 26 }, { ramp(external, 8), 22 }, { https, 18 },
				{ canonical, 12 }, { description, 10 }, { ramp(words, 800), 12 },
			}),
			extractability = dim({
				{ struct, 24 }, { ramp(headings, 6), 22 }, { alt_ok, 18 },
				{ ramp(words, 600), 18 }, { payload, 18 },
			}),
			citability = dim({
				{ faq, 26 }, { schema, 22 }, { struct, 22 },
				{ ramp(external, 6), 16 }, { description, 14 },
			}),
			performance = dim({
				{ payload, 45 }, { image_load, 20 }, { viewport, 20 }, { alt_ok, 15 },
			}),
		}
	end

	-- Asks the runner to settle final dimension scores from the mechanical
	-- baseline, issues, and metrics. Missing dimensions fall back to the
	-- baseline; values are clamped to 0-100.
	function agent.assess(mechanical, issues, metrics, ctx, args)
		local mem = base.memory(ctx, agent.slug, args)
		local verdict = base.invoke(ctx, agent.runner, CONTRACT, {
			role = agent.name,
			mechanical_scores = mechanical,
			issues = issues,
			metrics = metrics,
			previous_verdict = mem:get("last_verdict"),
		})

		local scores = {}
		local proposed = type(verdict.scores) == "table" and verdict.scores or {}
		for key in pairs(WEIGHTS) do
			local value = tonumber(proposed[key])
			scores[key] = util.clamp(util.round(value or mechanical[key] or 0), 0, 100)
		end

		agent.summary = util.trim(verdict.summary)
		mem:set("last_verdict", { summary = agent.summary, scores = scores })
		return scores
	end

	function agent.overall(scores)
		local total = 0
		for key, weight in pairs(WEIGHTS) do
			total = total + (scores[key] or 0) * weight
		end
		return util.round(total)
	end

	function agent.formulas()
		return FORMULAS
	end

	function agent.readiness(scores)
		local total = 0
		local weights = 0
		for key, weight in pairs(WEIGHTS) do
			total = total + (tonumber(scores and scores[key]) or 0) * weight
			weights = weights + weight
		end
		if weights == 0 then return 0 end
		return util.round(total / weights)
	end

	function agent.citation_rate(analysis)
		local metrics = analysis and analysis.metrics or {}
		local total = tonumber(metrics.citation_total or metrics.llm_test_total)
		local cited = tonumber(metrics.citation_cited or metrics.llm_test_cited)
		if total and total > 0 and cited then
			return util.clamp(cited / total, 0, 1), "live_prompt_tests"
		end

		local scores = analysis and analysis.scores or {}
		local proxy = ((tonumber(scores.citability) or 0) * 0.5
			+ (tonumber(scores.llm_visibility) or 0) * 0.3
			+ (tonumber(scores.geo_visibility) or 0) * 0.2) / 100
		return util.clamp(proxy, 0, 1), "readiness_proxy"
	end

	function agent.modelled_rank(readiness)
		local score = util.clamp(tonumber(readiness) or 0, 0, 100)
		return util.clamp(util.round(RANK_LIST_LENGTH - (score / 100) * (RANK_LIST_LENGTH - 1)), 1, RANK_LIST_LENGTH)
	end

	local function round3(value)
		return math.floor((tonumber(value) or 0) * 1000 + 0.5) / 1000
	end

	-- `before`/`after` are the raw operands shown in the table; pass `nil` for a
	-- one-sided gain metric (NRG, Promote@α) so the UI renders "--" instead of a
	-- meaningless zero baseline. `delta_override` lets rank metrics keep the
	-- paper's sign convention (improvement positive) instead of `after - before`.
	local function metric(id, before, after, unit, source, delta_override)
		local formula = FORMULAS[id]
		local delta = delta_override
		if delta == nil and type(before) == "number" and type(after) == "number" then
			delta = round3(after - before)
		end
		return {
			id = id,
			label = formula.label,
			formula = formula.formula,
			reference = formula.reference,
			before = before,
			after = after,
			delta = delta,
			unit = unit or "score",
			source = source or "derived",
		}
	end

	function agent.session_comparison(current, baseline)
		local formulas = agent.formulas()
		local current_readiness = agent.readiness(current and current.scores)
		local current_rank = agent.modelled_rank(current_readiness)
		local current_citation, current_citation_source = agent.citation_rate(current)

		if not baseline then
			return {
				baseline_available = false,
				current_session_id = current and current.session_id or nil,
				site_key = current and current.input and current.input.site_key or "",
				formulas = formulas,
				rank_list_length = RANK_LIST_LENGTH,
				promotion_alpha = PROMOTION_ALPHA,
				promotion_cutoff = math.ceil(PROMOTION_ALPHA * RANK_LIST_LENGTH),
				metrics = {
					metric("readiness_scoring", nil, current_readiness, "score", "current_scan"),
					metric("citation_rate", nil, round3(current_citation), "rate", current_citation_source),
				},
				note = "No previous saved scan exists for this same website.",
			}
		end

		local baseline_readiness = agent.readiness(baseline.scores)
		local baseline_rank = agent.modelled_rank(baseline_readiness)
		local baseline_citation, baseline_citation_source = agent.citation_rate(baseline)
		local nrg = (baseline_rank - current_rank) / (RANK_LIST_LENGTH - 1)
		local promotion_cutoff = math.ceil(PROMOTION_ALPHA * RANK_LIST_LENGTH)
		local promote = baseline_rank > promotion_cutoff and current_rank <= promotion_cutoff and 1 or 0
		local delta_rank = baseline_rank - current_rank

		return {
			baseline_available = true,
			baseline_session_id = baseline.session_id,
			baseline_created_at = baseline.created_at,
			current_session_id = current.session_id,
			current_created_at = current.created_at,
			site_key = current.input and current.input.site_key or "",
			formulas = formulas,
			rank_list_length = RANK_LIST_LENGTH,
			promotion_alpha = PROMOTION_ALPHA,
			promotion_cutoff = promotion_cutoff,
			metrics = {
				metric("readiness_scoring", baseline_readiness, current_readiness, "score", "weighted_dimensions"),
				-- ΔRank shows the real modelled positions (lower = better); the delta
				-- keeps the paper's sign (rank_before - rank_after, positive = moved up).
				metric("delta_rank", baseline_rank, current_rank, "rank_positions", "modelled_rank_from_readiness", delta_rank),
				-- NRG and Promote@α are one-sided gains: no prior value to compare to.
				metric("nrg", nil, round3(nrg), "rate", "modelled_rank_from_readiness"),
				metric("promote_alpha", nil, promote, "indicator", "modelled_rank_from_readiness"),
				metric("citation_rate", round3(baseline_citation), round3(current_citation), "rate", current_citation_source .. "_vs_" .. baseline_citation_source),
			},
			ranks = {
				before = baseline_rank,
				after = current_rank,
				delta = baseline_rank - current_rank,
				source = "modelled_rank_from_readiness",
			},
		}
	end

	-- Projected score assuming ~55% of the issue impact is recovered by fixes.
	function agent.projected(overall, issues)
		local potential = 0
		for _, item in ipairs(issues) do
			potential = potential + (item.impact or 0)
		end
		return util.clamp(overall + util.round(potential * 0.55), 0, 96)
	end

	function agent.rounded(scores)
		local out = {}
		for key in pairs(WEIGHTS) do
			out[key] = util.round(scores[key] or 0)
		end
		return out
	end

	return agent
end
