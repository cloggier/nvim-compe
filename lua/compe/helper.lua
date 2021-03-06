local Pattern = require'compe.pattern'
local Character = require'compe.utils.character'

local Private = {}

Private.DEFAULT_INVALID_BYTES = {}
Private.DEFAULT_INVALID_BYTES[string.byte('=', 1)] = true
Private.DEFAULT_INVALID_BYTES[string.byte('(', 1)] = true
Private.DEFAULT_INVALID_BYTES[string.byte('$', 1)] = true
Private.DEFAULT_INVALID_BYTES[string.byte('"', 1)] = true
Private.DEFAULT_INVALID_BYTES[string.byte("'", 1)] = true

--- Create byte map from string
Private.get_byte_map = function(str)
  local byte_map = {}
  for _, byte in ipairs({ string.byte(str, 1, -1) }) do
    byte_map[byte] = true
  end
  return byte_map
end

--- Create word
Private.get_word = function(input, word, byte_map)
  -- Fix for trigger character input. (`$|` -> `namespace\path\to\Class::$cache` = `$cache`)
  -- TODO: More general solution
  local first_char = string.sub(input, 1)
  if Character.is_symbol(string.byte(first_char)) then
    for idx = 1, #word do
      if first_char == string.sub(word, idx, idx) then
        word = string.sub(word, idx, -1)
        break
      end
    end
  end

  local match = -1
  for idx = 1, #word do
    local byte = string.byte(word, idx)
    if (match == -1 and byte_map[byte]) or (not Private.DEFAULT_INVALID_BYTES[byte]) then
      if match == -1 then
        match = idx
      end
    elseif match ~= -1 then
      return string.sub(word, match, idx - 1)
    end
  end
  if match ~= -1 then
    return string.sub(word, match, -1)
  end
  return ''
end

local Helper = {}

--- determine
Helper.determine = function(context, option)
  option = option or {}

  local trigger_character_offset = 0
  if option.trigger_characters and context.before_char ~= ' ' then
    if vim.tbl_contains(option.trigger_characters, context.before_char) then
      trigger_character_offset = context.col
    end
  end

  local keyword_pattern_offset = 0
  if option.keyword_pattern then
    keyword_pattern_offset = Pattern.get_pattern_offset(context.before_line, option.keyword_pattern)
  else
    keyword_pattern_offset = Pattern.get_keyword_offset(context)
  end

  return {
    keyword_pattern_offset = keyword_pattern_offset;
    trigger_character_offset = trigger_character_offset;
  }
end

--- get_keyword_pattern
Helper.get_keyword_pattern = function(filetype)
  return Pattern.get_keyword_pattern(filetype)
end

--- get_default_keyword_pattern
Helper.get_default_pattern = function()
  return Pattern.get_default_pattern()
end

--- convert_lsp
--
-- This method will convert LSP.CompletionItem.
--
-- Should check following servers.
--
-- - php: $| -> namespace\Class::$variable|
-- - clang: foo.| -> foo->prop|
-- - json: "repository|" -> "repository": {|}
-- - html: "</|>" -> "</div|>"
-- - rust: PathBuf::into_|os_string -> PathBuf::into_boxed_path|
-- - viml: let g:compe.| -> let g:compe.autocomplete|
-- - lua: require'compe|' -> require'compe.utils.character|'
--
Helper.convert_lsp = function(args)
  local keyword_pattern_offset = args.keyword_pattern_offset
  local context = args.context
  local request = args.request
  local response = args.response

  local complete_items = {}
  for _, completion_item in pairs(vim.tbl_islist(response or {}) and response or response.items or {}) do
    local word = ''
    local abbr = ''
    if completion_item.insertTextFormat == 2 then
      word = completion_item.label
      abbr = completion_item.label

      local text = word
      if completion_item.textEdit ~= nil then
        text = completion_item.textEdit.newText or text
      elseif completion_item.insertText ~= nil then
        text = completion_item.insertText or text
      end
      if word ~= text then
        abbr = abbr .. '~'
      end
      word = text
    else
      word = completion_item.insertText or completion_item.label
      abbr = completion_item.label
    end
    word = string.gsub(string.gsub(word, '^%s*', ''), '%s*$', '')
    abbr = string.gsub(string.gsub(abbr, '^%s*', ''), '%s*$', '')

    -- Fix for leading_word
    local suggest_offset = args.keyword_pattern_offset
    local word_char = string.byte(word, 1)
    for idx = #context.before_line, 1, -1 do
      local line_char = string.byte(context.before_line, idx)
      if Character.is_white(line_char) then
        break
      end
      if word_char == line_char then
        if string.find(word, string.sub(context.before_line, idx, -1), 1, true) == 1 then
          suggest_offset = idx
          keyword_pattern_offset = math.min(idx, keyword_pattern_offset)
          break
        end
      end
    end

    table.insert(complete_items, {
      word = word,
      abbr = abbr,
      kind = vim.lsp.protocol.CompletionItemKind[completion_item.kind] or nil;
      user_data = {
        compe = {
          request_position = request.position;
          completion_item = completion_item;
        };
      };
      filter_text = completion_item.filterText or abbr;
      sort_text = completion_item.sortText or abbr;
      preselect = completion_item.preselect or false;
      suggest_offset = suggest_offset;
    })
  end

  local input = string.sub(context.before_line, keyword_pattern_offset, -1)
  local bytes = Private.get_byte_map(input)
  for _, complete_item in ipairs(complete_items) do
    complete_item.word = Private.get_word(input, complete_item.word, bytes)
  end

  return {
    items = complete_items,
    incomplete = response.isIncomplete or false,
    keyword_pattern_offset = keyword_pattern_offset;
  }
end

return Helper

