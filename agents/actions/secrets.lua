-- secrets.* actions: OpenAI key management via the OS keyring.
return function(deps)
	local util = deps.util

	agentd.action({
		name = "secrets.set_openai_key",
		requires = { "secret:openai_api_key" },
		handler = function(args, ctx)
			local raw = args and (args.value or args.api_key)
			local value = type(raw) == "string" and util.trim(raw) or ""
			if value == "" then error("secrets.set_openai_key: `value` is required") end
			ctx.secret.set("openai_api_key", value)
			return { ok = true, key = "openai_api_key" }
		end,
	})

	agentd.action({
		name = "secrets.openai_status",
		requires = { "secret:openai_api_key" },
		handler = function(_, ctx)
			return { configured = ctx.secret.exists("openai_api_key"), key = "openai_api_key" }
		end,
	})
end
