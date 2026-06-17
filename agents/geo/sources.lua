-- Input acquisition: live URL fetches, robots.txt retrieval, and local
-- project file collection. The only module besides actions that touches ctx.
return function(util, config)
	local sources = {}

	function sources.robots_url_from(url)
		local scheme, host = tostring(url or ""):match("^(https?://)([^/%?#]+)")
		if not scheme then return nil end
		return scheme .. host .. "/robots.txt"
	end

	function sources.origin_from(url)
		local scheme, host = tostring(url or ""):match("^(https?://)([^/%?#]+)")
		if not scheme then return "" end
		return scheme .. host
	end

	function sources.fetch_url(url, ctx)
		local lowered = util.lower(url)
		if not util.starts_with(lowered, "http://") and not util.starts_with(lowered, "https://") then
			error("geo.analyze: URL must start with http:// or https://")
		end

		local response = ctx.http.get(url, {
			timeout_ms = 25000,
			headers = {
				["user-agent"] = config.USER_AGENT,
				["accept"] = "text/html,application/xhtml+xml,text/plain;q=0.8,*/*;q=0.5",
			},
		})

		if response.status < 200 or response.status >= 400 then
			error("geo.analyze: URL returned HTTP " .. tostring(response.status))
		end

		return response.body or "", response.status, response.headers or {}
	end

	function sources.fetch_robots(url, ctx)
		local robots_url = sources.robots_url_from(url)
		if not robots_url then return nil end
		local ok, response = pcall(ctx.http.get, robots_url, {
			timeout_ms = 12000,
			headers = { ["user-agent"] = config.USER_AGENT },
		})
		if not ok or not response or response.status < 200 or response.status >= 400 then
			return nil
		end
		return response.body or ""
	end

	local function is_ignored_dir(name)
		local n = util.lower(name)
		return n == ".git" or n == "node_modules" or n == "dist" or n == "build" or
			n == ".next" or n == "target" or n == "vendor" or n == ".venv" or n == "__pycache__"
	end

	local function readable_source_file(name)
		local n = util.lower(name)
		local exts = {
			".html", ".htm", ".md", ".mdx", ".txt", ".js", ".jsx", ".ts", ".tsx",
			".vue", ".svelte", ".astro", ".php", ".py", ".rb", ".go", ".rs",
			".java", ".cs", ".json", ".toml", ".yml", ".yaml",
		}
		for _, ext in ipairs(exts) do
			if string.endswith(n, ext) then return true end
		end
		return n == "robots.txt" or n == "llms.txt"
	end

	-- Walks a local project tree and concatenates readable source files into
	-- one analyzable body. Returns { html, robots, file_count }.
	function sources.collect_project(root, max_files, ctx)
		local queue = { { path = root, depth = 0 } }
		local files = {}
		local collected = {}
		local robots = ""

		while #queue > 0 and #files < max_files do
			local item = table.remove(queue, 1)
			local ok, entries = pcall(ctx.fs.list_dir, item.path)
			if ok and entries then
				for _, entry in ipairs(entries) do
					if entry.kind == "dir" and item.depth < 5 and not is_ignored_dir(entry.name) then
						queue[#queue + 1] = { path = entry.path, depth = item.depth + 1 }
					elseif entry.kind == "file" and readable_source_file(entry.name) then
						files[#files + 1] = entry.path
						local read_ok, body = pcall(ctx.fs.read, entry.path)
						if read_ok and body then
							if util.lower(entry.name) == "robots.txt" then robots = body end
							if #body > 50000 then body = string.sub(body, 1, 50000) end
							collected[#collected + 1] = "\n\n<!-- file: " .. entry.path .. " -->\n" .. body
						end
					end
					if #files >= max_files then break end
				end
			end
		end

		return {
			html = table.concat(collected, "\n"),
			robots = robots,
			file_count = #files,
			collected_count = #collected,
		}
	end

	return sources
end
