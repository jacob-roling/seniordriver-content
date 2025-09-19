-- Keep ONLY the attributes you define below; drop the rest.
-- Works for any element that has attributes (Div, Span, CodeBlock, Image, Link, Header, etc.)

-- ==== CONFIG: edit these ====
-- Attributes allowed on EVERY element (by key name). Example: keep IDs everywhere.
local ALLOW_GLOBAL = {
  -- id = true,
  -- style = true,         -- (uncomment if you want inline styles… usually you don't)
}

-- Extra attributes allowed per Pandoc element type (keys are Pandoc AST names).
-- Examples you might want:
local ALLOW = {
  Image     = {}, -- keep image sizing if present
  Link      = {}, -- nothing extra
  CodeBlock = {}, -- nothing extra (see KEEP_CODE_LANG)
  Code      = {},
}

-- Keep fenced code language (```js) even while stripping other classes.
local KEEP_CODE_LANG = true

-- Keep ALL classes as-is? (Usually false; GFM only needs the language on code blocks.)
local KEEP_CLASSES = false

-- Optionally keep attributes by prefix (e.g., allow all aria-* or data-*)
local ALLOW_PREFIX = {
  -- "aria%-",
  -- "data%-",
}
-- ==== END CONFIG ====

local function attr_allowed_key(k, tname)
  if ALLOW_GLOBAL[k] then return true end
  local per = ALLOW[tname]
  if per and per[k] then return true end
  for _, pat in ipairs(ALLOW_PREFIX) do
    if k:match("^" .. pat) then return true end
  end
  return false
end

local function clean_attr(el)
  if not el.attr then return el end
  local tname = el.t
  local orig  = el.attr

  -- identifier (id)
  local id    = ""
  if ALLOW_GLOBAL.id or (ALLOW[tname] and ALLOW[tname].id) then
    id = orig.identifier or ""
  end

  -- classes
  local classes = {}
  if KEEP_CLASSES then
    classes = orig.classes
  elseif KEEP_CODE_LANG and (tname == "CodeBlock" or tname == "Code") then
    -- Keep only the language as a single class/info string
    local lang = orig.classes[1]
    if lang and lang:match("^language%-") then
      lang = lang:sub(10) -- "language-js" -> "js"
    end
    if lang and #lang > 0 then classes = { lang } end
  end

  -- key/value attributes
  local kept = {}
  for k, v in pairs(orig.attributes) do
    if attr_allowed_key(k, tname) then kept[k] = v end
  end

  el.attr = pandoc.Attr(id, classes, kept)
  return el
end

return {
  { Block = clean_attr, Inline = clean_attr }
}
