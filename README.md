# claudia.vim

A Vim plugin for interacting with Anthropic's Claude API directly in your editor. Send text to Claude and get streaming responses right where you're typing.

## Features

- Direct integration with Claude API
- Streaming responses (see the text as Claude generates it)
- Works in both normal and visual modes
- Cancel responses with Escape key
- Supports Claude 3 models
- Context caching for efficient API usage

## Requirements

- Vim 8+ (for job control features)
- curl installed on your system
- Anthropic API key

## Credit

This project is a vim rewrite of the following projects:
- https://github.com/yacineMTB/dingllm.nvim
- https://github.com/melbaldove/llm.nvim

## Installation

### vim-plug
```vim
Plug 'cordcivilian/claudia.vim'
```
### Manual Installation
```bash
mkdir -p ~/.vim/pack/plugins/start
cd ~/.vim/pack/plugins/start
git clone https://github.com/cordcivilian/claudia.vim.git
```
## API Key Setup
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```
## Configuration
```vim
" Normal mode - uses text from start (of buffer) to cursor
nnoremap <silent> <Leader>c :call StreamLLMResponse()<CR>
" Visual mode - uses selected text
xnoremap <silent> <Leader>c :<C-u>call StreamLLMResponse()<CR>

" default values of StreamLLMResponse
nnoremap <Leader>q :call StreamLLMResponse({
    \ 'url': 'https://api.anthropic.com/v1/messages',
    \ 'api_key_name': 'ANTHROPIC_API_KEY',
    \ 'model': 'claude-3-5-sonnet-20241022'
    \ 'system_prompt': 'You are a helpful assistant.',
    \ })<CR>
```
## Usage (with example mappings)

1. Normal Mode:
   - Type your prompt
   - Press `<Leader>c` to send everything from the start of the document to the cursor

2. Visual Mode:
   - Select text (using v, V, or Ctrl-V)
   - Press `<Leader>c` to send only the selected text

3. To cancel a response:
   - Press `Esc` while Claude is responding

## License

MIT License
