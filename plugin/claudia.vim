" Save cpo
let s:save_cpo = &cpo
set cpo&vim

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

function! ResetGlobalState() abort
    let s:active_job = v:null
    let s:thinking_timer = v:null
    let s:dots_state = 0
    let s:current_thinking_word = ''
    let s:response_started = 0
    let s:original_cursor_pos = []
endfunction

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

function! MakeAnthropicCurlArgs(opts, prompt, system_prompt) abort
    let l:url = a:opts.url
    let l:api_key = $ANTHROPIC_API_KEY

    " Prepare system blocks with caching
    let l:system_blocks = []

    " Add base system prompt
    call add(l:system_blocks, {
        \ 'type': 'text',
        \ 'text': a:system_prompt
        \ })

    " Add cached content if provided
    if has_key(a:opts, 'cache_content')
        call add(l:system_blocks, {
            \ 'type': 'text',
            \ 'text': a:opts.cache_content,
            \ 'cache_control': {'type': 'ephemeral'}
            \ })
    endif

    let l:data = {
        \ 'messages': [{'role': 'user', 'content': a:prompt}],
        \ 'model': a:opts.model,
        \ 'stream': v:true,
        \ 'max_tokens': a:opts.max_tokens,
        \ 'temperature': a:opts.temperature,
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

    " Add URL last
    call add(l:args, l:url)
    return l:args
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

function! StreamLLMResponse(...) abort
    " Reset global state before starting new response
    call ResetGlobalState()

    " Store initial cursor position
    let s:original_cursor_pos = getpos('.')

    let l:defaults = {
        \ 'url': 'https://api.anthropic.com/v1/messages',
        \ 'api_key_name': 'ANTHROPIC_API_KEY',
        \ 'model': 'claude-3-5-sonnet-20241022',
        \ 'system_prompt': 'You are a helpful assistant.',
        \ 'max_tokens': 4096,
        \ 'temperature': 0.25,
        \ }

    " Get user options (if any)
    let l:opts = a:0 > 0 ? a:1 : {}
    " Merge with defaults
    let l:options = extend(copy(l:defaults), l:opts)
    let l:system_prompt = get(l:options, 'system_prompt')

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

    let l:args = MakeAnthropicCurlArgs(l:options, l:prompt, l:system_prompt)

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

" Restore cpo
let &cpo = s:save_cpo
unlet s:save_cpo
