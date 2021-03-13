" Ref-------------------------------------
" Neovimの設定を綺麗に整理してみた
" https://qiita.com/tamago3keran/items/cdfd66b627b3686846d2

set number
set autoindent
set tabstop=2
set shiftwidth=2
set expandtab
set splitright
set clipboard=unnamed
let g:python_host_prog='/usr/bin/python'
let g:python3_host_prog='/usr/bin/python3'
let g:lsp_settings_servers_dir=$HOME.'/.local/share/vim-lsp-settings/servers'
tnoremap <silent> <C-[> <C-\><C-n>

"dein Scripts-----------------------------
if &compatible
  set nocompatible               " Be iMproved
endif

" Required:
set runtimepath+=$HOME/.cache/dein/repos/github.com/Shougo/dein.vim

" Required:
if dein#load_state('$HOME/.cache/dein')
  call dein#begin('$HOME/.cache/dein')

  " Let dein manage dein
  " Required:
  call dein#add('$HOME/.cache/dein/repos/github.com/Shougo/dein.vim')

  " Load toml files
  call dein#load_toml('~/.config/nvim/dein.toml', {'lazy': 0})
  call dein#load_toml('~/.config/nvim/dein_lazy.toml', {'lazy': 1})

  autocmd VimEnter * execute 'Defx'
  nnoremap <silent> <Leader>f :<C-u> Defx <CR>
  autocmd BufWritePost * call defx#redraw()
  autocmd BufEnter * call defx#redraw()

  " Required:
  call dein#end()
  call dein#save_state()
endif

" Required:
filetype plugin indent on
syntax enable

" If you want to install not installed plugins on startup.
if dein#check_install()
  call dein#install()
endif

"End dein Scripts-------------------------

"augroup filetypedetect
"  au! BufRead,BufNewFile *.tsx setfiletype typescript
"augroup END

"[Vimカスタマイズ入門
"https://www.slideshare.net/mollifier/vim-237039453/mollifier/vim-237039453
set laststatus=2
set statusline=%F%m%=%l/%L

