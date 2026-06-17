-- HTML parsing and fact extraction. Pure functions over raw markup;
-- no I/O, no ctx. Returned as a factory so init.lua wires dependencies once.
return function(util)
	local html = {}

	function html.decode_entities(text)
		return tostring(text or "")
			:gsub("&nbsp;", " ")
			:gsub("&amp;", "&")
			:gsub("&lt;", "<")
			:gsub("&gt;", ">")
			:gsub("&quot;", "\"")
			:gsub("&#39;", "'")
	end

	function html.strip_tags(markup)
		local body = tostring(markup or "")
		body = body:gsub("<script[%s%S]-</script>", " ")
		body = body:gsub("<style[%s%S]-</style>", " ")
		body = body:gsub("<noscript[%s%S]-</noscript>", " ")
		body = body:gsub("<svg[%s%S]-</svg>", " ")
		body = body:gsub("<[^>]+>", " ")
		body = html.decode_entities(body)
		body = util.trim(body:gsub("%s+", " "))
		return body
	end

	function html.attr(tag, name)
		local pattern1 = name .. '%s*=%s*"([^"]*)"'
		local pattern2 = name .. "%s*=%s*'([^']*)'"
		local pattern3 = name .. "%s*=%s*([^%s>]+)"
		return tag:match(pattern1) or tag:match(pattern2) or tag:match(pattern3) or ""
	end

	function html.extract_title(markup)
		local value = tostring(markup or ""):match("<title[^>]*>([%s%S]-)</title>")
		return html.decode_entities(util.trim(value))
	end

	function html.extract_meta(markup, name)
		local target = util.lower(name)
		for tag in tostring(markup or ""):gmatch("<meta[^>]->") do
			local meta_name = util.lower(html.attr(tag, "name"))
			local prop = util.lower(html.attr(tag, "property"))
			if meta_name == target or prop == target then
				return html.decode_entities(util.trim(html.attr(tag, "content")))
			end
		end
		return ""
	end

	function html.extract_canonical(markup)
		for tag in tostring(markup or ""):gmatch("<link[^>]->") do
			local rel = util.lower(html.attr(tag, "rel"))
			if util.contains(rel, "canonical") then
				return util.trim(html.attr(tag, "href"))
			end
		end
		return ""
	end

	function html.extract_lang(markup)
		local tag = tostring(markup or ""):match("<html[^>]->") or ""
		return util.trim(html.attr(tag, "lang"))
	end

	function html.word_count(text)
		local count = 0
		for token in tostring(text or ""):gmatch("%S+") do
			if #token > 1 then count = count + 1 end
		end
		return count
	end

	function html.collect_headings(markup)
		local headings = {}
		for level, content in tostring(markup or ""):gmatch("<h([1-6])[^>]*>([%s%S]-)</h[1-6]>") do
			headings[#headings + 1] = {
				level = tonumber(level),
				text = html.strip_tags(content),
			}
		end
		return headings
	end

	function html.collect_images(markup)
		local total = 0
		local missing_alt = 0
		for tag in tostring(markup or ""):gmatch("<img[^>]->") do
			total = total + 1
			if util.trim(html.attr(tag, "alt")) == "" then
				missing_alt = missing_alt + 1
			end
		end
		return total, missing_alt
	end

	function html.collect_links(markup)
		local internal = 0
		local external = 0
		for tag in tostring(markup or ""):gmatch("<a[^>]->") do
			local href = util.lower(html.attr(tag, "href"))
			if util.starts_with(href, "http://") or util.starts_with(href, "https://") then
				external = external + 1
			elseif href ~= "" and not util.starts_with(href, "#") then
				internal = internal + 1
			end
		end
		return internal, external
	end

	function html.has_faq_schema(markup)
		local body = util.lower(markup)
		return util.contains(body, "faqpage")
			or util.contains(body, "question") and util.contains(body, "acceptedanswer")
	end

	function html.detect_structured_answers(markup, text)
		local body = util.lower(markup)
		local score = 0
		if util.contains(body, "<ul") or util.contains(body, "<ol") then score = score + 1 end
		if util.contains(body, "<table") then score = score + 1 end
		if util.contains(body, "<blockquote") then score = score + 1 end
		if util.count_pattern(text, "%?") >= 2 then score = score + 1 end
		return score
	end

	-- Builds the fact table every analysis agent reads. One extraction pass;
	-- agents stay pure and never touch raw markup themselves.
	function html.build_document(source)
		local markup = source.html or ""
		local text = html.strip_tags(markup)
		local lower_html = util.lower(markup)
		local headings = html.collect_headings(markup)
		local h1_count = 0
		for _, h in ipairs(headings) do
			if h.level == 1 then h1_count = h1_count + 1 end
		end
		local image_total, missing_alt = html.collect_images(markup)
		local internal_links, external_links = html.collect_links(markup)

		return {
			source = source,
			html = markup,
			lower_html = lower_html,
			text = text,
			title = html.extract_title(markup),
			description = html.extract_meta(markup, "description"),
			canonical = html.extract_canonical(markup),
			lang = html.extract_lang(markup),
			headings = headings,
			h1_count = h1_count,
			schema_count = util.count_pattern(lower_html, "application/ld%+json")
				+ util.count_pattern(lower_html, "schema.org"),
			faq_schema = html.has_faq_schema(markup),
			image_total = image_total,
			missing_alt = missing_alt,
			internal_links = internal_links,
			external_links = external_links,
			words = html.word_count(text),
			structured_answer_score = html.detect_structured_answers(markup, text),
			has_author = util.contains(lower_html, "author")
				or util.contains(lower_html, "person")
				or util.contains(lower_html, "profile"),
			has_llms = util.contains(lower_html, "llms.txt") or util.contains(lower_html, "llm"),
			has_viewport = util.contains(lower_html, "name=\"viewport\"")
				or util.contains(lower_html, "name='viewport'"),
			has_https = util.starts_with(util.lower(source.url or ""), "https://"),
			robots_ok = false,
			robots_evidence = "No robots.txt input was provided",
		}
	end

	return html
end
