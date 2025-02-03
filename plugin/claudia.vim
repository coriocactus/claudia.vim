" Save cpo
let s:save_cpo = &cpo
set cpo&vim

" Global configuration dictionary - Must be defined before global state
if !exists('g:claudia_config')
    let g:claudia_config = {
                \ 'url': 'https://api.anthropic.com/v1/messages',
                \ 'api_key_name': 'ANTHROPIC_API_KEY',
                \ 'model': 'claude-3-5-sonnet-20241022',
                \ 'system_prompt': 'You are a helpful assistant.',
                \ 'max_tokens': 4096,
                \ 'temperature': 0.25,
                \ }
endif

" Global state
let s:active_job = v:null
let s:thinking_timer = v:null
let s:thinking_states = [
            \ 'What does the stochastic parrot want to hear',
            \ 'Hallucinating so they can be God in their own head',
            \ 'Just predicting some tokens in 4294967296-dimensional probabilistic space',
            \ 'Unintentionally doing what they cannot do intentionally',
            \ 'Regurgitating training data for the specific problem that I was trained to solve',
            \ ]
let s:dots_state = 0
let s:current_thinking_word = ''
let s:response_started = 0
let s:original_cursor_pos = []
let s:debug_mode = 0
let s:debug_buffer = []
let s:max_debug_lines = 1000

" Context management state
let s:context_entries = []
let s:next_context_id = 1
let s:context_cache = {}

" Reset function for global state
function! ResetGlobalState() abort
    let s:active_job = v:null
    let s:thinking_timer = v:null
    let s:dots_state = 0
    let s:current_thinking_word = ''
    let s:response_started = 0
    let s:original_cursor_pos = []
    " Don't reset context entries or cache here as they should persist
endfunction

" Debug functions
function! s:DebugLog(msg) abort
    if !s:debug_mode
        return
    endif

    " Format message with timestamp
    let l:timestamp = strftime('%H:%M:%S')
    let l:formatted = printf('[%s] %s', l:timestamp, a:msg)

    " Truncate very long messages
    if len(l:formatted) > 1000
        let l:formatted = s:TruncateString(l:formatted, 1000)
    endif

    " Add to debug buffer
    call add(s:debug_buffer, l:formatted)

    " Trim buffer if too large
    if len(s:debug_buffer) > s:max_debug_lines
        let s:debug_buffer = s:debug_buffer[-s:max_debug_lines:]
    endif

    " Echo to messages
    echom l:formatted
endfunction

function! s:TruncateString(str, max_len) abort
    if len(a:str) > a:max_len
        return strpart(a:str, 0, a:max_len) . '...'
    endif
    return a:str
endfunction

function! s:TruncateValue(value, maxlen) abort
    if type(a:value) == v:t_string
        if len(a:value) > a:maxlen
            return strpart(a:value, 0, a:maxlen) . '...'
        endif
        return a:value
    endif
    return a:value
endfunction

function! s:SanitizeForDebug(data) abort
    let l:debug_data = deepcopy(a:data)
    let l:max_value_len = 10  " Maximum length for content values

    " Recursive function to process nested structures
    function! s:ProcessValue(item, maxlen) abort
        if type(a:item) == v:t_dict
            let l:result = {}
            for [key, val] in items(a:item)
                let l:result[key] = s:ProcessValue(val, a:maxlen)
            endfor
            return l:result
        elseif type(a:item) == v:t_list
            let l:result = []
            for val in a:item
                call add(l:result, s:ProcessValue(val, a:maxlen))
            endfor
            return l:result
        else
            return s:TruncateValue(a:item, a:maxlen)
        endif
    endfunction

    return s:ProcessValue(l:debug_data, l:max_value_len)
endfunction

function! s:DumpVar(name, var) abort
    if !s:debug_mode
        return
    endif

    let l:str = string(a:var)
    " Truncate long strings for readability
    if len(l:str) > 1000
        let l:str = l:str[0:997] . '...'
    endif
    call s:DebugLog(printf('%s = %s', a:name, l:str))
endfunction

function! s:ToggleDebug() abort
    let s:debug_mode = !s:debug_mode
    let s:debug_buffer = []
    echo "Debug mode " . (s:debug_mode ? "enabled" : "disabled")
    if s:debug_mode
        call s:DebugLog("Debug mode enabled")
        call s:DebugLog("Plugin version: 1.0.0")
        call s:DebugLog("Vim version: " . v:version)
        call s:DumpVar("config", g:claudia_config)
    endif
endfunction

function! s:ShowDebugLog() abort
    if empty(s:debug_buffer)
        echo "Debug log is empty"
        return
    endif

    " Create new buffer for log
    new
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal nobuflisted

    " Set buffer name
    execute 'file' 'ClaudiaDebugLog-' . strftime('%Y%m%d-%H%M%S')

    " Add content
    call setline(1, s:debug_buffer)

    " Make buffer readonly
    setlocal readonly
endfunction

" Configuration Management Functions
function! s:InitializeConfig() abort
    " Allow user to override defaults in their vimrc
    let l:user_config = get(g:, 'claudia_user_config', {})
    let g:claudia_config = extend(copy(g:claudia_config), l:user_config)
endfunction

function! s:ShowConfig() abort
    echo printf("%-15s %s", "URL:", g:claudia_config.url)
    echo printf("%-15s %s", "Model:", g:claudia_config.model)
    echo printf("%-15s %s", "System Prompt:", g:claudia_config.system_prompt)
    echo printf("%-15s %d", "Max Tokens:", g:claudia_config.max_tokens)
    echo printf("%-15s %.2f", "Temperature:", g:claudia_config.temperature)
endfunction

function! s:SetTemperature(temp) abort
    let l:temp_float = str2float(a:temp)
    if l:temp_float >= 0.0 && l:temp_float <= 1.0
        let g:claudia_config.temperature = l:temp_float
        echo "claudia temperature set to " . a:temp
    else
        echoerr "Temperature must be between 0.0 and 1.0"
    endif
endfunction

function! s:SetMaxTokens(tokens) abort
    let l:tokens_nr = str2nr(a:tokens)
    if l:tokens_nr > 0
        let g:claudia_config.max_tokens = l:tokens_nr
        echo "claudia max tokens set to " . a:tokens
    else
        echoerr "Max tokens must be a positive number"
    endif
endfunction

function! s:SetSystemPrompt(prompt) abort
    let g:claudia_config.system_prompt = a:prompt
    echo "claudia system prompt updated"
endfunction

function! s:SetModel(model) abort
    let g:claudia_config.model = a:model
    echo "claudia model set to " . a:model
endfunction

" Media Support Functions

" Media type detection
function! s:GetMediaType(filepath) abort
    let l:ext = tolower(fnamemodify(a:filepath, ':e'))
    let l:media_types = {
                \ 'jpg': 'image/jpeg',
                \ 'jpeg': 'image/jpeg',
                \ 'png': 'image/png',
                \ 'gif': 'image/gif',
                \ 'webp': 'image/webp',
                \ 'pdf': 'application/pdf'
                \ }
    return get(l:media_types, l:ext, '')
endfunction

" Progress bar function
function! s:ShowProgress(current, total) abort
    let l:width = 40
    let l:filled = float2nr(round(l:width * a:current / a:total))
    let l:empty = l:width - l:filled
    let l:bar = repeat('█', l:filled) . repeat('░', l:empty)
    redraw
    echo printf('Converting file: [%s] %d%%', l:bar, float2nr(round(100.0 * a:current / a:total)))
endfunction

function! s:LoadFileWithProgress(filepath, type) abort
    call s:DebugLog("Loading file: " . a:filepath . " (type: " . a:type . ")")

    " Recheck file existence
    if !filereadable(a:filepath)
        call s:DebugLog("Error: File no longer accessible")
        throw "File no longer accessible: " . a:filepath
    endif

    " Get file size
    let l:size = getfsize(a:filepath)
    call s:DebugLog("File size: " . l:size . " bytes")

    if a:type ==# 'text'
        let l:content = join(readfile(a:filepath), "\n")
        call s:DebugLog("Loaded text file, length: " . len(l:content))
        return l:content
    else
        call s:DebugLog("Starting base64 conversion")

        " Initialize progress
        call s:ShowProgress(0, 100)

        " Use base64 command with proper options to ensure clean output
        let l:cmd = 'base64 -w 0 -i ' . shellescape(a:filepath) . ' | tr -d "\n"'
        call s:DebugLog("Running command: " . l:cmd)

        let l:output = system(l:cmd)
        let l:status = v:shell_error

        call s:DebugLog("base64 conversion complete, status: " . l:status)
        call s:DebugLog("base64 output length: " . len(l:output))

        if l:status
            call s:DebugLog("Error: base64 conversion failed")
            throw "Failed to convert file: " . a:filepath
        endif

        " Clear progress display
        redraw
        echo ""

        return l:output
    endif
endfunction

" Cache management functions
function! s:CacheContext(id) abort
    let l:entry = v:null

    " Find context entry
    for e in s:context_entries
        if e.id == str2nr(a:id)
            let l:entry = e
            break
        endif
    endfor

    if l:entry is v:null
        echoerr "No context found with ID " . a:id
        return
    endif

    try
        echo "Caching content from " . l:entry.filepath . "..."
        let l:content = s:LoadFileWithProgress(l:entry.expanded_path, l:entry.type)
        let s:context_cache[a:id] = l:content
        echo "Successfully cached content from " . l:entry.filepath
    catch
        echoerr "Failed to cache content from " . l:entry.filepath . ": " . v:exception
    endtry
endfunction

" Enhanced context entry creation
function! s:CreateContextEntry(filepath, type) abort
    " Expand filepath to handle ~ and environment variables
    let l:expanded_path = expand(a:filepath)

    " Validate file exists
    if !filereadable(l:expanded_path)
        echoerr "File not readable: " . l:expanded_path
        return v:null
    endif

    " Get media type for media files
    let l:media_type = ''
    if a:type ==# 'media'
        let l:media_type = s:GetMediaType(l:expanded_path)
        if empty(l:media_type)
            echoerr "Unsupported file type: " . l:expanded_path
            return v:null
        endif
    endif

    " Create context entry without loading content
    let l:entry = {
                \ 'id': s:next_context_id,
                \ 'filepath': a:filepath,
                \ 'expanded_path': l:expanded_path,
                \ 'type': a:type,
                \ 'media_type': l:media_type
                \ }

    return l:entry
endfunction

" Context Management Functions
"
function! s:UpdateNextContextId() abort
    " If no contexts exist, reset to 1
    if empty(s:context_entries)
        let s:next_context_id = 1
        return
    endif

    " Find highest existing ID and set next_context_id to one more than that
    let l:max_id = 0
    for entry in s:context_entries
        if entry.id > l:max_id
            let l:max_id = entry.id
        endif
    endfor
    let s:next_context_id = l:max_id + 1
endfunction

function! s:AddContext(filepath) abort
    let l:entry = s:CreateContextEntry(a:filepath, 'text')
    if l:entry isnot v:null
        call add(s:context_entries, l:entry)
        let s:next_context_id += 1
        echo "Added context from " . a:filepath . " with ID " . (s:next_context_id - 1)
    endif
endfunction

function! s:AddImage(filepath) abort
    let l:entry = s:CreateContextEntry(a:filepath, 'media')
    if l:entry isnot v:null
        call add(s:context_entries, l:entry)
        let s:next_context_id += 1
        echo "Added image from " . a:filepath . " with ID " . (s:next_context_id - 1)
    endif
endfunction

function! s:AddPDF(filepath) abort
    let l:entry = s:CreateContextEntry(a:filepath, 'media')
    if l:entry isnot v:null
        call add(s:context_entries, l:entry)
        let s:next_context_id += 1
        echo "Added PDF from " . a:filepath . " with ID " . (s:next_context_id - 1)
    endif
endfunction

function! s:ShowContext() abort
    if empty(s:context_entries)
        echo "No context entries"
        return
    endif

    echo "Context Entries:"
    for entry in s:context_entries
        let l:type_str = entry.type ==# 'media' ? ' [' . entry.media_type . ']' : ''
        let l:cache_str = has_key(s:context_cache, entry.id) ? ' (cached)' : ''
        echo printf("ID: %d, File: %s%s%s", entry.id, entry.filepath, l:type_str, l:cache_str)
    endfor
endfunction

function! s:RemoveContext(id) abort
    let l:id = str2nr(a:id)
    let l:index = -1
    let l:removed_filepath = ''

    " Find entry with matching ID and store its filepath
    for i in range(len(s:context_entries))
        if s:context_entries[i].id == l:id
            let l:index = i
            let l:removed_filepath = s:context_entries[i].filepath
            break
        endif
    endfor

    if l:index >= 0
        " Remove from cache if present
        if has_key(s:context_cache, l:id)
            unlet s:context_cache[l:id]
        endif
        " Remove from contexts
        call remove(s:context_entries, l:index)
        " Update next_context_id
        call s:UpdateNextContextId()
        echo "Removed context " . l:id . " (" . l:removed_filepath . ")"
    else
        echoerr "No context found with ID " . l:id
    endif
endfunction

function! s:ClearContext() abort
    let s:context_entries = []
    let s:next_context_id = 1
    let s:context_cache = {}
    echo "Cleared all context entries and cache"
endfunction

" Core Plugin Functions
function! GetApiKey(name) abort
    return $ANTHROPIC_API_KEY
endfunction

function! AnimateThinking(timer) abort
    " Don't animate if response has started
    if s:response_started
        call StopThinkingAnimation()
        return
    endif

    if s:active_job == v:null
        call StopThinkingAnimation()
        return
    endif

    " Update dots animation
    let s:dots_state = (s:dots_state + 1) % 4
    let l:dots = repeat('.', s:dots_state)

    " Get current line
    let l:current_line = getline('.')
    " Remove previous thinking text if it exists
    let l:cleaned_line = substitute(l:current_line, s:current_thinking_word . '\.*$', '', '')
    " Add new thinking text
    let l:new_line = l:cleaned_line . s:current_thinking_word . l:dots
    call setline('.', l:new_line)
    redraw
endfunction

function! StartThinkingAnimation() abort
    let s:response_started = 0  " Reset response flag
    " Randomly select a thinking word
    let l:rand_index = rand() % len(s:thinking_states)
    let s:current_thinking_word = s:thinking_states[l:rand_index]

    " Start timer for animation
    let s:thinking_timer = timer_start(300, 'AnimateThinking', {'repeat': -1})
endfunction

function! StopThinkingAnimation() abort
    if s:thinking_timer != v:null
        call timer_stop(s:thinking_timer)
        let s:thinking_timer = v:null
        " Clean up thinking text
        let l:current_line = getline('.')
        let l:cleaned_line = substitute(l:current_line, s:current_thinking_word . '\.*$', '', '')
        call setline('.', l:cleaned_line)
    endif
endfunction

function! GetLinesUntilCursor() abort
    let l:current_line = line('.')
    let l:lines = getline(1, l:current_line)
    return join(l:lines, "\n")
endfunction

function! GetVisualSelection() abort
    let [l:line_start, l:column_start] = getpos("'<")[1:2]
    let [l:line_end, l:column_end] = getpos("'>")[1:2]
    let l:lines = getline(l:line_start, l:line_end)

    if visualmode() ==# 'v'
        let l:lines[-1] = l:lines[-1][: l:column_end - 1]
        let l:lines[0] = l:lines[0][l:column_start - 1:]
    elseif visualmode() ==# 'V'
    " Line-wise visual mode - no modification needed
    elseif visualmode() ==# "\<C-V>"
        let l:new_lines = []
        for l:line in l:lines
            call add(l:new_lines, l:line[l:column_start - 1 : l:column_end - 1])
        endfor
        let l:lines = l:new_lines
    endif

    return join(l:lines, "\n")
endfunction

function! WriteStringAtCursor(str) abort
    " If this is the first write, clean up thinking animation and prepare new line
    if !s:response_started
        let s:response_started = 1  " Mark that response has started
        call StopThinkingAnimation()

        " Store original cursor position if not already stored
        if empty(s:original_cursor_pos)
            let s:original_cursor_pos = getpos('.')
        endif

        " Move to next line to start the actual response
        call append('.', '')
        normal! j
    endif

    " First normalize all line endings
    let l:normalized = substitute(a:str, '\r\n\|\r\|\n', '\n', 'g')

    " Replace invisible space characters with regular spaces
    let l:normalized = substitute(l:normalized, '\%u00A0\|\%u2000-\%u200A\|\%u202F\|\%u205F\|\%u3000', ' ', 'g')

    " Fix specific code patterns
    let l:normalized = substitute(l:normalized, 'class\s*\([A-Za-z0-9_]\+\)', 'class \1', 'g')
    let l:normalized = substitute(l:normalized, 'def\s*\([A-Za-z0-9_]\+\)', 'def \1', 'g')

    " Split into lines, preserving empty lines
    let l:lines = split(l:normalized, '\n', 1)

    " Get current position relative to original cursor position
    let l:current_pos = getpos('.')
    let l:line_offset = l:current_pos[1] - s:original_cursor_pos[1]

    " Handle first line
    let l:current_line = getline('.')
    call setline('.', l:current_line . l:lines[0])

    " Add remaining lines
    if len(l:lines) > 1
        call append('.', l:lines[1:])
    endif

    " Calculate new cursor position
    let l:new_line = s:original_cursor_pos[1] + l:line_offset + len(l:lines) - 1
    let l:new_col = len(getline(l:new_line))
    call cursor(l:new_line, l:new_col)

    " Force redraw
    redraw
endfunction

function! MakeAnthropicCurlArgs(prompt) abort
    call s:DebugLog("Preparing API request")
    call s:DebugLog("Number of context entries: " . len(s:context_entries))

    " Validate API key
    let l:api_key = $ANTHROPIC_API_KEY
    if empty(l:api_key)
        call s:DebugLog("Error: API key not found in environment")
        echoerr "API key not found in environment variable ANTHROPIC_API_KEY"
        return []
    endif
    call s:DebugLog("API key found (length: " . len(l:api_key) . ")")

    " Prepare content blocks
    let l:content_blocks = []

    " Process context entries first
    for entry in s:context_entries
        try
            call s:DebugLog("Processing context entry: " . entry.filepath)
            call s:DebugLog("Entry type: " . entry.type)
            let l:content = ''

            " Check if content is cached
            if has_key(s:context_cache, entry.id)
                call s:DebugLog("Using cached content for ID " . entry.id)
                let l:content = s:context_cache[entry.id]
            else
                call s:DebugLog("Loading content for ID " . entry.id)
                let l:content = s:LoadFileWithProgress(entry.expanded_path, entry.type)
            endif

            call s:DebugLog("Content loaded, length: " . len(l:content))

            if entry.type ==# 'text'
                if !empty(l:content)
                    call s:DebugLog("Adding text content block")
                    let l:block = {
                                \ 'type': 'text',
                                \ 'text': l:content
                                \ }

                    " Add cache control if content is cached
                    if has_key(s:context_cache, entry.id)
                        let l:block.cache_control = {'type': 'ephemeral'}
                    endif

                    call add(l:content_blocks, l:block)
                endif
            elseif entry.type ==# 'media'
                call s:DebugLog("Adding media content block: " . entry.media_type)
                let l:block = {
                            \ 'type': entry.media_type =~# '^image/' ? 'image' : 'document',
                            \ 'source': {
                            \ 'type': 'base64',
                            \ 'media_type': entry.media_type,
                            \ 'data': l:content
                            \ }
                            \ }

                " Add cache control if content is cached
                if has_key(s:context_cache, entry.id)
                    let l:block.cache_control = {'type': 'ephemeral'}
                endif

                call add(l:content_blocks, l:block)
            endif

            call s:DebugLog("Context block added successfully")
        catch
            let l:error_msg = "Failed to process context " . entry.filepath . ": " . v:exception
            call s:DebugLog("Error: " . l:error_msg)
            echoerr l:error_msg
            return []
        endtry
    endfor

    call s:DebugLog("Context blocks processed: " . len(l:content_blocks))

    " Add user prompt last
    call add(l:content_blocks, {
                \ 'type': 'text',
                \ 'text': a:prompt
                \ })

    call s:DebugLog("Total content blocks (including prompt): " . len(l:content_blocks))

    " Build request data
    let l:data = {
                \ 'messages': [{'role': 'user', 'content': l:content_blocks}],
                \ 'model': g:claudia_config.model,
                \ 'stream': v:true,
                \ 'max_tokens': g:claudia_config.max_tokens,
                \ 'temperature': g:claudia_config.temperature,
                \ 'system': [{'type': 'text', 'text': g:claudia_config.system_prompt}]
                \ }

    " Log sanitized request data with preserved structure
    let l:debug_data = s:SanitizeForDebug(l:data)
    call s:DebugLog("Request data structure: " . string(l:debug_data))

    " Build curl arguments with explicit header handling
    let l:headers = [
                \ 'Content-Type: application/json',
                \ 'x-api-key: ' . l:api_key,
                \ 'anthropic-version: 2023-06-01'
                \ ]

    let l:args = ['-N', '-X', 'POST']

    if s:debug_mode
        call add(l:args, '-v')
        let l:error_log = tempname()
        call add(l:args, '--stderr')
        call add(l:args, l:error_log)
        let s:curl_error_log = l:error_log
    endif

    for header in l:headers
        call add(l:args, '-H')
        call add(l:args, header)
    endfor

    let l:json_data = json_encode(l:data)
    call add(l:args, '-d')
    call add(l:args, l:json_data)
    call add(l:args, g:claudia_config.url)

    return l:args
endfunction

function! JobOutCallback(channel, msg)
    call s:DebugLog("Response chunk received:")
    call s:DebugLog("Chunk length: " . len(a:msg))
    call s:DebugLog("First 100 chars: " . strpart(a:msg, 0, 100))

    " Check for error response
    if a:msg =~# '^{"type":"error"'
        try
            let l:json = json_decode(a:msg)
            if type(l:json) == v:t_dict && has_key(l:json, 'error')
                call s:HandleAPIError(l:json)
                return
            endif
        catch
            call s:DebugLog("Error parsing error JSON: " . v:exception)
        endtry
    endif

    " If not an error, process normally
    call HandleAnthropicData(a:msg, 'content_block_delta')
endfunction

function! JobErrCallback(channel, msg)
    call s:DebugLog("Error from job: " . a:msg)
endfunction

function! JobExitCallback(job, status)
    call s:DebugLog("Job exited with status: " . a:status)

    " Check curl error log if available
    if s:debug_mode && exists('s:curl_error_log') && filereadable(s:curl_error_log)
        let l:errors = readfile(s:curl_error_log)
        if !empty(l:errors)
            call s:DebugLog("Curl debug output:")
            for l:line in l:errors
                call s:DebugLog("Curl: " . l:line)
            endfor
        endif
        " Clean up temp file
        call delete(s:curl_error_log)
        unlet s:curl_error_log
    endif

    let s:active_job = v:null
    if hasmapto('CancelJob')
        silent! nunmap <Esc>
    endif
    call ResetGlobalState()
endfunction

function! CancelJob()
    if exists('s:active_job') && s:active_job != v:null
        call job_stop(s:active_job)
        let s:active_job = v:null
        if hasmapto('CancelJob')
            silent! nunmap <Esc>
        endif
        " Stop thinking animation
        call StopThinkingAnimation()
        call ResetGlobalState()
    endif
endfunction

" API Error handling
function! s:HandleAPIError(error) abort
    " Extract error information
    if type(a:error) != v:t_dict || !has_key(a:error, 'error')
        call s:DebugLog("Invalid error format")
        return
    endif

    let l:error = a:error.error
    let l:type = get(l:error, 'type', 'unknown_error')
    let l:message = get(l:error, 'message', 'Unknown error occurred')
    let l:details = get(l:error, 'details', v:null)

    call s:DebugLog("Handling API error: " . l:type)
    call s:DebugLog("Error message: " . l:message)
    if l:details != v:null
        call s:DebugLog("Error details: " . string(l:details))
    endif

    " Clean up any thinking animation
    call StopThinkingAnimation()

    " Force redraw to ensure buffer is clean
    redraw!

    " Handle specific error types
    if l:type ==# 'overloaded_error'
        echohl ErrorMsg
        echo "Anthropic API is currently unavailable (overloaded). Please try again later."
        echohl None
    elseif l:type ==# 'invalid_request_error'
        echohl ErrorMsg
        echo "Invalid request: " . l:message
        echohl None
    elseif l:type ==# 'authentication_error'
        echohl ErrorMsg
        echo "Authentication failed. Please check your API key."
        echohl None
    elseif l:type ==# 'permission_error'
        echohl ErrorMsg
        echo "Permission denied: " . l:message
        echohl None
    elseif l:type ==# 'not_found_error'
        echohl ErrorMsg
        echo "Resource not found: " . l:message
        echohl None
    elseif l:type ==# 'rate_limit_error'
        echohl ErrorMsg
        echo "Rate limit exceeded. Please wait before making more requests."
        echohl None
    else
        " Generic error handling
        echohl ErrorMsg
        echo "API Error (" . l:type . "): " . l:message
        echohl None
    endif

    " Cancel the current job and reset state
    call CancelJob()
endfunction

function! HandleAnthropicData(data, event_state) abort
    call s:DebugLog("Handling response data of length: " . len(a:data))
    call s:DebugLog("Raw response: " . a:data)

    " Split the input into individual events
    let l:events = split(a:data, "event: ")
    call s:DebugLog("Number of events: " . len(l:events))

    for l:event in l:events
        if empty(l:event)
            call s:DebugLog("Skipping empty event")
            continue
        endif

        " Split event into type and data
        let l:parts = split(l:event, "\n")
        if len(l:parts) < 2
            call s:DebugLog("Invalid event format - parts: " . string(l:parts))
            continue
        endif

        let l:event_type = l:parts[0]
        let l:data = l:parts[1]
        call s:DebugLog("Event type: " . l:event_type)

        " Remove 'data: ' prefix if present
        if l:data =~# '^data: '
            let l:data = l:data[6:]
        endif
        call s:DebugLog("Event data: " . l:data)

        try
            let l:json = json_decode(l:data)
            call s:DebugLog("Parsed JSON: " . string(l:json))
            if l:event_type ==# 'content_block_delta'
                if has_key(l:json, 'delta') && has_key(l:json.delta, 'text')
                    call s:DebugLog("Writing delta text: " . l:json.delta.text)
                    call WriteStringAtCursor(l:json.delta.text)
                else
                    call s:DebugLog("No delta.text in JSON: " . string(keys(l:json)))
                endif
            endif
        catch
            call s:DebugLog("JSON parse error: " . v:exception)
            continue
        endtry
    endfor
endfunction

function! s:TriggerClaudia() abort
    " Reset global state before starting new response
    call ResetGlobalState()

    " Store initial cursor position
    let s:original_cursor_pos = getpos('.')

    " Handle newline insertion based on mode
    let l:prompt = GetVisualSelection()
    if !empty(l:prompt)
        let l:end_line = line("'>")
        execute "normal! \<Esc>"
        call setline(l:end_line + 1, [''])
        execute "normal! " . (l:end_line + 1) . "G"
    else
        let l:prompt = GetLinesUntilCursor()
        call append('.', '')
        normal! j
    endif

    " Start thinking animation before making API call
    call StartThinkingAnimation()

    let l:args = MakeAnthropicCurlArgs(l:prompt)

    " Build curl command
    let l:curl_cmd = 'curl -N -s --no-buffer'
    for l:arg in l:args
        let l:curl_cmd .= ' ' . shellescape(l:arg)
    endfor

    " Execute curl in background
    let s:active_job = job_start(['/bin/sh', '-c', l:curl_cmd], {
                \ 'out_cb': 'JobOutCallback',
                \ 'err_cb': 'JobErrCallback',
                \ 'exit_cb': 'JobExitCallback',
                \ 'mode': 'raw'
                \ })

    " Allow cancellation with Escape
    nnoremap <silent> <Esc> :call CancelJob()<CR>
endfunction

" Commands for runtime configuration
command! -nargs=1 ClaudiaTemp call s:SetTemperature(<q-args>)
command! -nargs=1 ClaudiaTokens call s:SetMaxTokens(<q-args>)
command! -nargs=1 ClaudiaSystemPrompt call s:SetSystemPrompt(<q-args>)
command! -nargs=1 ClaudiaModel call s:SetModel(<q-args>)
command! ClaudiaShowConfig call s:ShowConfig()
command! ClaudiaResetConfig call s:InitializeConfig()

" Context management commands
command! -nargs=1 -complete=file ClaudiaAddContext call s:AddContext(<q-args>)
command! -nargs=1 -complete=file ClaudiaAddImage call s:AddImage(<q-args>)
command! -nargs=1 -complete=file ClaudiaAddPDF call s:AddPDF(<q-args>)
command! -nargs=1 ClaudiaCacheContext call s:CacheContext(<q-args>)
command! -nargs=1 ClaudiaRemoveContext call s:RemoveContext(<q-args>)
command! ClaudiaShowContext call s:ShowContext()
command! ClaudiaClearContext call s:ClearContext()

" Debug commands
command! ClaudiaToggleDebug call s:ToggleDebug()
command! ClaudiaShowDebugLog call s:ShowDebugLog()

" Plugin mappings
if !hasmapto('<Plug>ClaudiaTrigger') && empty(maparg('<Leader>c', 'n'))
    nmap <silent> <Leader>c <Plug>ClaudiaTrigger
endif

if !hasmapto('<Plug>ClaudiaTriggerVisual') && empty(maparg('<Leader>c', 'x'))
    xmap <silent> <Leader>c <Plug>ClaudiaTriggerVisual
endif

nnoremap <silent> <script> <Plug>ClaudiaTrigger <SID>Trigger
nnoremap <silent> <SID>Trigger :call <SID>TriggerClaudia()<CR>

xnoremap <silent> <script> <Plug>ClaudiaTriggerVisual <SID>TriggerVisual
xnoremap <silent> <SID>TriggerVisual :<C-u>call <SID>TriggerClaudia()<CR>

" Initialize config on load
call s:InitializeConfig()

" Restore cpo
let &cpo = s:save_cpo
unlet s:save_cpo
