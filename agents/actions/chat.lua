-- chat.* actions: the coordinator conversation surface.
return function(deps)
	local config = deps.config
	local util = deps.util
	local store = deps.store

	local MEM = config.MEMORY_ROOT

	agentd.action({
		name = "chat.send",
		requires = {
			"ai:openai",
			"memory.read:" .. MEM .. "/**",
			"memory.write:" .. MEM .. "/**",
		},
		handler = function(args, ctx)
			local raw = args and args.message
			local message = type(raw) == "string" and util.trim(raw) or ""
			if message == "" then error("chat.send: `message` is required") end

			local mem = store.memory_for(ctx, args)
			local history = {}
			if not (args and args.reset == true) then
				history = mem:get("history", {})
			end
			local analysis = mem:get("last_analysis")

			store.append_turn(history, "user", message)
			local system = "Current analysis context:\n" .. store.analysis_summary(analysis)
			local response = ctx.run("geo_juma_chat", {
				messages = history,
				system = system,
			})

			store.append_turn(history, "assistant", response.text)
			mem:set("history", history)
			return {
				reply = response.text,
				provider = response.provider,
				model = response.model,
				stop_reason = response.stop_reason,
				history = history,
				session = ctx.caller.session,
			}
		end,
	})

	agentd.action({
		name = "chat.history",
		requires = { "memory.read:" .. MEM .. "/**" },
		handler = function(args, ctx)
			return {
				history = store.memory_for(ctx, args):get("history", {}),
				session = ctx.caller.session,
			}
		end,
	})

	agentd.action({
		name = "chat.clear",
		requires = { "memory.write:" .. MEM .. "/**" },
		handler = function(args, ctx)
			local mem = store.memory_for(ctx, args)
			mem:delete("history")
			mem:delete("last_report")
			return { ok = true, session = ctx.caller.session }
		end,
	})
end
