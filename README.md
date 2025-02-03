# claudia.vim

Interact with Anthropic's API directly in Vim.
Send text and get streaming responses right where you're typing.

## Why

- It's the age of the [terminal](https://github.com/ghostty-org/ghostty).
- AIs don’t need breaks--say no to "message limits."
- Keep API keys out of the browser.
- Maximum AI, minimal config.
- Pay for intelligence, not the messenger.

## Credit

This project is a vim rewrite of the following projects:
- https://github.com/yacineMTB/dingllm.nvim
- https://github.com/melbaldove/llm.nvim

## Features

- Direct integration with Anthropic API (Claude 3 models)
- Provide context via local file contents [Supported: texts, images, PDFs]
- Normal mode and Visual mode prompting
- Streaming responses
- Stop responses with Escape key
- Customizable API configurations
- WIP: Context caching for fast and efficient API usage
- WIP: Provide context via remote file contents
- WIP: Show exact tokens of context
- TODO: Trim trailing whitespace from responses
- TODO: Support for other APIs (probably DeepSeek first, most similar API)
- TODO: DEMO mp4 and DEMO md

## Usage (with default mappings)

**1. Normal Mode:**
- Press `<Leader>c` to send everything from the start of the document to the cursor

**2. Visual Mode:**
- Select text (using v, V, or Ctrl-V)
- Press `<Leader>c` to send only the selected text

**3. To cancel a response:**
- Press `Esc` while claudia is responding

## Adding Context

You can add file contents as context that will be prepended to every prompt:

1. Add context files:
```vim
:ClaudiaAddContext ~/path/to/context.txt    " Add a file as context
:ClaudiaAddPDF $HOME/pdfs/context.pdf       " Environment variables work
:ClaudiaAddImage ./path/to/context.png      " Relative paths work
```
2. Manage context:
```vim
:ClaudiaShowContext     " List all context files and their IDs
:ClaudiaRemoveContext 6 " Remove context with ID 6
:ClaudiaCacheContext 9  " Cache context with ID 9
:ClaudiaClearContext    " Remove all context files
```
Context files persist across queries but reset when Vim restarts.
Files are read fresh on each query, so edits to context files take effect immediately.

## Requirements

- Vim 8+ (for job control features)
- curl installed on your system
- Anthropic API key

## Getting Started

### Step 1 Option 1: vim-plug (or your preferred plugin manager)
```vim
Plug 'cordcivilian/claudia.vim'
```
### Step 1 Option 2: Manual Installation
```bash
mkdir -p ~/.vim/pack/plugins/start
cd ~/.vim/pack/plugins/start
git clone https://github.com/cordcivilian/claudia.vim.git
```
### Step 2: API Key Setup
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```
## Configuration

### Load Time (default configs and mappings shown)
```vim
" Normal mode - uses text from start (of buffer) to cursor
nmap <silent> <Leader>c <Plug>ClaudiaTrigger
" This is NOT mapped out of the box if your Normal mode <Leader>c is already in use

" Visual mode - uses selected text
xmap <silent> <Leader>c <Plug>ClaudiaTriggerVisual
" This is NOT mapped out of the box if your Visual mode <Leader>c is already in use

" API configurations
let g:claudia_user_config = {
    \ 'url': 'https://api.anthropic.com/v1/messages',
    \ 'api_key_name': 'ANTHROPIC_API_KEY',
    \ 'model': 'claude-3-5-sonnet-20241022',
    \ 'system_prompt': 'You are a helpful assistant.',
    \ 'max_tokens': 4096,
    \ 'temperature': 0.25,
    \ }
```
### Runtime
```vim
" Modify configs at runtime
:ClaudiaModel claude-3-opus-20240229
:ClaudiaSystemPrompt Pretend you are sentient.
:ClaudiaTokens 8192
:ClaudiaTemp 0.75
:ClaudiaResetConfig
:ClaudiaShowConfig
```
