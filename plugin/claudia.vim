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

" Context management state
let s:context_entries = []
let s:next_context_id = 1

" Reset function for global state
function! ResetGlobalState() abort
    let s:active_job = v:null
    let s:thinking_timer = v:null
    let s:dots_state = 0
    let s:current_thinking_word = ''
    let s:response_started = 0
    let s:original_cursor_pos = []
    " Don't reset context entries here as they should persist
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

" Context Management Functions
function! s:AddContext(filepath) abort
    " Expand filepath to handle ~ and environment variables
    let l:expanded_path = expand(a:filepath)

    " Validate file exists
    if !filereadable(l:expanded_path)
        echoerr "File not readable: " . l:expanded_path
        return
    endif

    " Add new context entry - store both original and expanded path
    let l:entry = {
        \ 'id': s:next_context_id,
        \ 'filepath': a:filepath,
        \ 'expanded_path': l:expanded_path
        \ }
    call add(s:context_entries, l:entry)

    " Increment ID counter
    let s:next_context_id += 1

    echo "Added context from " . a:filepath . " with ID " . (s:next_context_id - 1)
endfunction

function! s:ShowContext() abort
    if empty(s:context_entries)
        echo "No context entries"
        return
    endif

    echo "Context Entries:"
    for entry in s:context_entries
        echo printf("ID: %d, File: %s", entry.id, entry.filepath)
    endfor
endfunction

function! s:RemoveContext(id) abort
    let l:id = str2nr(a:id)
    let l:index = -1

    " Find entry with matching ID
    for i in range(len(s:context_entries))
        if s:context_entries[i].id == l:id
            let l:index = i
            break
        endif
    endfor

    if l:index >= 0
        call remove(s:context_entries, l:index)
        echo "Removed context with ID " . l:id
    else
        echoerr "No context found with ID " . l:id
    endif
endfunction

function! s:ClearContext() abort
    let s:context_entries = []
    let s:next_context_id = 1
    echo "Cleared all context entries"
endfunction

" Core Plugin Functions
function! GetApiKey(name) abort
    return $ANTHROPIC_API_KEY
endfunction

function! LoadFile(file_path) abort
    if filereadable(a:file_path)
        return join(readfile(a:file_path), "\n")
    endif
    return ''
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
    let l:api_key = $ANTHROPIC_API_KEY

    " Prepare system blocks
    let l:system_blocks = []
    call add(l:system_blocks, {
        \ 'type': 'text',
        \ 'text': g:claudia_config.system_prompt
        \ })

    " Prepare content blocks
    let l:content_blocks = []

    " Add context blocks first
    for entry in s:context_entries
        let l:context_text = LoadFile(entry.expanded_path)
        if !empty(l:context_text)
            call add(l:content_blocks, {
                \ 'type': 'text',
                \ 'text': l:context_text
                \ })
        endif
    endfor

    " Add user prompt last
    call add(l:content_blocks, {
        \ 'type': 'text',
        \ 'text': a:prompt
        \ })

    let l:data = {
        \ 'messages': [{'role': 'user', 'content': l:content_blocks}],
        \ 'model': g:claudia_config.model,
        \ 'stream': v:true,
        \ 'max_tokens': g:claudia_config.max_tokens,
        \ 'temperature': g:claudia_config.temperature,
        \ 'system': l:system_blocks
        \ }

    let l:args = ['-N', '-X', 'POST', '-H', 'Content-Type: application/json']

    " Add API key headers
    call add(l:args, '-H')
    call add(l:args, 'x-api-key: ' . l:api_key)
    call add(l:args, '-H')
    call add(l:args, 'anthropic-version: 2023-06-01')

    " Add data last
    let l:json_data = json_encode(l:data)
    call add(l:args, '-d')
    call add(l:args, l:json_data)

    " Add URL from config
    call add(l:args, g:claudia_config.url)
    return l:args
endfunction

function! JobOutCallback(channel, msg)
    call HandleAnthropicData(a:msg, 'content_block_delta')
endfunction

function! JobErrCallback(channel, msg)
endfunction

function! JobExitCallback(job, status)
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

function! HandleAnthropicData(data, event_state) abort
    " Split the input into individual events
    let l:events = split(a:data, "event: ")

    for l:event in l:events
        if empty(l:event)
            continue
        endif

        " Split event into type and data
        let l:parts = split(l:event, "\n")
        if len(l:parts) < 2
            continue
        endif

        let l:event_type = l:parts[0]
        let l:data = l:parts[1]

        " Remove 'data: ' prefix if present
        if l:data =~# '^data: '
            let l:data = l:data[6:]
        endif

        try
            let l:json = json_decode(l:data)
            if l:event_type ==# 'content_block_delta'
                if has_key(l:json, 'delta') && has_key(l:json.delta, 'text')
                    call WriteStringAtCursor(l:json.delta.text)
                endif
            endif
        catch
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
command! ClaudiaShowContext call s:ShowContext()
command! -nargs=1 ClaudiaRemoveContext call s:RemoveContext(<q-args>)
command! ClaudiaClearContext call s:ClearContext()

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
