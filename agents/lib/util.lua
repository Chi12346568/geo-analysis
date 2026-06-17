-- Generic helpers shared by every module. Self-contained: no imports.
local util = {}

function util.trim(value)
	return string.trim(tostring(value or ""))
end

function util.lower(value)
	return string.lower(tostring(value or ""))
end

function util.clamp(n, min, max)
	if n < min then return min end
	if n > max then return max end
	return n
end

function util.round(n)
	return math.floor(n + 0.5)
end

function util.starts_with(value, prefix)
	return string.sub(value, 1, #prefix) == prefix
end

function util.contains(value, needle)
	return string.find(value, needle, 1, true) ~= nil
end

function util.count_pattern(value, pattern)
	local count = 0
	for _ in string.gmatch(value or "", pattern) do
		count = count + 1
	end
	return count
end

-- Splits a string into a list of lines (no trailing-newline empty element).
local function split_lines(value)
	local lines = {}
	for line in (tostring(value or "") .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	-- gmatch on "...\n" leaves one trailing "" we don't want.
	if #lines > 0 and lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end

-- Normalizes a filesystem path for comparison: forward slashes, no trailing
-- slash. Enough to compare a target against a project root.
function util.normalize_path(value)
	local p = tostring(value or ""):gsub("\\", "/")
	p = p:gsub("^//%?/UNC/", "//")
	p = p:gsub("^//%?/", "")
	if p:match("^%a:/") then
		p = string.lower(string.sub(p, 1, 1)) .. string.sub(p, 2)
	end
	p = p:gsub("/+$", "")
	return p
end

-- True when `path` is the root itself or sits underneath it. Rejects `..`
-- escapes by refusing any path that contains a ".." segment.
function util.path_inside(root, path)
	root = util.normalize_path(root)
	path = util.normalize_path(path)
	if root == "" or path == "" then return false end
	if path:find("%.%.") then return false end
	if path == root then return true end
	return util.starts_with(path, root .. "/")
end

-- Minimal line-based unified diff. Not an LCS — it emits the old block as
-- removals and the new block as additions, which is plenty for the webapp's
-- review panel (whole-file replacements). Returns "" when content is identical.
function util.unified_diff(path, old, new)
	if tostring(old or "") == tostring(new or "") then return "" end
	local a = split_lines(old)
	local b = split_lines(new)

	-- Trim the common prefix/suffix so the diff focuses on what changed.
	local pre = 0
	while pre < #a and pre < #b and a[pre + 1] == b[pre + 1] do
		pre = pre + 1
	end
	local suf = 0
	while suf < (#a - pre) and suf < (#b - pre) and a[#a - suf] == b[#b - suf] do
		suf = suf + 1
	end

	-- Keep at most 3 lines of context on each side of the change.
	local ctx_n = 3
	local ctx_pre = math.min(pre, ctx_n)
	local ctx_suf = math.min(suf, ctx_n)
	local old_start = pre - ctx_pre + 1
	local new_start = pre - ctx_pre + 1
	local old_len = (#a - suf) - (pre - ctx_pre) + ctx_suf
	local new_len = (#b - suf) - (pre - ctx_pre) + ctx_suf

	local out = {
		"--- a/" .. path,
		"+++ b/" .. path,
		string.format("@@ -%d,%d +%d,%d @@", old_start, old_len, new_start, new_len),
	}
	for i = pre - ctx_pre + 1, pre do
		out[#out + 1] = " " .. a[i]
	end
	for i = pre + 1, #a - suf do
		out[#out + 1] = "-" .. a[i]
	end
	for i = pre + 1, #b - suf do
		out[#out + 1] = "+" .. b[i]
	end
	for i = #a - suf + 1, #a - suf + ctx_suf do
		out[#out + 1] = " " .. a[i]
	end
	return table.concat(out, "\n")
end

return util
