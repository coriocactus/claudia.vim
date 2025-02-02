" Save cpo
let s:save_cpo = &cpo
set cpo&vim

" Global state
let s:active_job = v:null

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
        \ 'max_tokens': 4096,
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

function! WriteStringAtCursor(str) abort
    " First normalize all line endings
    let l:normalized = substitute(a:str, '\r\n\|\r\|\n', '\n', 'g')
    
    " Replace invisible space characters with regular spaces
    let l:normalized = substitute(l:normalized, '\%u00A0\|\%u2000-\%u200A\|\%u202F\|\%u205F\|\%u3000', ' ', 'g')
    
    " Fix specific code patterns
    let l:normalized = substitute(l:normalized, 'class\s*\([A-Za-z0-9_]\+\)', 'class \1', 'g')
    let l:normalized = substitute(l:normalized, 'def\s*\([A-Za-z0-9_]\+\)', 'def \1', 'g')
    
    " Split into lines, preserving empty lines
    let l:lines = split(l:normalized, '\n', 1)
    
    let l:pos = getpos('.')
    
    " Handle first line
    let l:current_line = getline('.')
    call setline('.', l:current_line . l:lines[0])
    
    " Add remaining lines
    if len(l:lines) > 1
        call append('.', l:lines[1:])
    endif
    
    " Update cursor position
    let l:new_pos = [l:pos[0], l:pos[1] + len(l:lines) - 1, l:pos[2] + len(l:lines[-1]), l:pos[3]]
    call setpos('.', l:new_pos)
    
    " Force redraw
    redraw
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
endfunction

function! CancelJob()
    if exists('s:active_job') && s:active_job != v:null
        call job_stop(s:active_job)
        let s:active_job = v:null
        if hasmapto('CancelJob')
            silent! nunmap <Esc>
        endif
    endif
endfunction

function! StreamLLMResponse(...) abort
    let l:defaults = {
        \ 'url': 'https://api.anthropic.com/v1/messages',
        \ 'api_key_name': 'ANTHROPIC_API_KEY',
        \ 'model': 'claude-3-5-sonnet-20241022'
        \ }

    " Get user options (if any)
    let l:opts = a:0 > 0 ? a:1 : {}
    " Merge with defaults
    let l:options = extend(copy(l:defaults), l:opts)

    let l:prompt = GetVisualSelection()
    let l:is_visual = !empty(l:prompt)
    if !l:is_visual
        let l:prompt = GetLinesUntilCursor()
    endif

    let l:system_prompt = get(l:options, 'system_prompt', 'You are a helpful assistant.')

    " Handle newline insertion based on mode
    if l:is_visual
        let l:end_line = line("'>")
        execute "normal! \<Esc>"
        call setline(l:end_line + 1, [''])
        execute "normal! " . (l:end_line + 1) . "G"
    else
        call append('.', '')
        normal! j
    endif

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

function! StreamLLMResponseWithContext(context_file, ...) abort
    let l:defaults = {
        \ 'url': 'https://api.anthropic.com/v1/messages',
        \ 'api_key_name': 'ANTHROPIC_API_KEY',
        \ 'model': 'claude-3-5-sonnet-20241022'
        \ }

    " Get user options (if any)
    let l:opts = a:0 > 0 ? a:1 : {}
    " Merge with defaults
    let l:options = extend(copy(l:defaults), l:opts)

    " Expand home directory if path starts with ~
    let l:expanded_path = expand(a:context_file)
    
    " Load the context file content
    let l:context_content = LoadFile(l:expanded_path)
    if empty(l:context_content)
        echohl ErrorMsg
        echo "Could not load context file: " . l:expanded_path
        echohl None
        return
    endif

    " Add the context content to options
    let l:options.cache_content = l:context_content

    let l:prompt = GetVisualSelection()
    let l:is_visual = !empty(l:prompt)
    if !l:is_visual
        let l:prompt = GetLinesUntilCursor()
    endif

    let l:system_prompt = get(l:options, 'system_prompt', 'You are a helpful assistant.')

    " Handle newline insertion based on mode
    if l:is_visual
        let l:end_line = GetVisualEndLine()
        call append(l:end_line, '')
        call cursor(l:end_line + 1, 1)
    else
        call append('.', '')
        normal! j
    endif

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
