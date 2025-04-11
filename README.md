# claudia.vim

![demo](./claudia.gif)

## Credit

This project is a vim rewrite of the following projects:
- https://github.com/yacineMTB/dingllm.nvim
- https://github.com/melbaldove/llm.nvim

## Usage (with default mappings)

**1. Normal Mode:**
- Press `<Leader>c` to send everything from the start of the buffer to the cursor

**2. Visual Mode:**
- Select text (using v, V, or Ctrl-V)
- Press `<Leader>c` to send only the selected text

**3. Replace Mode:**
- Add rewrite instructions as comments
- Select text with rewrite instructions (using v, V, or Ctrl-V)
- Press `<Leader>x` to send selected text to be rewritten by claudia

**4. To cancel a response:**
- Press `Esc` while claudia is responding

## Getting Started

### Step 1 Option 1: vim-plug (or your preferred plugin manager)

```vim
Plug 'coriocactus/claudia.vim'
```

### Step 1 Option 2: Manual Installation

```bash
mkdir -p ~/.vim/pack/plugins/start
cd ~/.vim/pack/plugins/start
git clone https://github.com/coriocactus/claudia.vim.git
```

### Step 2: API Key Setup

```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

## Adding Context

You can add file contents as context that will be prepended to every prompt:

1. Add context files:
```vim
:ClaudiaAddContext ~/path/to/context.txt    " Add a file as context
:ClaudiaAddContext $HOME/pdfs/context.pdf   " Environment variables work
:ClaudiaAddContext ./path/to/context.png    " Relative paths work
```
2. Manage context:
```vim
:ClaudiaShowContext         " List all context files and their IDs
:ClaudiaRemoveContext 6     " Remove context with ID 6
:ClaudiaClearContext        " Remove all context files
:ClaudiaCacheContext 9      " Cache context with ID 9 to avoid reloading
:ClaudiaUncacheContext 9    " Remove context ID 9 from cache
:ClaudiaClearCache          " Clear all cached context
```

Context persists across queries but resets when Vim restarts. Uncached context
are read fresh on each query, so edits to context files take effect
immediately. Cached context are read and stored in memory (and [prompt
cached](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching).)
Avoid caching frequently edited files since changes won't be reflected until
re-cached. Each set of context files are tied to the buffer in which they were
added.

## Extended Reasoning Mode

Claude 3.7 Sonnet supports extended thinking capabilities for more complex tasks:

```vim
:ClaudiaReason 0    " Disable reasoning mode (default, max_tokens: 8192)
:ClaudiaReason 1    " Enable medium reasoning (max_tokens: 64000, thinking budget: 16000)
:ClaudiaReason 2    " Enable heavy reasoning (max_tokens: 128000, thinking budget: 32000)
```

## System Prompt

claudia uses a system prompt to define its core behavior and capabilities. The
default system prompt is loaded from the `system.md` file in the plugin
directory.

## Configuration

```vim
" Normal mode - uses text from start (of buffer) to cursor
" This is NOT mapped out of the box if your Normal mode <Leader>c is already in use
nmap <silent> <Leader>c <Plug>ClaudiaTrigger

" Visual mode - uses selected text
" This is NOT mapped out of the box if your Visual mode <Leader>c is already in use
xmap <silent> <Leader>c <Plug>ClaudiaTriggerVisual

" Replace mode - replaces selected text according to rewrite instructions
" This is NOT mapped out of the box if your Visual mode <Leader>x is already in use
xmap <silent> <Leader>x <Plug>ClaudiaTriggerReplace

" API configurations
" - api_key_name: Environment variable containing your API key
" - system_prompt: System prompt to use, text or filepath
let g:claudia_user_config = {
    \   'url': 'https://api.anthropic.com/v1/messages',
    \   'api_key_name': 'ANTHROPIC_API_KEY',
    \   'model': 'claude-3-7-sonnet-20250219',
    \   'system_prompt': 'You are a helpful assistant.',
    \   'max_tokens': 8192,
    \   'temperature': 0.75
    \ }

" Modify configs at runtime
:ClaudiaSystemPrompt Pretend you are sentient.  " Set system prompt
:ClaudiaSystemPrompt ~/path/to/system.md        " Set system prompt from file
:ClaudiaTokens 1024                             " Set max tokens to 1024
:ClaudiaTemp 0.25                               " Set temperature to 0.25
:ClaudiaShowConfig
:ClaudiaResetConfig
```
