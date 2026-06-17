-- GEO Juma — agent.d init script.
-- Registration only: wires modules together and declares tools, skills,
-- runners (one per agent, registered in each agent's file), and actions.
-- Modules are imported exactly once here; dependencies are threaded through
-- factories because a deduplicated import returns `true`, not the module.

local config = import("config.lua")

-- Skills first: each agent's runner composes its skill fragment.
agentd.skills.dir("skills")

-- Shared libraries -----------------------------------------------------------
local util = import("lib/util.lua")
local html = import("lib/html.lua")(util)
local store = import("lib/store.lua")(config)
local sources = import("geo/sources.lua")(util, config)
local base = import("geo/agents/base.lua")(util, config)

-- Tools (permission manifests) ------------------------------------------------
agentd.tool({
	name = "geo",
	requires = {
		"ai:openai",
		"net:*",
		"fs.read:*",
		"fs.write:*",
		"memory.read:" .. config.MEMORY_ROOT .. "/**",
		"memory.write:" .. config.MEMORY_ROOT .. "/**",
	},
})

agentd.tool({
	name = "chat",
	requires = {
		"ai:openai",
		"memory.read:" .. config.MEMORY_ROOT .. "/**",
		"memory.write:" .. config.MEMORY_ROOT .. "/**",
	},
})

agentd.tool({
	name = "secrets",
	requires = { "secret:openai_api_key" },
})

-- Agents (each file registers its own runner + skill binding) -----------------
local analyzers = {
	import("geo/agents/data_collection.lua")(util, config), -- Agent 1
	import("geo/agents/technical_seo.lua")(util, config), -- Agent 2
	import("geo/agents/geo_visibility.lua")(util, config), -- Agent 3
	import("geo/agents/eeat_credibility.lua")(util, config), -- Agent 4
	import("geo/agents/llm_testing.lua")(util, config), -- Agent 5
}
local recommendation = import("geo/agents/recommendation.lua")(util, config, base) -- Agent 6
local scoring = import("geo/agents/scoring.lua")(util, config, base) -- Agent 7
local reporting = import("geo/agents/reporting.lua")(util, config, base) -- Agent 8

-- Coordinator runner (conversation surface; not part of the 8-agent pipeline).
agentd.runner({
	name = "geo_juma_chat",
	model = config.MODEL,
	skills = { "geo-coordinator" },
})

-- Governor: drives the whole pipeline -----------------------------------------
local governor = import("geo/governor.lua")({
	util = util,
	html = html,
	base = base,
	sources = sources,
	analyzers = analyzers,
	recommendation = recommendation,
	scoring = scoring,
	reporting = reporting,
})

-- Actions ------------------------------------------------------------------------
import("actions/geo.lua")({
	config = config,
	util = util,
	store = store,
	sources = sources,
	governor = governor,
	recommendation = recommendation,
})

import("actions/chat.lua")({
	config = config,
	util = util,
	store = store,
})

import("actions/secrets.lua")({
	util = util,
})
