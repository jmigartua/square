-- text.lua — the dateline under a text's title and the end block after it.
--
-- Runs on every page that has `state:` in its frontmatter (the texts). Reads what tools/build.py computed
-- into _gen/texts.json (touched, sessions) and counts the words itself, leaving notes to self out of the count.
-- Desk-only facts (state, touched, sessions, sample) are wrapped in mother-only so the square never shows them.

local function read_json(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local s = f:read("a"); f:close()
  local ok, data = pcall(pandoc.json.decode, s)
  return ok and data or {}
end

local function slug_of(path)
  local base = path:match("([^/\\]+)%.qmd$") or path
  return base
end

local MONTHS = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" }
local function short(d)
  if not d then return nil end
  local y, m, day = tostring(d):match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not y then return tostring(d) end
  return tonumber(day) .. " " .. MONTHS[tonumber(m)] .. " " .. y
end

local LONG = {
  en = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" },
  es = { "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre" },
  eu = { "urtarrilaren", "otsailaren", "martxoaren", "apirilaren", "maiatzaren", "ekainaren", "uztailaren", "abuztuaren", "irailaren", "urriaren", "azaroaren", "abenduaren" },
}
local function long(d, lang)
  local y, m, day = tostring(d):match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not y then return tostring(d) end
  m, day = tonumber(m), tonumber(day)
  if lang == "es" then return day .. " de " .. LONG.es[m] .. " de " .. y end
  if lang == "eu" then return y .. "ko " .. LONG.eu[m] .. " " .. day .. "a" end
  return day .. " " .. LONG.en[m] .. " " .. y
end

local function words_in(blocks)
  local n = 0
  for _, b in ipairs(blocks) do
    if b.t == "Div" and (b.classes:includes("note") or b.classes:includes("mother-only")
                         or b.identifier:match("^quarto") or b.identifier:match("^title%-block")
                         or b.classes:find_if(function(c) return c:match("^quarto") end)) then
      -- notes to self do not count, nor the title and metadata blocks Quarto appends to the document
    elseif b.t == "Div" or b.t == "BlockQuote" then
      n = n + words_in(b.content)
    elseif b.t == "Para" or b.t == "Plain" or b.t == "Header" then
      local s = pandoc.utils.stringify(b)
      for _ in s:gmatch("%S+") do n = n + 1 end
    elseif b.t == "BulletList" or b.t == "OrderedList" then
      for _, item in ipairs(b.content) do n = n + words_in(item) end
    end
  end
  return n
end

local function str(m) return m and pandoc.utils.stringify(m) or nil end

function Pandoc(doc)
  local meta = doc.meta
  local state = str(meta.state)
  if not state then return doc end

  local lang = str(meta.lang) or "en"
  local slug = str(meta.slug) or slug_of(quarto.doc.input_file or "")
  local facts = read_json(quarto.project.directory .. "/_gen/texts.json")[slug] or {}
  if meta.touched then facts.touched = str(meta.touched) end      -- the square's derivation passes it in
  local words = words_in(doc.blocks)

  -- the dateline
  local parts = {}
  if state == "free" and meta.freed then
    parts[#parts + 1] = "<span>" .. long(str(meta.freed), lang) .. "</span>"
  else
    parts[#parts + 1] = '<span class="state mother-only">' .. state .. "</span>"
  end
  parts[#parts + 1] = "<span>" .. lang .. "</span>"
  parts[#parts + 1] = '<span class="mother-only">' .. words .. " words</span>"
  if facts.touched_human and state ~= "free" then
    parts[#parts + 1] = '<span class="mother-only">touched ' .. facts.touched_human .. "</span>"
  end
  if meta.sample then parts[#parts + 1] = '<span class="sample mother-only">sample</span>' end
  local dateline = pandoc.RawBlock("html", '<div class="dateline">' .. table.concat(parts) .. "</div>")

  local head = { dateline }
  if meta.epigraph then
    head[#head + 1] = pandoc.Div({ pandoc.Para(pandoc.Emph(pandoc.utils.blocks_to_inlines({ pandoc.Para(meta.epigraph) }))) }, pandoc.Attr("", { "epigraph" }))
  end

  -- the end
  local left = {}
  if state == "free" and meta.freed then
    local verb = (lang == "es") and "liberado " or (lang == "eu") and "askatua " or "freed "
    left[#left + 1] = verb .. short(str(meta.freed))
    if facts.touched and facts.touched > str(meta.freed) then
      local t = (lang == "es") and "tocado " or (lang == "eu") and "ukitua " or "touched "
      left[#left + 1] = t .. short(facts.touched)
    end
  else
    if meta.created then left[#left + 1] = "created " .. short(str(meta.created)) end
    if facts.sessions then
      local n = math.floor(facts.sessions)
      left[#left + 1] = string.format("%d %s", n, (n == 1) and "session" or "sessions")
    end
  end
  -- the keywords, after the facts (release 0.8.0): on the desk always; on the square unless square.yml says not
  local kws = {}
  if meta.keywords and not meta.hide_keywords then
    for _, k in ipairs(meta.keywords) do kws[#kws + 1] = pandoc.utils.stringify(k) end
  end
  if #kws > 0 then
    local esc = function(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;")) end
    local kparts = {}
    for _, k in ipairs(kws) do kparts[#kparts + 1] = "<span>" .. esc(k) .. "</span>" end
    left[#left + 1] = '<span class="kws">' .. table.concat(kparts, " · ") .. "</span>"
  end
  local back = (lang == "es") and "volver a la mesa" or (lang == "eu") and "mahaira itzuli" or "back to the desk"
  local square = (lang == "es") and "volver a la plaza" or (lang == "eu") and "plazara itzuli" or "back to the square"
  local write = (lang == "es") and "escribir" or (lang == "eu") and "idatzi" or "write"
  local endblock = pandoc.RawBlock("html",
    '<div class="end"><span>' .. table.concat(left, " · ") .. '</span>'
    .. '<span class="mother-only"><a href="/write/' .. slug .. '" class="act">' .. write .. '</a> · <a href="/">' .. back .. '</a></span>'
    .. '<a href="/" class="sibling-only">' .. square .. '</a></div>')

  local blocks = pandoc.List(head)
  blocks:extend(doc.blocks)
  blocks:insert(endblock)
  doc.blocks = blocks
  return doc
end
